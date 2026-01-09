//
//  Models.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Foundation

// MARK: - Glucose Reading

struct GlucoseReading: Codable, Equatable {
    let value: Int // mg/dL
    let trend: TrendArrow
    let timestamp: Date
    let isHigh: Bool
    let isLow: Bool

    var displayValue: String {
        "\(value)"
    }

    var statusColor: GlucoseStatus {
        if isLow { return .low }
        if isHigh { return .high }
        return .normal
    }
}

// MARK: - Historical Data Point

struct GlucoseDataPoint: Identifiable, Equatable {
    let id = UUID()
    let value: Int
    let timestamp: Date

    var isHigh: Bool { value > 180 }
    var isLow: Bool { value < 70 }

    var statusColor: GlucoseStatus {
        if isLow { return .low }
        if isHigh { return .high }
        return .normal
    }
}

enum GlucoseStatus {
    case low, normal, high
}

// MARK: - Trend Arrow

enum TrendArrow: Int, Codable, Equatable {
    case notComputable = 0
    case singleDown = 1
    case fortyFiveDown = 2
    case flat = 3
    case fortyFiveUp = 4
    case singleUp = 5

    var symbol: String {
        switch self {
        case .notComputable: return "?"
        case .singleDown: return "↓"
        case .fortyFiveDown: return "↘"
        case .flat: return "→"
        case .fortyFiveUp: return "↗"
        case .singleUp: return "↑"
        }
    }

    var sfSymbol: String {
        switch self {
        case .notComputable: return "questionmark"
        case .singleDown: return "arrow.down"
        case .fortyFiveDown: return "arrow.down.right"
        case .flat: return "arrow.right"
        case .fortyFiveUp: return "arrow.up.right"
        case .singleUp: return "arrow.up"
        }
    }

    var description: String {
        switch self {
        case .notComputable: return "Unknown"
        case .singleDown: return "Falling quickly"
        case .fortyFiveDown: return "Falling"
        case .flat: return "Stable"
        case .fortyFiveUp: return "Rising"
        case .singleUp: return "Rising quickly"
        }
    }
}

// MARK: - Connection Status

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)

    var description: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error(let message): return "Error: \(message)"
        }
    }
}

// MARK: - API Response Models

struct LoginResponse: Codable {
    let status: Int
    let data: AuthData?

    struct AuthData: Codable {
        let authTicket: AuthTicket
        let user: User
    }

    struct AuthTicket: Codable {
        let token: String
        let expires: Int
        let duration: Int
    }

    struct User: Codable {
        let id: String
        let firstName: String
        let lastName: String
        let email: String
    }
}

struct ConnectionsResponse: Codable {
    let status: Int
    let data: [Connection]

    struct Connection: Codable {
        let patientId: String
        let firstName: String
        let lastName: String
    }
}

struct GlucoseResponse: Codable {
    let status: Int
    let data: GlucoseData?

    struct GlucoseData: Codable {
        let connection: ConnectionData
        let graphData: [GraphPoint]?
    }

    struct ConnectionData: Codable {
        let glucoseMeasurement: GlucoseMeasurement?
    }

    struct GlucoseMeasurement: Codable {
        let ValueInMgPerDl: Int
        let TrendArrow: Int
        let Timestamp: String
        let FactoryTimestamp: String?
        let isHigh: Bool?
        let isLow: Bool?

        enum CodingKeys: String, CodingKey {
            case ValueInMgPerDl
            case TrendArrow
            case Timestamp
            case FactoryTimestamp
            case isHigh
            case isLow
        }
    }

    struct GraphPoint: Codable {
        let ValueInMgPerDl: Int
        let Timestamp: String
        let FactoryTimestamp: String?

        enum CodingKeys: String, CodingKey {
            case ValueInMgPerDl
            case Timestamp
            case FactoryTimestamp
        }
    }
}

// MARK: - API Errors

enum LibreAPIError: Error, Equatable {
    case invalidCredentials
    case networkError(String)
    case serverError(Int)
    case decodingError
    case noData
    case notAuthenticated
    case rateLimited
    case regionRedirect(String)
    case termsNotAccepted

    var localizedDescription: String {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError(let message):
            return "Network error: \(message)"
        case .serverError(let code):
            return "Server error: \(code)"
        case .decodingError:
            return "Failed to parse response"
        case .noData:
            return "No glucose data available"
        case .notAuthenticated:
            return "Please log in"
        case .rateLimited:
            return "Too many requests, please wait"
        case .regionRedirect(let region):
            return "Redirecting to region: \(region)"
        case .termsNotAccepted:
            return "Please accept terms in the LibreLinkUp app first"
        }
    }
}

// MARK: - User Credentials

struct UserCredentials: Codable, Equatable {
    let email: String
    let password: String
}

// MARK: - Region

enum LibreRegion: String, CaseIterable, Identifiable {
    case eu = "eu"
    case us = "us"
    case eu2 = "eu2"
    case ae = "ae"
    case ap = "ap"
    case au = "au"
    case ca = "ca"
    case de = "de"
    case fr = "fr"
    case jp = "jp"
    case la = "la"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eu: return "Europe"
        case .us: return "United States"
        case .eu2: return "Europe 2"
        case .ae: return "United Arab Emirates"
        case .ap: return "Asia Pacific"
        case .au: return "Australia"
        case .ca: return "Canada"
        case .de: return "Germany"
        case .fr: return "France"
        case .jp: return "Japan"
        case .la: return "Latin America"
        }
    }

    var flag: String {
        switch self {
        case .eu: return "🇪🇺"
        case .us: return "🇺🇸"
        case .eu2: return "🇪🇺"
        case .ae: return "🇦🇪"
        case .ap: return "🌏"
        case .au: return "🇦🇺"
        case .ca: return "🇨🇦"
        case .de: return "🇩🇪"
        case .fr: return "🇫🇷"
        case .jp: return "🇯🇵"
        case .la: return "🌎"
        }
    }
}
