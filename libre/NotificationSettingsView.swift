//
//  NotificationSettingsView.swift
//  libre
//
//  Alert toggles and glucose thresholds. Thresholds are stored and edited
//  in mg/dL (the unit the API reports); when the display unit is mmol/L
//  the footer shows the equivalents so the numbers stay meaningful.
//

import SwiftUI

struct NotificationSettingsView: View {
    @Environment(GlucoseService.self) private var glucoseService
    @State private var notificationService = NotificationService.shared

    var body: some View {
        @Bindable var notificationService = notificationService

        Form {
            Section {
                Toggle("Enable Notifications", isOn: $notificationService.notificationsEnabled)

                if !notificationService.isAuthorized {
                    HStack(spacing: 6) {
                        Label("Not authorized", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                        Spacer()
                        Button("Open Settings", action: openSystemNotificationSettings)
                            .buttonStyle(.link)
                            .controlSize(.small)
                    }
                }
            }

            Section {
                ThresholdPair(
                    leftTitle: "Low",
                    left: $notificationService.lowThreshold,
                    rightTitle: "High",
                    right: $notificationService.highThreshold
                )
                ThresholdPair(
                    leftTitle: "Urgent Low",
                    left: $notificationService.urgentLowThreshold,
                    rightTitle: "Urgent High",
                    right: $notificationService.urgentHighThreshold
                )
            } header: {
                Text("Thresholds (mg/dL)")
            } footer: {
                VStack(alignment: .leading, spacing: 2) {
                    if glucoseService.glucoseUnit == .mmolL {
                        Text(mmolEquivalents)
                    }
                    Text("Urgent thresholds use critical alert sounds.")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var mmolEquivalents: String {
        let unit = GlucoseUnit.mmolL
        let parts: [String] = [
            "Low \(unit.format(notificationService.lowThreshold))",
            "High \(unit.format(notificationService.highThreshold))",
            "Urgent Low \(unit.format(notificationService.urgentLowThreshold))",
            "Urgent High \(unit.format(notificationService.urgentHighThreshold))"
        ]
        return "In mmol/L: \(parts.joined(separator: ", "))."
    }

    private func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ThresholdPair: View {
    let leftTitle: String
    @Binding var left: Int
    let rightTitle: String
    @Binding var right: Int

    var body: some View {
        HStack(spacing: 16) {
            HStack {
                Text(leftTitle)
                Spacer(minLength: 6)
                TextField("\(leftTitle) threshold", value: $left, format: .number)
                    .labelsHidden()
                    .frame(width: 56)
            }
            Divider()
            HStack {
                Text(rightTitle)
                Spacer(minLength: 6)
                TextField("\(rightTitle) threshold", value: $right, format: .number)
                    .labelsHidden()
                    .frame(width: 56)
            }
        }
    }
}

#Preview {
    NotificationSettingsView()
        .environment(GlucoseService())
}
