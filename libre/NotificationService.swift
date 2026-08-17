//
//  NotificationService.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Foundation
import UserNotifications
import SwiftUI

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
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            isAuthorized = settings.authorizationStatus == .authorized
        }
    }

    // MARK: - Alert Checking

    /// Threshold configuration for alert decisions, separated out so the
    /// decision logic is a pure function that unit tests can exercise.
    nonisolated struct Thresholds {
        var low: Int
        var high: Int
        var urgentLow: Int
        var urgentHigh: Int
    }

    /// Pure decision logic: which alerts does this reading trigger?
    /// Cooldowns and authorization are applied later, at send time.
    nonisolated static func triggeredAlerts(
        value: Int,
        trend: TrendArrow,
        thresholds: Thresholds
    ) -> [GlucoseAlertType] {
        var alerts: [GlucoseAlertType] = []

        // Urgent thresholds win over regular ones
        if value <= thresholds.urgentLow {
            alerts.append(.urgentLow)
        } else if value >= thresholds.urgentHigh {
            alerts.append(.urgentHigh)
        } else if value <= thresholds.low {
            alerts.append(.low)
        } else if value >= thresholds.high {
            alerts.append(.high)
        }

        switch trend {
        case .singleDown: alerts.append(.fallingFast)
        case .singleUp:   alerts.append(.risingFast)
        default:          break
        }

        return alerts
    }

    func checkAndNotify(reading: GlucoseReading, unit: GlucoseUnit) {
        guard notificationsEnabled && isAuthorized else { return }

        let thresholds = Thresholds(
            low: lowThreshold,
            high: highThreshold,
            urgentLow: urgentLowThreshold,
            urgentHigh: urgentHighThreshold
        )

        for alert in Self.triggeredAlerts(value: reading.value, trend: reading.trend, thresholds: thresholds) {
            sendAlert(alert, value: reading.value, unit: unit)
        }
    }

    // MARK: - Send Notification

    private func sendAlert(_ type: GlucoseAlertType, value: Int, unit: GlucoseUnit) {
        // Check cooldown
        if let lastTime = lastAlertTimes[type],
           Date.now.timeIntervalSince(lastTime) < alertCooldown {
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
            identifier: "glucose_\(type.rawValue)_\(Date.now.timeIntervalSince1970)",
            content: content,
            trigger: nil // Deliver immediately
        )

        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
                lastAlertTimes[type] = Date.now
            } catch {
                // Delivery failed; leave the cooldown untouched so the next
                // reading can retry.
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
}
