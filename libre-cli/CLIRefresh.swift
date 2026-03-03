//
//  CLIRefresh.swift
//  libre-cli
//
//  Background refresh: fetches fresh data from LibreLinkUp API
//  and writes it to the shared SwiftData store.
//
//  This runs in a detached child process spawned by the main CLI,
//  with stdout/stderr redirected to /dev/null.
//

import Foundation
import SwiftData

/// Performs a full API refresh cycle. Blocks until complete.
func performBackgroundRefresh() {
    // File-based lock to prevent concurrent refreshes
    let lockURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("libre-cli-refresh.lock")

    if let lockData = try? Data(contentsOf: lockURL),
       let lockTime = String(data: lockData, encoding: .utf8),
       let lockDate = Double(lockTime),
       Date().timeIntervalSince1970 - lockDate < 30 {
        return // Another refresh is already running
    }

    // Write lock
    try? "\(Date().timeIntervalSince1970)".data(using: .utf8)?.write(to: lockURL)
    defer { try? FileManager.default.removeItem(at: lockURL) }

    // Load credentials
    let keychain = KeychainService()
    guard let email = try? keychain.load(key: "libre_email"),
          let password = try? keychain.load(key: "libre_password") else {
        return
    }

    let regionStr = (try? keychain.load(key: "libre_region")) ?? "us"
    let region = LibreRegion(rawValue: regionStr) ?? .us

    guard let patientId = try? keychain.load(key: "libre_patient_id") else {
        return
    }

    // Run async API work synchronously
    let semaphore = DispatchSemaphore(value: 0)

    Task {
        defer { semaphore.signal() }

        do {
            let api = LibreLinkAPI()
            await api.setRegion(region.rawValue)
            _ = try await api.login(email: email, password: password)

            let result = try await api.getGlucoseDataWithHistory(patientId: patientId)

            // Write to SwiftData
            let container = try createModelContainer()
            let context = ModelContext(container)

            // Clear old "latest" flags
            let latestDescriptor = FetchDescriptor<PersistedGlucoseReading>(
                predicate: #Predicate { $0.isLatest == true }
            )
            if let oldLatest = try? context.fetch(latestDescriptor) {
                for reading in oldLatest {
                    reading.isLatest = false
                }
            }

            // Insert new latest reading
            let persisted = PersistedGlucoseReading(from: result.current, isLatest: true)
            context.insert(persisted)

            // Batch-check existing timestamps to avoid duplicates
            let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
            let existingDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
                predicate: #Predicate { $0.timestamp >= twentyFourHoursAgo }
            )
            let existingTimestamps: Set<Date>
            if let existing = try? context.fetch(existingDescriptor) {
                existingTimestamps = Set(existing.map { $0.timestamp })
            } else {
                existingTimestamps = []
            }

            for point in result.history {
                if !existingTimestamps.contains(point.timestamp) {
                    context.insert(PersistedGlucoseDataPoint(from: point))
                }
            }

            // Clean up old data
            let oldReadingsDescriptor = FetchDescriptor<PersistedGlucoseReading>(
                predicate: #Predicate { $0.timestamp < twentyFourHoursAgo }
            )
            if let old = try? context.fetch(oldReadingsDescriptor) {
                for r in old { context.delete(r) }
            }

            let oldPointsDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
                predicate: #Predicate { $0.timestamp < twentyFourHoursAgo }
            )
            if let old = try? context.fetch(oldPointsDescriptor) {
                for p in old { context.delete(p) }
            }

            try context.save()
        } catch {
            // Silently fail -- next CLI invocation will retry
        }
    }

    _ = semaphore.wait(timeout: .now() + 30)
}
