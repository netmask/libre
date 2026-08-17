//
//  libreTests.swift
//  libreTests
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Testing
import Foundation
import SwiftData
@testable import libre

// MARK: - Mock URL Session

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var mockData: Data?
    var mockResponse: HTTPURLResponse?
    var mockError: Error?

    /// FIFO queue of responses for flows that make several requests
    /// (login → connections → glucose). Falls back to mockData/mockResponse
    /// when empty.
    var queuedResponses: [(statusCode: Int, data: Data)] = []

    /// Every URL requested, in order, so tests can assert which endpoints
    /// (and which regional hosts) were hit.
    private(set) var requestedURLs: [URL] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let url = request.url {
            requestedURLs.append(url)
        }

        if let error = mockError {
            throw error
        }

        if !queuedResponses.isEmpty {
            let next = queuedResponses.removeFirst()
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: next.statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (next.data, response)
        }

        let data = mockData ?? Data()
        let response = mockResponse ?? HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!

        return (data, response)
    }

    func setResponse(statusCode: Int, data: Data) {
        mockData = data
        mockResponse = HTTPURLResponse(
            url: URL(string: "https://api-eu.libreview.io")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
    }
}

// MARK: - Fixtures

enum Fixtures {
    static func loginResponse(
        token: String = "test-token",
        expires: Int = Int(Date.now.timeIntervalSince1970) + 3600
    ) -> LoginResponse {
        LoginResponse(
            status: 0,
            data: LoginResponse.AuthData(
                authTicket: LoginResponse.AuthTicket(
                    token: token,
                    expires: expires,
                    duration: 3600
                ),
                user: LoginResponse.User(
                    id: "user-123",
                    firstName: "John",
                    lastName: "Doe",
                    email: "test@example.com"
                )
            )
        )
    }

    static func loginJSON() throws -> Data {
        try JSONEncoder().encode(loginResponse())
    }

    static let redirectJSON = Data("""
    {"status":0,"data":{"redirect":true,"region":"eu"}}
    """.utf8)

    static let connectionsJSON = Data("""
    {"status":0,"data":[{"patientId":"patient-123","firstName":"John","lastName":"Doe"}]}
    """.utf8)

    static let emptyConnectionsJSON = Data("""
    {"status":0,"data":[]}
    """.utf8)

    static let glucoseJSON = Data("""
    {
        "status": 0,
        "data": {
            "connection": {
                "glucoseMeasurement": {
                    "ValueInMgPerDl": 115,
                    "TrendArrow": 3,
                    "Timestamp": "1/9/2026 10:30:00 AM",
                    "isHigh": false,
                    "isLow": false
                }
            }
        }
    }
    """.utf8)
}

// MARK: - Mock Keychain Service

@MainActor
final class MockKeychainService: KeychainServiceProtocol {
    private var storage: [String: String] = [:]

    func save(key: String, value: String) throws {
        storage[key] = value
    }

    func load(key: String) throws -> String? {
        return storage[key]
    }

    func delete(key: String) throws {
        storage.removeValue(forKey: key)
    }
}

// MARK: - Model Tests

struct ModelTests {

    @Test func glucoseReadingDisplayValue() {
        let reading = GlucoseReading(
            value: 120,
            trend: .flat,
            timestamp: Date.now,
            isHigh: false,
            isLow: false
        )
        #expect(reading.displayValue == "120")
    }

    @Test func glucoseReadingStatusColorNormal() {
        let reading = GlucoseReading(
            value: 100,
            trend: .flat,
            timestamp: Date.now,
            isHigh: false,
            isLow: false
        )
        #expect(reading.statusColor == .normal)
    }

    @Test func glucoseReadingStatusColorHigh() {
        let reading = GlucoseReading(
            value: 200,
            trend: .singleUp,
            timestamp: Date.now,
            isHigh: true,
            isLow: false
        )
        #expect(reading.statusColor == .high)
    }

    @Test func glucoseReadingStatusColorLow() {
        let reading = GlucoseReading(
            value: 60,
            trend: .singleDown,
            timestamp: Date.now,
            isHigh: false,
            isLow: true
        )
        #expect(reading.statusColor == .low)
    }

