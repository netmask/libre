//
//  MenuBarView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI

struct MenuBarView: View {
    @Environment(GlucoseService.self) private var glucoseService
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with current reading
            if let reading = glucoseService.currentReading {
                GlucoseReadingView(reading: reading)

                Divider()

                // 24-hour chart
                GlucoseChartView(
                    data: glucoseService.historyData,
                    currentReading: reading
                )

            } else if case .connecting = glucoseService.connectionStatus {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Connecting...")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if case .error(let message) = glucoseService.connectionStatus {
                VStack(alignment: .leading) {
                    Label("Error", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "drop.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Not connected")
                        .foregroundStyle(.secondary)
                    Button("Log In") {
                        openSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }

            Divider()

            // Status info
            HStack {
                if let name = glucoseService.patientName {
                    Label(name, systemImage: "person.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let lastUpdated = glucoseService.lastUpdated {
                    Label(timeAgo(from: lastUpdated), systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Actions
            HStack {
                Button {
                    Task {
                        await glucoseService.refresh()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                Spacer()

                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding()
        .frame(width: 360)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else {
            return date.formatted(date: .omitted, time: .shortened)
        }
    }
}

// MARK: - Glucose Reading View

struct GlucoseReadingView: View {
    let reading: GlucoseReading

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.displayValue)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(statusColor)

                Text("mg/dL")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(reading.trend.symbol)
                    .font(.title)
                    .foregroundStyle(statusColor)
            }

            Text(reading.trend.description)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(reading.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var statusColor: Color {
        switch reading.statusColor {
        case .low: return .red
        case .high: return .orange
        case .normal: return .green
        }
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    let reading: GlucoseReading?
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 2) {
            if let reading = reading {
                Text(reading.displayValue)
                    .font(.system(.body, design: .rounded).monospacedDigit())
                Image(systemName: reading.trend.sfSymbol)
                    .font(.caption)
            } else {
                switch status {
                case .connecting:
                    Image(systemName: "arrow.triangle.2.circlepath")
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                default:
                    Image(systemName: "drop.fill")
                }
            }
        }
    }
}

#Preview("Menu Bar View") {
    MenuBarView()
        .environment(GlucoseService())
}

#Preview("Menu Bar Label - Connected") {
    let reading = GlucoseReading(
        value: 115,
        trend: .flat,
        timestamp: Date(),
        isHigh: false,
        isLow: false
    )
    return MenuBarLabel(reading: reading, status: .connected)
}

#Preview("Menu Bar Label - Disconnected") {
    MenuBarLabel(reading: nil, status: .disconnected)
}
