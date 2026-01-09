//
//  GlucoseService.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Glucose Service Protocol

protocol GlucoseServiceProtocol: AnyObject {
    var currentReading: GlucoseReading? { get }
    var connectionStatus: ConnectionStatus { get }
    var lastUpdated: Date? { get }
    var patientName: String? { get }

    func login(email: String, password: String, region: LibreRegion) async throws
    func logout()
    func startMonitoring()
    func stopMonitoring()
    func refresh() async
}

// MARK: - Glucose Service

@MainActor
@Observable
final class GlucoseService: GlucoseServiceProtocol {
    private(set) var currentReading: GlucoseReading?
    private(set) var historyData: [GlucoseDataPoint] = []
    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var lastUpdated: Date?
    private(set) var patientName: String?
    private(set) var patientId: String?
    var selectedRegion: LibreRegion = .us

    private let api: LibreLinkAPI
    private let keychainService: KeychainServiceProtocol
    private let modelContext: ModelContext?
    private var refreshTask: Task<Void, Never>?
    var refreshInterval: TimeInterval = 60 // seconds

    init(
        api: LibreLinkAPI = LibreLinkAPI(),
        keychainService: KeychainServiceProtocol? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.api = api
        self.keychainService = keychainService ?? KeychainService()
        self.modelContext = modelContext
    }

    // MARK: - Authentication

    func login(email: String, password: String, region: LibreRegion) async throws {
        connectionStatus = .connecting
        selectedRegion = region

        do {
            // Set region before login
            await api.setRegion(region.rawValue)

            _ = try await api.login(email: email, password: password)

            // Save credentials and region securely
            try? keychainService.save(key: "libre_email", value: email)
            try? keychainService.save(key: "libre_password", value: password)
            try? keychainService.save(key: "libre_region", value: region.rawValue)

            // Get connections
            let connections = try await api.getConnections()
            if let firstConnection = connections.first {
                patientId = firstConnection.patientId
                patientName = "\(firstConnection.firstName) \(firstConnection.lastName)"
            }

            connectionStatus = .connected

            // Fetch initial reading
            await refresh()

        } catch let error as LibreAPIError {
            connectionStatus = .error(error.localizedDescription)
            throw error
        } catch {
            connectionStatus = .error(error.localizedDescription)
            throw LibreAPIError.networkError(error.localizedDescription)
        }
    }

    func logout() {
        stopMonitoring()
        Task { await api.logout() }
        try? keychainService.delete(key: "libre_email")
        try? keychainService.delete(key: "libre_password")
        try? keychainService.delete(key: "libre_token")
        currentReading = nil
        historyData = []
        patientId = nil
        patientName = nil
        connectionStatus = .disconnected
    }

    func tryAutoLogin() async -> Bool {
        guard let email = try? keychainService.load(key: "libre_email"),
              let password = try? keychainService.load(key: "libre_password") else {
            return false
        }

        // Load saved region or default to US
        let regionString = try? keychainService.load(key: "libre_region")
        let region = LibreRegion(rawValue: regionString ?? "us") ?? .us

        do {
            try await login(email: email, password: password, region: region)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Monitoring

    func startMonitoring() {
        stopMonitoring()

        refreshTask = Task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(refreshInterval))
            }
        }
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func refresh() async {
        guard let patientId = patientId else { return }

        do {
            let result = try await api.getGlucoseDataWithHistory(patientId: patientId)
            currentReading = result.current
            historyData = result.history
            lastUpdated = Date()
            connectionStatus = .connected

            // Persist the data
            saveToCache(current: result.current, history: result.history)
        } catch let error as LibreAPIError {
            connectionStatus = .error(error.localizedDescription)
        } catch {
            connectionStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Settings

    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        if refreshTask != nil {
            startMonitoring() // Restart with new interval
        }
    }

    // MARK: - Persistence

    func loadCachedData() {
        guard let modelContext = modelContext else { return }

        // Load latest reading
        let latestDescriptor = FetchDescriptor<PersistedGlucoseReading>(
            predicate: #Predicate { $0.isLatest == true },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        if let latestReading = try? modelContext.fetch(latestDescriptor).first {
            currentReading = latestReading.toGlucoseReading()
            lastUpdated = latestReading.timestamp
        }

        // Load history from last 24 hours
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let historyDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
            predicate: #Predicate { $0.timestamp >= twentyFourHoursAgo },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        if let cachedHistory = try? modelContext.fetch(historyDescriptor) {
            historyData = cachedHistory.map { $0.toGlucoseDataPoint() }
        }
    }

    private func saveToCache(current: GlucoseReading, history: [GlucoseDataPoint]) {
        guard let modelContext = modelContext else { return }

        // Clear old "latest" flag
        let latestDescriptor = FetchDescriptor<PersistedGlucoseReading>(
            predicate: #Predicate { $0.isLatest == true }
        )
        if let oldLatest = try? modelContext.fetch(latestDescriptor) {
            for reading in oldLatest {
                reading.isLatest = false
            }
        }

        // Save new latest reading
        let persistedReading = PersistedGlucoseReading(from: current, isLatest: true)
        modelContext.insert(persistedReading)

        // Delete old history points (older than 24 hours)
        let twentyFourHoursAgo = Date().addingTimeInterval(-24 * 60 * 60)
        let oldPointsDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
            predicate: #Predicate { $0.timestamp < twentyFourHoursAgo }
        )
        if let oldPoints = try? modelContext.fetch(oldPointsDescriptor) {
            for point in oldPoints {
                modelContext.delete(point)
            }
        }

        // Delete old readings (older than 24 hours)
        let oldReadingsDescriptor = FetchDescriptor<PersistedGlucoseReading>(
            predicate: #Predicate { $0.timestamp < twentyFourHoursAgo }
        )
        if let oldReadings = try? modelContext.fetch(oldReadingsDescriptor) {
            for reading in oldReadings {
                modelContext.delete(reading)
            }
        }

        // Save new history points (avoid duplicates by checking timestamp)
        for dataPoint in history {
            let pointTimestamp = dataPoint.timestamp
            let existingDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
                predicate: #Predicate { $0.timestamp == pointTimestamp }
            )
            let existingCount = (try? modelContext.fetchCount(existingDescriptor)) ?? 0
            if existingCount == 0 {
                let persistedPoint = PersistedGlucoseDataPoint(from: dataPoint)
                modelContext.insert(persistedPoint)
            }
        }

        try? modelContext.save()
    }
}

// MARK: - Keychain Service Protocol

@MainActor
protocol KeychainServiceProtocol: Sendable {
    func save(key: String, value: String) throws
    func load(key: String) throws -> String?
    func delete(key: String) throws
}

// MARK: - Keychain Service

@MainActor
final class KeychainService: KeychainServiceProtocol {
    private let service = "mx.garay.libre"

    enum KeychainError: Error {
        case duplicateEntry
        case unknown(OSStatus)
        case notFound
        case encodingError
    }

    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingError
        }

        // Delete existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }
    }

    func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unknown(status)
        }

        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingError
        }

        return value
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unknown(status)
        }
    }
}
