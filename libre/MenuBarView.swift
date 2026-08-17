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
    @AppStorage("popoverRange") private var range: GlucoseTimeRange = .h6

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            Divider()
            footer
        }
        .padding(14)
        .frame(minWidth: 320, idealWidth: 360)
    }

    @ViewBuilder
    private var content: some View {
        if let reading = glucoseService.currentReading {
            GlucoseHeaderView(
                reading: reading,
                unit: glucoseService.glucoseUnit,
                isStale: glucoseService.isDataStale,
                lastUpdated: glucoseService.lastUpdated
            )

            RangeTabs(selection: $range)

            GlucoseChartView(
                data: glucoseService.historyData,
                currentReading: reading,
                unit: glucoseService.glucoseUnit,
                range: range
            )

            StatRow(
                stats: GlucoseStats(points: glucoseService.historyData, range: range),
                unit: glucoseService.glucoseUnit
            )
        } else if case .connecting = glucoseService.connectionStatus {
            placeholder {
                ProgressView().scaleEffect(0.7)
                Text("Connecting…").foregroundStyle(.secondary)
            }
        } else if case .error(let message) = glucoseService.connectionStatus {
            placeholder {
                Label("Error", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else {
            placeholder {
                Image(systemName: "drop.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Not connected").foregroundStyle(.secondary)
                Button("Log In") { openSettings() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func placeholder(@ViewBuilder _ inner: () -> some View) -> some View {
        VStack(spacing: 8) { inner() }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let name = glucoseService.patientName {
                Label(name, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Refresh", systemImage: "arrow.clockwise", action: refresh)
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh")

            Button("Settings", systemImage: "gear") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")

            Button("Quit", systemImage: "power", action: quit)
                .keyboardShortcut("q", modifiers: .command)
                .help("Quit")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .imageScale(.medium)
    }

    private func refresh() {
        Task { await glucoseService.refresh() }
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

#Preview {
    MenuBarView()
        .environment(GlucoseService())
}
