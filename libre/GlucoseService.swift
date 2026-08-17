//
//  GlucoseService.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Foundation
import SwiftUI
import SwiftData

// MARK: - Glucose Service

@MainActor
@Observable
final class GlucoseService {
    private(set) var currentReading: GlucoseReading?
    private(set) var historyData: [GlucoseDataPoint] = []
    private(set) var connectionStatus: ConnectionStatus = .disconnected
    private(set) var lastUpdated: Date?
    private(set) var patientName: String?
    private(set) var patientId: String?

    /// Whether the current reading is older than 5 minutes and may be stale
    var isDataStale: Bool {
        guard let lastUpdated else { return false }
        return Date.now.timeIntervalSince(lastUpdated) > 5 * 60
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
        if let savedPatientId = try? self.keychainService.load(key: LibreKeychainKey.patientId) {
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

            let response = try await api.login(email: email, password: password)

            // Save credentials and region securely
            try? keychainService.save(key: LibreKeychainKey.email, value: email)
            try? keychainService.save(key: LibreKeychainKey.password, value: password)
            try? keychainService.save(key: LibreKeychainKey.region, value: region.rawValue)

            // Persist the session token so future launches (and the CLI)
            // can skip the password login while it's still valid.
            if let authData = response.data {
                let expiry = LibreLinkAPI.expiryDate(from: authData.authTicket)
                try? keychainService.save(key: LibreKeychainKey.token, value: authData.authTicket.token)
                try? keychainService.save(
                    key: LibreKeychainKey.tokenExpiry,
                    value: String(expiry.timeIntervalSince1970)
                )
                try? keychainService.save(key: LibreKeychainKey.userId, value: authData.user.id)
            }

            // Get connections
            let connections = try await api.getConnections()
            if let firstConnection = connections.first {
                patientId = firstConnection.patientId
                patientName = "\(firstConnection.firstName) \(firstConnection.lastName)"
                // Persist patientId and name
                try? keychainService.save(key: LibreKeychainKey.patientId, value: firstConnection.patientId)
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
        for key in [
            LibreKeychainKey.email,
            LibreKeychainKey.password,
            LibreKeychainKey.token,
            LibreKeychainKey.tokenExpiry,
            LibreKeychainKey.userId,
            LibreKeychainKey.patientId
        ] {
            try? keychainService.delete(key: key)
        }
        UserDefaults.standard.removeObject(forKey: "patientName")
        currentReading = nil
        historyData = []
        patientId = nil
        patientName = nil
        connectionStatus = .disconnected
        consecutiveFailures = 0
    }

    func tryAutoLogin() async -> Bool {
        // Load saved region or default to US
        let regionString = try? keychainService.load(key: LibreKeychainKey.region)
        let region = LibreRegion(rawValue: regionString ?? "us") ?? .us

        // First choice: restore the saved session token and skip the
        // password login entirely.
        if await tryRestoreSession(region: region) {
            return true
        }

        guard let email = try? keychainService.load(key: LibreKeychainKey.email),
              let password = try? keychainService.load(key: LibreKeychainKey.password) else {
            return false
        }

        do {
            try await login(email: email, password: password, region: region)
            return true
        } catch {
            return false
        }
    }

    /// Restores a persisted, unexpired session token. Returns false (after
    /// discarding the token, so we don't retry a rejected one) if anything
    /// is missing or the API refuses it.
    private func tryRestoreSession(region: LibreRegion) async -> Bool {
        guard let token = try? keychainService.load(key: LibreKeychainKey.token),
              let expiryString = try? keychainService.load(key: LibreKeychainKey.tokenExpiry),
              let expiryEpoch = Double(expiryString),
              Date(timeIntervalSince1970: expiryEpoch) > .now,
              let userId = try? keychainService.load(key: LibreKeychainKey.userId) else {
            return false
        }

        selectedRegion = region
        connectionStatus = .connecting
        await api.setRegion(region.rawValue)
        await api.restoreSession(
            token: token,
            expiry: Date(timeIntervalSince1970: expiryEpoch),
            userId: userId
        )

        do {
            // getConnections doubles as token validation.
            let connections = try await api.getConnections()
            if let firstConnection = connections.first {
                patientId = firstConnection.patientId
                patientName = "\(firstConnection.firstName) \(firstConnection.lastName)"
                try? keychainService.save(key: LibreKeychainKey.patientId, value: firstConnection.patientId)
                UserDefaults.standard.set(patientName, forKey: "patientName")
            }
            connectionStatus = .connected
            consecutiveFailures = 0
            await refresh()
            return true
        } catch {
            // Token rejected or network trouble — drop it and let the
            // password path take over.
            try? keychainService.delete(key: LibreKeychainKey.token)
            try? keychainService.delete(key: LibreKeychainKey.tokenExpiry)
            await api.logout()
            connectionStatus = .disconnected
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
        guard let patientId else { return }

        do {
            let result = try await api.getGlucoseDataWithHistory(patientId: patientId)
            currentReading = result.current
            historyData = result.history
            lastUpdated = Date.now
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
        } catch {
            consecutiveFailures += 1
            connectionStatus = .error(error.localizedDescription)
        }
    }

    // MARK: - Settings

    func updateRefreshInterval(_ interval: TimeInterval) {
        refreshInterval = interval
        restartMonitoringIfActive()
    }

    /// Restarts the refresh loop so a changed interval takes effect;
    /// does nothing if monitoring isn't running.
    func restartMonitoringIfActive() {
        if refreshTask != nil {
            startMonitoring()
        }
    }

    // MARK: - Persistence

    func loadCachedData() {
        guard let modelContext else { return }
        let store = GlucoseCacheStore(context: modelContext)

        if let latestReading = try? store.latestReading() {
            currentReading = latestReading.toGlucoseReading()
            lastUpdated = latestReading.timestamp
        }

        if let cachedHistory = try? store.recentHistory() {
            historyData = cachedHistory.map { $0.toGlucoseDataPoint() }
        }
    }

    private func saveToCache(current: GlucoseReading, history: [GlucoseDataPoint]) {
        guard let modelContext else { return }
        try? GlucoseCacheStore(context: modelContext).save(current: current, history: history)
    }
}
