//
//  GlucoseAlertType.swift
//  libre
//
//  The kinds of glucose alerts the app can raise, with their
//  notification titles and sounds.
//

import UserNotifications

nonisolated enum GlucoseAlertType: String {
    case low = "low"
    case high = "high"
    case urgentLow = "urgent_low"
    case urgentHigh = "urgent_high"
    case fallingFast = "falling_fast"
    case risingFast = "rising_fast"

    var title: String {
        switch self {
        case .low: "Low Glucose"
        case .high: "High Glucose"
        case .urgentLow: "Urgent Low Glucose"
        case .urgentHigh: "Urgent High Glucose"
        case .fallingFast: "Glucose Falling Fast"
        case .risingFast: "Glucose Rising Fast"
        }
    }

    var sound: UNNotificationSound {
        switch self {
        case .urgentLow, .urgentHigh:
            .defaultCritical
        default:
            .default
        }
    }
}