    @Test func glucoseDataPointIdentityIsStable() {
        let timestamp = Date.now
        let a = GlucoseDataPoint(value: 100, timestamp: timestamp)
        let b = GlucoseDataPoint(value: 100, timestamp: timestamp)
        // Re-parsed points with the same data must compare equal and share
        // identity, so chart diffing works across refreshes.
        #expect(a == b)
        #expect(a.id == b.id)
    }

    @Test func trendArrowSymbols() {
        #expect(TrendArrow.flat.symbol == "→")
        #expect(TrendArrow.singleUp.symbol == "↑")
        #expect(TrendArrow.singleDown.symbol == "↓")
        #expect(TrendArrow.fortyFiveUp.symbol == "↗")
        #expect(TrendArrow.fortyFiveDown.symbol == "↘")
        #expect(TrendArrow.notComputable.symbol == "?")
    }

    @Test func trendArrowDescriptions() {
        #expect(TrendArrow.flat.description == "Stable")
        #expect(TrendArrow.singleUp.description == "Rising quickly")
        #expect(TrendArrow.singleDown.description == "Falling quickly")
    }

    @Test func connectionStatusDescriptions() {
        #expect(ConnectionStatus.disconnected.description == "Disconnected")
        #expect(ConnectionStatus.connecting.description == "Connecting...")
        #expect(ConnectionStatus.connected.description == "Connected")
        #expect(ConnectionStatus.error("Test").description == "Error: Test")
    }
}

// MARK: - Glucose Unit Tests

struct GlucoseUnitTests {

    @Test func mgdLIsIdentity() {
        #expect(GlucoseUnit.mgdL.convert(105) == 105.0)
        #expect(GlucoseUnit.mgdL.format(105) == "105")
    }

    @Test func mmolConversion() {
        let converted = GlucoseUnit.mmolL.convert(180)
        #expect(abs(converted - 9.99) < 0.01)
    }

    @Test func mmolFormatting() {
        // 18 mg/dL is ~0.999 mmol/L which should display as 1.0 (locale-safe
        // comparison against the same format style).
        let expected = 1.0.formatted(.number.precision(.fractionLength(1)))
        #expect(GlucoseUnit.mmolL.format(18) == expected)
    }
}

// MARK: - Glucose Stats Tests

struct GlucoseStatsTests {

    private func point(_ value: Int, minutesAgo: Double, now: Date) -> GlucoseDataPoint {
        GlucoseDataPoint(value: value, timestamp: now.addingTimeInterval(-minutesAgo * 60))
    }

    @Test func emptyPointsProduceEmptyStats() {
        let stats = GlucoseStats(points: [], range: .h6)
        #expect(stats == .empty)
    }

    @Test func computesAverageMinMaxAndTIR() {
        let now = Date.now
        let points = [
            point(100, minutesAgo: 10, now: now), // in range
            point(60, minutesAgo: 20, now: now),  // low
            point(200, minutesAgo: 30, now: now), // high
            point(150, minutesAgo: 40, now: now)  // in range
        ]
        let stats = GlucoseStats(points: points, range: .h6, now: now)

        #expect(stats.count == 4)
        #expect(stats.timeInRange == 0.5)
        #expect(stats.average == 128) // mean 127.5 rounds up
        #expect(stats.minimum == 60)
        #expect(stats.maximum == 200)
    }

    @Test func gmiUsesADAGFormula() {
        let now = Date.now
        let points = [point(100, minutesAgo: 5, now: now)]
        let stats = GlucoseStats(points: points, range: .h6, now: now)
        // GMI(%) = 3.31 + 0.02392 × mean
        #expect(abs(stats.gmi - (3.31 + 0.02392 * 100)) < 0.0001)
    }

    @Test func pointsOutsideRangeAreExcluded() {
        let now = Date.now
        let points = [
            point(100, minutesAgo: 10, now: now),
            point(300, minutesAgo: 7 * 60, now: now) // older than the 6h range
        ]
        let stats = GlucoseStats(points: points, range: .h6, now: now)
        #expect(stats.count == 1)
        #expect(stats.maximum == 100)
    }
}

