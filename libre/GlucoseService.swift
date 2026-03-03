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

    /// Whether the current reading is older than 5 minutes and may be stale
    var isDataStale: Bool {
        guard let lastUpdated else { return false }
        return Date().timeIntervalSince(lastUpdated) > 5 * 60
    }

    var selectedRegion: LibreRegion = .us
    var glucoseUnit: GlucoseUnit = .mgdL {
        didSet {
            UserDefaults.standard.set(glucoseUnit.rawValue, forKey: "glucoseUnit")
        }
    }

    private let api: LibreLinkAPI
    private let keychainService: KeychainServiceProtocol
    private let modelContext: ModelContext?
    private var refreshTask: Task<Void, Never>?
    private var consecutiveFailures = 0
    private static let maxBackoffInterval: TimeInterval = 5 * 60

    var refreshInterval: TimeInterval = 60 {
        didSet {
            UserDefaults.standard.set(refreshInterval, forKey: "refreshInterval")
        }
    }

    init(
        api: LibreLinkAPI = LibreLinkAPI(),
        keychainService: KeychainServiceProtocol? = nil,
        modelContext: ModelContext? = nil
    ) {
        self.api = api
        self.keychainService = keychainService ?? KeychainService()
        self.modelContext = modelContext

        // Load saved unit preference
        if let savedUnit = UserDefaults.standard.string(forKey: "glucoseUnit"),
           let unit = GlucoseUnit(rawValue: savedUnit) {
            self.glucoseUnit = unit
        }

        // Load saved refresh interval
        let savedInterval = UserDefaults.standard.double(forKey: "refreshInterval")
        if savedInterval > 0 {
            self.refreshInterval = savedInterval
        }

        // Load persisted patientId
        if let savedPatientId = try? (keychainService ?? KeychainService()).load(key: "libre_patient_id") {
            self.patientId = savedPatientId
        }

        // Load persisted patientName
        if let savedName = UserDefaults.standard.string(forKey: "patientName") {
            self.patientName = savedName
        }
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
                // Persist patientId and name
                try? keychainService.save(key: "libre_patient_id", value: firstConnection.patientId)
                UserDefaults.standard.set(patientName, forKey: "patientName")
            }

            connectionStatus = .connected
            consecutiveFailures = 0

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
        try? keychainService.delete(key: "libre_patient_id")
        UserDefaults.standard.removeObject(forKey: "patientName")
        currentReading = nil
        historyData = []
        patientId = nil
        patientName = nil
        connectionStatus = .disconnected
        consecutiveFailures = 0
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

                // Exponential backoff on consecutive failures
                let delay: TimeInterval
                if consecutiveFailures > 0 {
                    let backoff = refreshInterval * pow(2.0, Double(min(consecutiveFailures, 5)))
                    delay = min(backoff, Self.maxBackoffInterval)
                } else {
                    delay = refreshInterval
                }

                try? await Task.sleep(for: .seconds(delay))
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
            consecutiveFailures = 0

            // Persist the data
            saveToCache(current: result.current, history: result.history)

            // Check for alerts and send notifications
            NotificationService.shared.checkAndNotify(reading: result.current, unit: glucoseUnit)
        } catch LibreAPIError.notAuthenticated {
            // Token expired — attempt re-authentication
            let success = await tryAutoLogin()
            if !success {
                consecutiveFailures += 1
                connectionStatus = .error("Session expired. Please log in again.")
            }
        } catch LibreAPIError.rateLimited {
            consecutiveFailures += 1
            connectionStatus = .error("Rate limited. Backing off...")
        } catch let error as LibreAPIError {
            consecutiveFailures += 1
            connectionStatus = .error(error.localizedDescription)
        } catch {
            consecutiveFailures += 1
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

        // Batch-check existing timestamps to avoid N+1 queries
        let allPointsDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
            predicate: #Predicate { $0.timestamp >= twentyFourHoursAgo }
        )
        let existingTimestamps: Set<Date>
        if let existingPoints = try? modelContext.fetch(allPointsDescriptor) {
            existingTimestamps = Set(existingPoints.map { $0.timestamp })
        } else {
            existingTimestamps = []
        }

        for dataPoint in history {
            if !existingTimestamps.contains(dataPoint.timestamp) {
                let persistedPoint = PersistedGlucoseDataPoint(from: dataPoint)
                modelContext.insert(persistedPoint)
            }
        }

        try? modelContext.save()
    }
}
