//
//  NotificationService.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Foundation
import UserNotifications
import SwiftUI

// MARK: - Glucose Alert Type

enum GlucoseAlertType: String {
    case low = "low"
    case high = "high"
    case urgentLow = "urgent_low"
    case urgentHigh = "urgent_high"
    case fallingFast = "falling_fast"
    case risingFast = "rising_fast"

    var title: String {
        switch self {
        case .low: return "Low Glucose"
        case .high: return "High Glucose"
        case .urgentLow: return "Urgent Low Glucose"
        case .urgentHigh: return "Urgent High Glucose"
        case .fallingFast: return "Glucose Falling Fast"
        case .risingFast: return "Glucose Rising Fast"
        }
    }

    var sound: UNNotificationSound {
        switch self {
        case .urgentLow, .urgentHigh:
            return .defaultCritical
        default:
            return .default
        }
    }
}

// MARK: - Notification Service

@MainActor
@Observable
final class NotificationService {
    static let shared = NotificationService()

    var isAuthorized = false
    var notificationsEnabled = true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }
    var lowThreshold = 70 {
        didSet { UserDefaults.standard.set(lowThreshold, forKey: "lowThreshold") }
    }
    var highThreshold = 180 {
        didSet { UserDefaults.standard.set(highThreshold, forKey: "highThreshold") }
    }
    var urgentLowThreshold = 55 {
        didSet { UserDefaults.standard.set(urgentLowThreshold, forKey: "urgentLowThreshold") }
    }
    var urgentHighThreshold = 250 {
        didSet { UserDefaults.standard.set(urgentHighThreshold, forKey: "urgentHighThreshold") }
    }

    // Cooldown tracking to avoid notification spam
    private var lastAlertTimes: [GlucoseAlertType: Date] = [:]
    private let alertCooldown: TimeInterval = 15 * 60 // 15 minutes

    private init() {
        loadSettings()
        checkAuthorization()
    }

    private func loadSettings() {
        if UserDefaults.standard.object(forKey: "notificationsEnabled") != nil {
            notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
        }
        if UserDefaults.standard.object(forKey: "lowThreshold") != nil {
            lowThreshold = UserDefaults.standard.integer(forKey: "lowThreshold")
        }
        if UserDefaults.standard.object(forKey: "highThreshold") != nil {
            highThreshold = UserDefaults.standard.integer(forKey: "highThreshold")
        }
        if UserDefaults.standard.object(forKey: "urgentLowThreshold") != nil {
            urgentLowThreshold = UserDefaults.standard.integer(forKey: "urgentLowThreshold")
        }
        if UserDefaults.standard.object(forKey: "urgentHighThreshold") != nil {
            urgentHighThreshold = UserDefaults.standard.integer(forKey: "urgentHighThreshold")
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func checkAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            Task { @MainActor in
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }

    // MARK: - Alert Checking

    func checkAndNotify(reading: GlucoseReading, unit: GlucoseUnit) {
        guard notificationsEnabled && isAuthorized else { return }

        let value = reading.value

        // Check urgent thresholds first (most important)
        if value <= urgentLowThreshold {
            sendAlert(.urgentLow, value: value, unit: unit)
        } else if value >= urgentHighThreshold {
            sendAlert(.urgentHigh, value: value, unit: unit)
        }
        // Check regular thresholds
        else if value <= lowThreshold {
            sendAlert(.low, value: value, unit: unit)
        } else if value >= highThreshold {
            sendAlert(.high, value: value, unit: unit)
        }

        // Check trend-based alerts
        switch reading.trend {
        case .singleDown:
            sendAlert(.fallingFast, value: value, unit: unit)
        case .singleUp:
            sendAlert(.risingFast, value: value, unit: unit)
        default:
            break
        }
    }

    // MARK: - Send Notification

    private func sendAlert(_ type: GlucoseAlertType, value: Int, unit: GlucoseUnit) {
        // Check cooldown
        if let lastTime = lastAlertTimes[type],
           Date().timeIntervalSince(lastTime) < alertCooldown {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = type.title
        content.body = buildAlertMessage(type: type, value: value, unit: unit)
        content.sound = type.sound
        content.categoryIdentifier = "GLUCOSE_ALERT"

        // Add the glucose value as user info for potential actions
        content.userInfo = [
            "alertType": type.rawValue,
            "glucoseValue": value
        ]

        let request = UNNotificationRequest(
            identifier: "glucose_\(type.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error == nil {
                Task { @MainActor in
                    self?.lastAlertTimes[type] = Date()
                }
            }
        }
    }

    private func buildAlertMessage(type: GlucoseAlertType, value: Int, unit: GlucoseUnit) -> String {
        let formattedValue = "\(unit.format(value)) \(unit.label)"

        switch type {
        case .urgentLow:
            return "Your glucose is critically low at \(formattedValue). Take fast-acting carbs immediately."
        case .low:
            return "Your glucose is low at \(formattedValue). Consider having a snack."
        case .urgentHigh:
            return "Your glucose is very high at \(formattedValue). Check ketones if needed."
        case .high:
            return "Your glucose is high at \(formattedValue)."
        case .fallingFast:
            return "Your glucose is \(formattedValue) and falling quickly."
        case .risingFast:
            return "Your glucose is \(formattedValue) and rising quickly."
        }
    }

    // MARK: - Clear Notifications

    func clearAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    // Reset cooldowns (useful for testing)
    func resetCooldowns() {
        lastAlertTimes.removeAll()
    }
}
