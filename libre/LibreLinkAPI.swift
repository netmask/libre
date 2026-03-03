//
//  LibreLinkAPI.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Foundation
import CryptoKit
import os.log

// MARK: - Debug Logger

private struct DebugLogger {
    private let logger = Logger(subsystem: "mx.garay.libre", category: "LibreLinkAPI")

    func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message)")
        #endif
    }

    func info(_ message: String) {
        #if DEBUG
        logger.info("\(message)")
        #endif
    }

    func warning(_ message: String) {
        #if DEBUG
        logger.warning("\(message)")
        #endif
    }

    func error(_ message: String) {
        #if DEBUG
        logger.error("\(message)")
        #endif
    }
}

private let logger = DebugLogger()

// MARK: - URL Session Protocol

protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - LibreLink API Client

actor LibreLinkAPI {
    private let session: URLSessionProtocol
    private var authToken: String?
    private var userId: String?
    private var tokenExpiry: Date?
    private var currentRegion: String = "US"
    private let deviceId: String

    private static let maxRedirects = 3

    // Only use verified working endpoints
    private let baseURLs: [String: String] = [
        "eu": "https://api-eu.libreview.io",
        "eu2": "https://api-eu2.libreview.io",
        "us": "https://api-us.libreview.io",
        "ca": "https://api-ca.libreview.io",
        "au": "https://api-au.libreview.io",
        "de": "https://api-de.libreview.io",
        "fr": "https://api-fr.libreview.io",
        "jp": "https://api-jp.libreview.io",
        "ap": "https://api-ap.libreview.io",
        "ae": "https://api-ae.libreview.io",
        "la": "https://api-la.libreview.io",
        "global": "https://api.libreview.io"
    ]

    private var baseURL: String {
        baseURLs[currentRegion.lowercased()] ?? baseURLs["us"]!
    }

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
        // Generate a persistent device ID
        self.deviceId = Self.generateDeviceId()
    }

    private static func generateDeviceId() -> String {
        // Try to load from UserDefaults, or generate new one
        let key = "libre_device_id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        let newId = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    // MARK: - Authentication

    func login(email: String, password: String) async throws -> LoginResponse {
        try await login(email: email, password: password, redirectCount: 0)
    }

    private func login(email: String, password: String, redirectCount: Int) async throws -> LoginResponse {
        guard redirectCount < Self.maxRedirects else {
            logger.error("🔴 Too many redirects (\(redirectCount))")
            throw LibreAPIError.networkError("Too many region redirects")
        }

        let url = URL(string: "\(baseURL)/llu/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request = addBaseHeaders(to: request)

        let body: [String: Any] = [
            "email": email,
            "password": password,
            "rememberMe": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Log request details
        logger.info("🔵 LOGIN REQUEST")
        logger.info("   URL: \(url.absoluteString)")
        logger.info("   Method: POST")
        logger.info("   Region: \(self.currentRegion)")
        logHeaders(request.allHTTPHeaderFields ?? [:], prefix: "   ")
        if let bodyData = request.httpBody, let bodyString = String(data: bodyData, encoding: .utf8) {
            // Mask password in logs
            let maskedBody = bodyString.replacingOccurrences(of: password, with: "****")
            logger.info("   Body: \(maskedBody)")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("🔴 Invalid response type")
            throw LibreAPIError.networkError("Invalid response")
        }

        // Log response details
        logger.info("🟢 LOGIN RESPONSE")
        logger.info("   Status: \(httpResponse.statusCode)")
        logHeaders(httpResponse.allHeaderFields as? [String: String] ?? [:], prefix: "   ")
        if let responseString = String(data: data, encoding: .utf8) {
            logger.info("   Body: \(responseString)")
        }

        // Handle region redirect (status 2 in response body)
        if httpResponse.statusCode == 200 {
            // First check for redirect
            if let redirectData = try? JSONDecoder().decode(RedirectResponse.self, from: data),
               redirectData.status == 2,
               let redirect = redirectData.data?.redirect,
               redirect == true,
               let region = redirectData.data?.region {
                logger.info("🔄 Redirect to region: \(region)")
                currentRegion = region.lowercased()
                // Retry with new region
                return try await login(email: email, password: password, redirectCount: redirectCount + 1)
            }

            let loginResponse = try JSONDecoder().decode(LoginResponse.self, from: data)

            if loginResponse.status == 4 {
                logger.warning("⚠️ Terms not accepted")
                throw LibreAPIError.termsNotAccepted
            }

            if let authData = loginResponse.data {
                self.authToken = authData.authTicket.token
                self.userId = authData.user.id
                self.tokenExpiry = Date().addingTimeInterval(TimeInterval(authData.authTicket.duration))
                logger.info("✅ Login successful, token received")
            }

            return loginResponse
        }

        if httpResponse.statusCode == 401 {
            logger.error("🔴 Invalid credentials (401)")
            throw LibreAPIError.invalidCredentials
        }

        if httpResponse.statusCode == 429 {
            logger.error("🔴 Rate limited (429)")
            throw LibreAPIError.rateLimited
        }

        if httpResponse.statusCode == 403 {
            logger.error("🔴 Forbidden (403) - Check headers and request format")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.error("   Response body: \(responseString)")
            }
            throw LibreAPIError.serverError(403)
        }

        logger.error("🔴 Server error: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            logger.error("   Response body: \(responseString)")
        }
        throw LibreAPIError.serverError(httpResponse.statusCode)
    }

    private func logHeaders(_ headers: [String: String], prefix: String) {
        for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
            if key.lowercased() == "authorization" {
                logger.info("\(prefix)\(key): Bearer ****")
            } else {
                logger.info("\(prefix)\(key): \(value)")
            }
        }
    }

    func logout() {
        authToken = nil
        userId = nil
        tokenExpiry = nil
    }

    var isAuthenticated: Bool {
        guard let token = authToken, let expiry = tokenExpiry else {
            return false
        }
        return !token.isEmpty && expiry > Date()
    }

    // MARK: - Connections

    func getConnections() async throws -> [ConnectionsResponse.Connection] {
        guard isAuthenticated else {
            logger.error("🔴 Not authenticated for getConnections")
            throw LibreAPIError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/llu/connections")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request = addAuthHeaders(to: request)

        // Log request
        logger.info("🔵 CONNECTIONS REQUEST")
        logger.info("   URL: \(url.absoluteString)")
        logger.info("   Method: GET")
        logHeaders(request.allHTTPHeaderFields ?? [:], prefix: "   ")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("🔴 Invalid response type")
            throw LibreAPIError.networkError("Invalid response")
        }

        // Log response
        logger.info("🟢 CONNECTIONS RESPONSE")
        logger.info("   Status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            logger.info("   Body: \(responseString)")
        }

        if httpResponse.statusCode == 401 {
            logger.error("🔴 Not authenticated (401)")
            throw LibreAPIError.notAuthenticated
        }

        if httpResponse.statusCode == 403 {
            logger.error("🔴 Forbidden (403)")
            throw LibreAPIError.serverError(403)
        }

        if httpResponse.statusCode != 200 {
            logger.error("🔴 Server error: \(httpResponse.statusCode)")
            throw LibreAPIError.serverError(httpResponse.statusCode)
        }

        let connectionsResponse = try JSONDecoder().decode(ConnectionsResponse.self, from: data)
        logger.info("✅ Got \(connectionsResponse.data.count) connections")
        return connectionsResponse.data
    }

    // MARK: - Glucose Data

    struct GlucoseResult {
        let current: GlucoseReading
        let history: [GlucoseDataPoint]
    }

    func getGlucoseData(patientId: String) async throws -> GlucoseReading {
        let result = try await getGlucoseDataWithHistory(patientId: patientId)
        return result.current
    }

    func getGlucoseDataWithHistory(patientId: String) async throws -> GlucoseResult {
        guard isAuthenticated else {
            logger.error("🔴 Not authenticated for getGlucoseData")
            throw LibreAPIError.notAuthenticated
        }

        let url = URL(string: "\(baseURL)/llu/connections/\(patientId)/graph")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request = addAuthHeaders(to: request)

        // Log request
        logger.info("🔵 GLUCOSE DATA REQUEST")
        logger.info("   URL: \(url.absoluteString)")
        logger.info("   Method: GET")
        logger.info("   PatientId: \(patientId)")
        logHeaders(request.allHTTPHeaderFields ?? [:], prefix: "   ")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("🔴 Invalid response type")
            throw LibreAPIError.networkError("Invalid response")
        }

        // Log response
        logger.info("🟢 GLUCOSE DATA RESPONSE")
        logger.info("   Status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            // Truncate if too long
            let truncated = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
            logger.info("   Body: \(truncated)")
        }

        if httpResponse.statusCode == 401 {
            logger.error("🔴 Not authenticated (401)")
            throw LibreAPIError.notAuthenticated
        }

        if httpResponse.statusCode == 429 {
            logger.error("🔴 Rate limited (429)")
            throw LibreAPIError.rateLimited
        }

        if httpResponse.statusCode == 403 {
            logger.error("🔴 Forbidden (403)")
            if let responseString = String(data: data, encoding: .utf8) {
                logger.error("   Response: \(responseString)")
            }
            throw LibreAPIError.serverError(403)
        }

        if httpResponse.statusCode != 200 {
            logger.error("🔴 Server error: \(httpResponse.statusCode)")
            throw LibreAPIError.serverError(httpResponse.statusCode)
        }

        let glucoseResponse = try JSONDecoder().decode(GlucoseResponse.self, from: data)

        guard let measurement = glucoseResponse.data?.connection.glucoseMeasurement else {
            throw LibreAPIError.noData
        }

        let timestamp = parseTimestamp(measurement.Timestamp) ?? Date()

        let currentReading = GlucoseReading(
            value: measurement.ValueInMgPerDl,
            trend: TrendArrow(rawValue: measurement.TrendArrow) ?? .notComputable,
            timestamp: timestamp,
            isHigh: measurement.isHigh ?? false,
            isLow: measurement.isLow ?? false
        )

        // Parse historical graph data
        var historyPoints: [GlucoseDataPoint] = []
        if let graphData = glucoseResponse.data?.graphData {
            for point in graphData {
                if let pointDate = parseTimestamp(point.Timestamp) {
                    historyPoints.append(GlucoseDataPoint(
                        value: point.ValueInMgPerDl,
                        timestamp: pointDate
                    ))
                }
            }
        }

        // Sort by timestamp (oldest first)
        historyPoints.sort { $0.timestamp < $1.timestamp }

        return GlucoseResult(current: currentReading, history: historyPoints)
    }

    // MARK: - Timestamp Parsing

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    private static let customFormatters: [DateFormatter] = {
        ["M/d/yyyy h:mm:ss a", "MM/dd/yyyy h:mm:ss a", "M/d/yyyy H:mm:ss"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    private func parseTimestamp(_ ts: String) -> Date? {
        if let date = Self.isoFormatter.date(from: ts) {
            return date
        }

        for formatter in Self.customFormatters {
            if let date = formatter.date(from: ts) {
                return date
            }
        }

        return nil
    }

    // MARK: - Headers

    private func addBaseHeaders(to request: URLRequest) -> URLRequest {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Keep-Alive", forHTTPHeaderField: "Connection")
        request.setValue("llu.android", forHTTPHeaderField: "product")
        request.setValue("4.16.0", forHTTPHeaderField: "version")
        request.setValue(deviceId, forHTTPHeaderField: "device")
        request.setValue(currentRegion.uppercased(), forHTTPHeaderField: "country")
        request.setValue("okhttp/4.9.3", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        return request
    }

    private func addAuthHeaders(to request: URLRequest) -> URLRequest {
        var request = addBaseHeaders(to: request)
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let userId = userId {
            let hashedId = sha256Hash(userId)
            request.setValue(hashedId, forHTTPHeaderField: "account-id")
        }
        return request
    }

    private func sha256Hash(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Token Management

    func setToken(_ token: String, expiry: Date) {
        self.authToken = token
        self.tokenExpiry = expiry
    }

    func setRegion(_ region: String) {
        let lowercased = region.lowercased()
        if baseURLs.keys.contains(lowercased) {
            currentRegion = lowercased
        }
    }
}

// MARK: - Redirect Response

private struct RedirectResponse: Codable {
    let status: Int
    let data: RedirectData?

    struct RedirectData: Codable {
        let redirect: Bool?
        let region: String?
    }
}
