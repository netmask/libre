//
//  MenuBarView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI
import Charts

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
            HeaderView(
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
            VStack(spacing: 12) {
                Image(systemName: "drop.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Not connected").foregroundStyle(.secondary)
                Button("Log In") { openSettings() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func placeholder<Content: View>(@ViewBuilder _ inner: () -> Content) -> some View {
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

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await glucoseService.refresh() }
            }
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh")

            Button("Settings", systemImage: "gear") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .help("Settings")

            Button("Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .help("Quit")
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .imageScale(.medium)
    }
}

// MARK: - Header

private struct HeaderView: View {
    let reading: GlucoseReading
    let unit: GlucoseUnit
    let isStale: Bool
    let lastUpdated: Date?

    private var color: Color { statusColor(reading.statusColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(unit.format(reading.value))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .foregroundStyle(color)
                    .opacity(isStale ? 0.55 : 1.0)

                Text(unit.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(reading.trend.description, systemImage: reading.trend.sfSymbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(trendVelocityColor(reading.trend))
                    .opacity(isStale ? 0.55 : 1.0)
            }

            Group {
                if isStale {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityHidden(true)
                        Text("Reading may be outdated")
                            .foregroundStyle(.secondary)
                    }
                } else if let lastUpdated {
                    Text("Updated \(lastUpdated, format: .relative(presentation: .named))")
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.caption)
        }
    }
}

// MARK: - Range tabs

private struct RangeTabs: View {
    @Binding var selection: GlucoseTimeRange

    var body: some View {
        Picker("Range", selection: $selection) {
            ForEach(GlucoseTimeRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

// MARK: - Stat row

private struct StatRow: View {
    let stats: GlucoseStats
    let unit: GlucoseUnit

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            StatCell(label: "TIR", value: tirString, accent: tirColor)
            divider
            StatCell(label: "GMI", value: gmiString)
            divider
            StatCell(label: "Avg", value: unit.format(stats.average))
            divider
            StatCell(label: "Min", value: unit.format(stats.minimum))
            divider
            StatCell(label: "Max", value: unit.format(stats.maximum))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1, height: 28)
            .opacity(0.4)
    }

    private var tirString: String {
        guard stats.count > 0 else { return "—" }
        return "\(Int((stats.timeInRange * 100).rounded()))%"
    }

    private var tirColor: Color? {
        guard stats.count > 0 else { return nil }
        switch stats.timeInRange {
        case 0.7...:    return .green
        case 0.5..<0.7: return .orange
        default:        return .red
        }
    }

    private var gmiString: String {
        guard stats.count > 0 else { return "—" }
        return String(format: "%.1f%%", stats.gmi)
    }
}

private struct StatCell: View {
    let label: String
    let value: String
    var accent: Color? = nil

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(accent ?? .primary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

private func statusColor(_ status: GlucoseStatus) -> Color {
    switch status {
    case .low:    .red
    case .high:   .orange
    case .normal: .green
    }
}

private func trendVelocityColor(_ trend: TrendArrow) -> Color {
    switch trend {
    case .flat:                          .green
    case .fortyFiveUp, .fortyFiveDown:   .yellow
    case .singleUp, .singleDown:         .red
    case .notComputable:                 .secondary
    }
}

// MARK: - Sparkline (used in menu bar label)

struct Sparkline: View {
    let points: [GlucoseDataPoint]
    var color: Color = .primary
    var lookback: TimeInterval = 3 * 3600 // 3 hours, matches the popover's shortest range

    private var trimmed: [GlucoseDataPoint] {
        let cutoff = Date().addingTimeInterval(-lookback)
        let recent = points.filter { $0.timestamp >= cutoff }
        if recent.count >= 2 { return recent }
        return Array(points.suffix(30))
    }

    private var normalized: [CGPoint] {
        let pts = trimmed
        guard pts.count >= 2 else { return [] }
        let values = pts.map { Double($0.value) }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 1.0)
        let minT = pts.first!.timestamp.timeIntervalSinceReferenceDate
        let maxT = pts.last!.timestamp.timeIntervalSinceReferenceDate
        let timeSpan = max(maxT - minT, 1.0)
        return pts.map { p in
            CGPoint(
                x: (p.timestamp.timeIntervalSinceReferenceDate - minT) / timeSpan,
                y: 1 - (Double(p.value) - minV) / span
            )
        }
    }

    var body: some View {
        let pts = normalized
        GeometryReader { geo in
            ZStack {
                if !pts.isEmpty {
                    SparklineAreaShape(values: pts)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.50), color.opacity(0.05)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    SparklineLineShape(values: pts)
                        .stroke(
                            color,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )

                    if let last = pts.last {
                        Circle()
                            .fill(color)
                            .frame(width: 3.5, height: 3.5)
                            .position(
                                x: last.x * geo.size.width,
                                y: last.y * geo.size.height
                            )
                    }
                }
            }
        }
    }
}

private struct SparklineLineShape: Shape {
    let values: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 2 else { return path }
        let first = CGPoint(x: values[0].x * rect.width, y: values[0].y * rect.height)
        path.move(to: first)
        for i in 1..<values.count {
            let pt = CGPoint(x: values[i].x * rect.width, y: values[i].y * rect.height)
            path.addLine(to: pt)
        }
        return path
    }
}

private struct SparklineAreaShape: Shape {
    let values: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 2 else { return path }
        let first = CGPoint(x: values[0].x * rect.width, y: values[0].y * rect.height)
        path.move(to: first)
        for i in 1..<values.count {
            let pt = CGPoint(x: values[i].x * rect.width, y: values[i].y * rect.height)
            path.addLine(to: pt)
        }
        let lastX = values.last!.x * rect.width
        let firstX = values.first!.x * rect.width
        path.addLine(to: CGPoint(x: lastX, y: rect.height))
        path.addLine(to: CGPoint(x: firstX, y: rect.height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Menu Bar Label

struct MenuBarLabel: View {
    let reading: GlucoseReading?
    let history: [GlucoseDataPoint]
    let status: ConnectionStatus
    var unit: GlucoseUnit = .mgdL
    var isStale: Bool = false

    @AppStorage("showUnitInMenuBar") private var showUnitInMenuBar = false
    @AppStorage("showSparkline") private var showSparkline = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Reading `colorScheme` here makes SwiftUI re-evaluate the body when the
        // system appearance flips dark <-> light, which re-renders the NSImage
        // with the correct text/icon colors.
        _ = colorScheme
        return Group {
            if let reading {
                renderedImage(for: reading).map { Image(nsImage: $0) }
            } else {
                fallbackView
            }
        }
    }

    @ViewBuilder
    private var fallbackView: some View {
        HStack(spacing: 4) {
            switch status {
            case .connecting:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .accessibilityLabel("Connecting")
            case .error:
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityLabel("Error")
            default:
                Image(systemName: "drop.fill")
                    .accessibilityLabel("Disconnected")
            }
        }
    }

    @MainActor
    private func renderedImage(for reading: GlucoseReading) -> NSImage? {
        let scheme = currentMenuBarColorScheme()
        let view = contentView(reading: reading)
            .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    private func currentMenuBarColorScheme() -> ColorScheme {
        // AppKit's effective appearance is the authoritative source for the menu bar.
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .dark : .light
    }

    private func contentView(reading: GlucoseReading) -> some View {
        HStack(spacing: 5) {
            Text(unit.format(reading.value))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(numberColor(for: reading.statusColor))
                .opacity(isStale ? 0.5 : 1.0)

            if showUnitInMenuBar {
                Text(unit.label)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .opacity(isStale ? 0.5 : 1.0)
            }

            Image(systemName: reading.trend.sfSymbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(trendVelocityColor(reading.trend))
                .opacity(isStale ? 0.5 : 1.0)

            if showSparkline {
                Sparkline(points: history, color: numberColor(for: reading.statusColor))
                    .frame(width: 40, height: 14)
                    .opacity(isStale ? 0.5 : 1.0)
            }
        }
        .frame(height: 18)
        .fixedSize()
    }

    private func numberColor(for status: GlucoseStatus) -> Color {
        switch status {
        case .low:    .red
        case .high:   .orange
        case .normal: .primary
        }
    }
}

// MARK: - Previews

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
    let history: [GlucoseDataPoint] = (0..<12).map { i in
        GlucoseDataPoint(
            value: Int.random(in: 95...140),
            timestamp: Date().addingTimeInterval(Double(-i) * 300)
        )
    }
    return MenuBarLabel(reading: reading, history: history, status: .connected)
}

#Preview("Menu Bar Label - High") {
    let reading = GlucoseReading(
        value: 215,
        trend: .singleUp,
        timestamp: Date(),
        isHigh: true,
        isLow: false
    )
    let history: [GlucoseDataPoint] = (0..<12).map { i in
        GlucoseDataPoint(
            value: 150 + i * 6,
            timestamp: Date().addingTimeInterval(Double(-12 + i) * 300)
        )
    }
    return MenuBarLabel(reading: reading, history: history, status: .connected)
}

#Preview("Menu Bar Label - Disconnected") {
    MenuBarLabel(reading: nil, history: [], status: .disconnected)
}