// MARK: - Notification Alert Logic Tests

struct NotificationAlertTests {

    private let thresholds = NotificationService.Thresholds(
        low: 70, high: 180, urgentLow: 55, urgentHigh: 250
    )

    @Test func normalReadingTriggersNothing() {
        let alerts = NotificationService.triggeredAlerts(value: 100, trend: .flat, thresholds: thresholds)
        #expect(alerts.isEmpty)
    }

    @Test func lowReadingTriggersLow() {
        let alerts = NotificationService.triggeredAlerts(value: 65, trend: .flat, thresholds: thresholds)
        #expect(alerts == [.low])
    }

    @Test func urgentLowBeatsLow() {
        let alerts = NotificationService.triggeredAlerts(value: 50, trend: .flat, thresholds: thresholds)
        #expect(alerts == [.urgentLow])
    }

    @Test func highReadingTriggersHigh() {
        let alerts = NotificationService.triggeredAlerts(value: 200, trend: .flat, thresholds: thresholds)
        #expect(alerts == [.high])
    }

    @Test func urgentHighBeatsHigh() {
        let alerts = NotificationService.triggeredAlerts(value: 300, trend: .flat, thresholds: thresholds)
        #expect(alerts == [.urgentHigh])
    }

    @Test func fastTrendsTriggerTrendAlerts() {
        #expect(NotificationService.triggeredAlerts(value: 100, trend: .singleDown, thresholds: thresholds) == [.fallingFast])
        #expect(NotificationService.triggeredAlerts(value: 100, trend: .singleUp, thresholds: thresholds) == [.risingFast])
    }

    @Test func thresholdAndTrendAlertsCombine() {
        let alerts = NotificationService.triggeredAlerts(value: 50, trend: .singleDown, thresholds: thresholds)
        #expect(alerts == [.urgentLow, .fallingFast])
    }
}

// MARK: - LibreLink API Tests

struct LibreLinkAPITests {

    @Test func loginWithValidCredentials() async throws {
        let mockSession = MockURLSession()
        mockSession.setResponse(statusCode: 200, data: try Fixtures.loginJSON())

        let api = LibreLinkAPI(session: mockSession)
        let response = try await api.login(email: "test@example.com", password: "password123")

        #expect(response.status == 0)
        #expect(response.data?.user.email == "test@example.com")
        #expect(await api.isAuthenticated == true)
    }

