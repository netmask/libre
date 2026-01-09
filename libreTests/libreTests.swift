//
//  libreTests.swift
//  libreTests
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Testing
import Foundation
@testable import libre

// MARK: - Mock URL Session

final class MockURLSession: URLSessionProtocol, @unchecked Sendable {
    var mockData: Data?
    var mockResponse: HTTPURLResponse?
    var mockError: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = mockError {
            throw error
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
            timestamp: Date(),
            isHigh: false,
            isLow: false
        )
        #expect(reading.displayValue == "120")
    }

    @Test func glucoseReadingStatusColorNormal() {
        let reading = GlucoseReading(
            value: 100,
            trend: .flat,
            timestamp: Date(),
            isHigh: false,
            isLow: false
        )
        #expect(reading.statusColor == .normal)
    }

    @Test func glucoseReadingStatusColorHigh() {
        let reading = GlucoseReading(
            value: 200,
            trend: .singleUp,
            timestamp: Date(),
            isHigh: true,
            isLow: false
        )
        #expect(reading.statusColor == .high)
    }

    @Test func glucoseReadingStatusColorLow() {
        let reading = GlucoseReading(
            value: 60,
            trend: .singleDown,
            timestamp: Date(),
            isHigh: false,
            isLow: true
        )
        #expect(reading.statusColor == .low)
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

// MARK: - LibreLink API Tests

struct LibreLinkAPITests {

    @Test func loginWithValidCredentials() async throws {
        let mockSession = MockURLSession()

        let loginResponse = LoginResponse(
            status: 0,
            data: LoginResponse.AuthData(
                authTicket: LoginResponse.AuthTicket(
                    token: "test-token",
                    expires: 3600,
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

        let jsonData = try JSONEncoder().encode(loginResponse)
        mockSession.setResponse(statusCode: 200, data: jsonData)

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

        // First, authenticate
        let loginResponse = LoginResponse(
            status: 0,
            data: LoginResponse.AuthData(
                authTicket: LoginResponse.AuthTicket(
                    token: "test-token",
                    expires: 3600,
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
        mockSession.setResponse(statusCode: 200, data: try JSONEncoder().encode(loginResponse))

        let api = LibreLinkAPI(session: mockSession)
        _ = try await api.login(email: "test@example.com", password: "password")

        // Now set up glucose response
        let glucoseJSON = """
        {
            "status": 0,
            "data": {
                "connection": {
                    "glucoseMeasurement": {
                        "Value": 115,
                        "TrendArrow": 3,
                        "Timestamp": "1/9/2026 10:30:00 AM",
                        "isHigh": false,
                        "isLow": false
                    }
                }
            }
        }
        """
        mockSession.setResponse(statusCode: 200, data: glucoseJSON.data(using: .utf8)!)

        let reading = try await api.getGlucoseData(patientId: "patient-123")

        #expect(reading.value == 115)
        #expect(reading.trend == .flat)
        #expect(reading.isHigh == false)
        #expect(reading.isLow == false)
    }

    @Test func logoutClearsAuthentication() async throws {
        let mockSession = MockURLSession()

        let loginResponse = LoginResponse(
            status: 0,
            data: LoginResponse.AuthData(
                authTicket: LoginResponse.AuthTicket(
                    token: "test-token",
                    expires: 3600,
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
        mockSession.setResponse(statusCode: 200, data: try JSONEncoder().encode(loginResponse))

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

    @Test func logoutClearsData() async throws {
        let mockSession = MockURLSession()
        let mockKeychain = MockKeychainService()

        // Store some credentials
        try mockKeychain.save(key: "libre_email", value: "test@example.com")
        try mockKeychain.save(key: "libre_password", value: "password")

        let service = GlucoseService(
            api: LibreLinkAPI(session: mockSession),
            keychainService: mockKeychain
        )

        service.logout()

        #expect(service.currentReading == nil)
        #expect(service.connectionStatus == .disconnected)
        #expect(try mockKeychain.load(key: "libre_email") == nil)
        #expect(try mockKeychain.load(key: "libre_password") == nil)
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

// MARK: - API Error Tests

struct APIErrorTests {

    @Test func errorDescriptions() {
        #expect(LibreAPIError.invalidCredentials.localizedDescription == "Invalid email or password")
        #expect(LibreAPIError.noData.localizedDescription == "No glucose data available")
        #expect(LibreAPIError.notAuthenticated.localizedDescription == "Please log in")
        #expect(LibreAPIError.rateLimited.localizedDescription == "Too many requests, please wait")
        #expect(LibreAPIError.decodingError.localizedDescription == "Failed to parse response")
        #expect(LibreAPIError.serverError(500).localizedDescription == "Server error: 500")
        #expect(LibreAPIError.networkError("timeout").localizedDescription == "Network error: timeout")
    }

    @Test func errorEquality() {
        #expect(LibreAPIError.invalidCredentials == LibreAPIError.invalidCredentials)
        #expect(LibreAPIError.serverError(500) == LibreAPIError.serverError(500))
        #expect(LibreAPIError.serverError(500) != LibreAPIError.serverError(404))
    }
}