    @Test func loginWithInvalidCredentials() async throws {
        let mockSession = MockURLSession()
        mockSession.setResponse(statusCode: 401, data: Data())

        let api = LibreLinkAPI(session: mockSession)

        do {
            _ = try await api.login(email: "wrong@example.com", password: "wrongpassword")
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as LibreAPIError {
            #expect(error == .invalidCredentials)
        }
    }

    @Test func loginWithNetworkError() async throws {
        let mockSession = MockURLSession()
        mockSession.mockError = URLError(.notConnectedToInternet)

        let api = LibreLinkAPI(session: mockSession)

        do {
            _ = try await api.login(email: "test@example.com", password: "password")
            #expect(Bool(false), "Should have thrown an error")
        } catch {
            // Expected network error
            #expect(error is URLError)
        }
    }

    @Test func loginRateLimited() async throws {
        let mockSession = MockURLSession()
        mockSession.setResponse(statusCode: 429, data: Data())

        let api = LibreLinkAPI(session: mockSession)

        do {
            _ = try await api.login(email: "test@example.com", password: "password")
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as LibreAPIError {
            #expect(error == .rateLimited)
        }
    }

    @Test func loginFollowsRegionRedirect() async throws {
        // Regression test for the redirect fix: the API signals a redirect
        // with status 0 and a `redirect` flag, and login must retry against
        // the new region's host.
        let mockSession = MockURLSession()
        mockSession.queuedResponses = [
            (200, Fixtures.redirectJSON),
            (200, try Fixtures.loginJSON())
        ]

        let api = LibreLinkAPI(session: mockSession)
        let response = try await api.login(email: "test@example.com", password: "password")

        #expect(response.status == 0)
        #expect(await api.isAuthenticated == true)
        #expect(mockSession.requestedURLs.count == 2)
        #expect(mockSession.requestedURLs[0].host()?.contains("api-us") == true)
        #expect(mockSession.requestedURLs[1].host()?.contains("api-eu") == true)
    }

    @Test func getConnectionsNotAuthenticated() async throws {
        let mockSession = MockURLSession()
        let api = LibreLinkAPI(session: mockSession)

        do {
            _ = try await api.getConnections()
            #expect(Bool(false), "Should have thrown an error")
        } catch let error as LibreAPIError {
            #expect(error == .notAuthenticated)
        }
    }

    @Test func getGlucoseDataParsesCorrectly() async throws {
        let mockSession = MockURLSession()
        mockSession.setResponse(statusCode: 200, data: try Fixtures.loginJSON())

        let api = LibreLinkAPI(session: mockSession)
        _ = try await api.login(email: "test@example.com", password: "password")

        mockSession.setResponse(statusCode: 200, data: Fixtures.glucoseJSON)

        let reading = try await api.getGlucoseData(patientId: "patient-123")

        #expect(reading.value == 115)
        #expect(reading.trend == .flat)
        #expect(reading.isHigh == false)
        #expect(reading.isLow == false)
    }

    @Test func restoreSessionAuthenticatesWithoutLogin() async throws {
        let mockSession = MockURLSession()
        let api = LibreLinkAPI(session: mockSession)

        await api.restoreSession(
            token: "restored-token",
            expiry: Date.now.addingTimeInterval(3600),
            userId: "user-123"
        )

        #expect(await api.isAuthenticated == true)

        mockSession.setResponse(statusCode: 200, data: Fixtures.connectionsJSON)
        let connections = try await api.getConnections()
        #expect(connections.first?.patientId == "patient-123")
        #expect(mockSession.requestedURLs.allSatisfy { !$0.path().contains("auth/login") })
    }

    @Test func logoutClearsAuthentication() async throws {
        let mockSession = MockURLSession()
        mockSession.setResponse(statusCode: 200, data: try Fixtures.loginJSON())

        let api = LibreLinkAPI(session: mockSession)
        _ = try await api.login(email: "test@example.com", password: "password")

        #expect(await api.isAuthenticated == true)

        await api.logout()

        #expect(await api.isAuthenticated == false)
    }
}

// MARK: - Keychain Service Tests

@MainActor
struct KeychainServiceTests {

    @Test func saveAndLoadValue() throws {
        let keychain = MockKeychainService()

        try keychain.save(key: "test_key", value: "test_value")
        let loaded = try keychain.load(key: "test_key")

        #expect(loaded == "test_value")
    }

    @Test func loadNonExistentKey() throws {
        let keychain = MockKeychainService()

        let loaded = try keychain.load(key: "nonexistent")

        #expect(loaded == nil)
    }

    @Test func deleteValue() throws {
        let keychain = MockKeychainService()

        try keychain.save(key: "test_key", value: "test_value")
        try keychain.delete(key: "test_key")
        let loaded = try keychain.load(key: "test_key")

        #expect(loaded == nil)
    }

    @Test func overwriteValue() throws {
        let keychain = MockKeychainService()

        try keychain.save(key: "test_key", value: "value1")
        try keychain.save(key: "test_key", value: "value2")
        let loaded = try keychain.load(key: "test_key")

        #expect(loaded == "value2")
    }
}

// MARK: - GlucoseService Tests

@MainActor
struct GlucoseServiceTests {

    @Test func initialState() {
        let service = GlucoseService(
            api: LibreLinkAPI(session: MockURLSession()),
            keychainService: MockKeychainService()
        )

        #expect(service.currentReading == nil)
        #expect(service.connectionStatus == .disconnected)
        #expect(service.lastUpdated == nil)
        #expect(service.patientName == nil)
    }

    @Test func updateRefreshInterval() {
        let service = GlucoseService(
            api: LibreLinkAPI(session: MockURLSession()),
            keychainService: MockKeychainService()
        )

        service.updateRefreshInterval(120)

        #expect(service.refreshInterval == 120)
    }

    @Test func loginPersistsSessionToken() async throws {
        let mockSession = MockURLSession()
        mockSession.queuedResponses = [
            (200, try Fixtures.loginJSON()),
            (200, Fixtures.connectionsJSON),
            (200, Fixtures.glucoseJSON)
        ]
        let mockKeychain = MockKeychainService()

        let service = GlucoseService(
            api: LibreLinkAPI(session: mockSession),
            keychainService: mockKeychain
        )

        try await service.login(email: "test@example.com", password: "password", region: .us)

        #expect(try mockKeychain.load(key: LibreKeychainKey.token) == "test-token")
        #expect(try mockKeychain.load(key: LibreKeychainKey.userId) == "user-123")
        #expect(try mockKeychain.load(key: LibreKeychainKey.tokenExpiry) != nil)
        #expect(service.connectionStatus == .connected)
        #expect(service.patientName == "John Doe")
    }

    @Test func autoLoginRestoresSavedSessionWithoutPasswordLogin() async throws {
        let mockSession = MockURLSession()
        mockSession.queuedResponses = [
            (200, Fixtures.connectionsJSON),
            (200, Fixtures.glucoseJSON)
        ]
        let mockKeychain = MockKeychainService()
        try mockKeychain.save(key: LibreKeychainKey.token, value: "saved-token")
        try mockKeychain.save(
            key: LibreKeychainKey.tokenExpiry,
            value: String(Date.now.addingTimeInterval(3600).timeIntervalSince1970)
        )
        try mockKeychain.save(key: LibreKeychainKey.userId, value: "user-123")
        try mockKeychain.save(key: LibreKeychainKey.region, value: "us")

        let service = GlucoseService(
            api: LibreLinkAPI(session: mockSession),
            keychainService: mockKeychain
        )

        let success = await service.tryAutoLogin()

        #expect(success == true)
        #expect(service.connectionStatus == .connected)
        #expect(service.patientName == "John Doe")
        #expect(mockSession.requestedURLs.allSatisfy { !$0.path().contains("auth/login") })
    }

    @Test func expiredSavedTokenFallsBackToPasswordLogin() async throws {
        let mockSession = MockURLSession()
        mockSession.queuedResponses = [
            (200, try Fixtures.loginJSON()),
            (200, Fixtures.connectionsJSON),
            (200, Fixtures.glucoseJSON)
        ]
        let mockKeychain = MockKeychainService()
        try mockKeychain.save(key: LibreKeychainKey.token, value: "expired-token")
        try mockKeychain.save(
            key: LibreKeychainKey.tokenExpiry,
            value: String(Date.now.addingTimeInterval(-3600).timeIntervalSince1970)
        )
        try mockKeychain.save(key: LibreKeychainKey.userId, value: "user-123")
        try mockKeychain.save(key: LibreKeychainKey.email, value: "test@example.com")
        try mockKeychain.save(key: LibreKeychainKey.password, value: "password")

        let service = GlucoseService(
            api: LibreLinkAPI(session: mockSession),
            keychainService: mockKeychain
        )

        let success = await service.tryAutoLogin()

        #expect(success == true)
        #expect(service.connectionStatus == .connected)
        #expect(mockSession.requestedURLs.contains { $0.path().contains("auth/login") })
    }

    @Test func logoutClearsData() async throws {
        let mockSession = MockURLSession()
        let mockKeychain = MockKeychainService()

        // Store credentials and a session
        try mockKeychain.save(key: LibreKeychainKey.email, value: "test@example.com")
        try mockKeychain.save(key: LibreKeychainKey.password, value: "password")
        try mockKeychain.save(key: LibreKeychainKey.token, value: "token")
        try mockKeychain.save(key: LibreKeychainKey.tokenExpiry, value: "12345")
        try mockKeychain.save(key: LibreKeychainKey.userId, value: "user-123")

        let service = GlucoseService(
            api: LibreLinkAPI(session: mockSession),
            keychainService: mockKeychain
        )

        service.logout()

        #expect(service.currentReading == nil)
        #expect(service.connectionStatus == .disconnected)
        #expect(try mockKeychain.load(key: LibreKeychainKey.email) == nil)
        #expect(try mockKeychain.load(key: LibreKeychainKey.password) == nil)
        #expect(try mockKeychain.load(key: LibreKeychainKey.token) == nil)
        #expect(try mockKeychain.load(key: LibreKeychainKey.tokenExpiry) == nil)
        #expect(try mockKeychain.load(key: LibreKeychainKey.userId) == nil)
    }

    @Test func tryAutoLoginWithNoCredentials() async {
        let service = GlucoseService(
            api: LibreLinkAPI(session: MockURLSession()),
            keychainService: MockKeychainService()
        )

        let success = await service.tryAutoLogin()

        #expect(success == false)
    }
}

// MARK: - Glucose Cache Store Tests

@MainActor
struct GlucoseCacheStoreTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: GlucoseSchema.schema, configurations: [config])
        return ModelContext(container)
    }

    private func reading(value: Int, now: Date) -> GlucoseReading {
        GlucoseReading(value: value, trend: .flat, timestamp: now, isHigh: false, isLow: false)
    }

    @Test func savesLatestReadingAndHistory() throws {
        let context = try makeContext()
        let store = GlucoseCacheStore(context: context)
        let now = Date.now

        let history = [
            GlucoseDataPoint(value: 100, timestamp: now.addingTimeInterval(-600)),
            GlucoseDataPoint(value: 110, timestamp: now.addingTimeInterval(-300))
        ]
        try store.save(current: reading(value: 115, now: now), history: history, now: now)

        #expect(try store.latestReading()?.value == 115)
        #expect(try store.recentHistory(now: now).count == 2)
    }

    @Test func replacesLatestFlagOnSubsequentSave() throws {
        let context = try makeContext()
        let store = GlucoseCacheStore(context: context)
        let now = Date.now

        try store.save(current: reading(value: 100, now: now.addingTimeInterval(-300)), history: [], now: now)
        try store.save(current: reading(value: 120, now: now), history: [], now: now)

        #expect(try store.latestReading()?.value == 120)
    }

    @Test func deduplicatesHistoryByTimestamp() throws {
        let context = try makeContext()
        let store = GlucoseCacheStore(context: context)
        let now = Date.now

        let point = GlucoseDataPoint(value: 100, timestamp: now.addingTimeInterval(-300))
        try store.save(current: reading(value: 100, now: now), history: [point], now: now)
        try store.save(current: reading(value: 105, now: now), history: [point], now: now)

        #expect(try store.recentHistory(now: now).count == 1)
    }

    @Test func prunesDataPastRetention() throws {
        let context = try makeContext()
        let store = GlucoseCacheStore(context: context)
        let now = Date.now

        let oldPoint = GlucoseDataPoint(value: 90, timestamp: now.addingTimeInterval(-25 * 3600))
        try store.save(current: reading(value: 100, now: now), history: [oldPoint], now: now)
        // A later save prunes anything older than the 24h retention window.
        try store.save(current: reading(value: 105, now: now), history: [], now: now)

        let allPoints = try context.fetch(FetchDescriptor<PersistedGlucoseDataPoint>())
        #expect(allPoints.isEmpty)
    }
}

// MARK: - API Error Tests

struct APIErrorTests {

    @Test func errorDescriptions() {
        #expect(LibreAPIError.invalidCredentials.localizedDescription == "Invalid email or password")
        #expect(LibreAPIError.noData.localizedDescription == "No glucose data available")
        #expect(LibreAPIError.notAuthenticated.localizedDescription == "Please log in")
        #expect(LibreAPIError.rateLimited.localizedDescription == "Too many requests, please wait")
        #expect(LibreAPIError.serverError(500).localizedDescription == "Server error: 500")
        #expect(LibreAPIError.networkError("timeout").localizedDescription == "Network error: timeout")
    }

    @Test func errorEquality() {
        #expect(LibreAPIError.invalidCredentials == LibreAPIError.invalidCredentials)
        #expect(LibreAPIError.serverError(500) == LibreAPIError.serverError(500))
        #expect(LibreAPIError.serverError(500) != LibreAPIError.serverError(404))
    }
}
