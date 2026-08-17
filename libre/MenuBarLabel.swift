//
//  MenuBarLabel.swift
//  libre
//
//  The status item content. macOS renders menu bar labels as template images,
//  which strips color — so the colored reading is pre-rendered to an NSImage
//  with ImageRenderer and cached, re-rendering only when its inputs change.
//

import SwiftUI

struct MenuBarLabel: View {
    let reading: GlucoseReading?
    let history: [GlucoseDataPoint]
    let status: ConnectionStatus
    var unit: GlucoseUnit = .mgdL
    var isStale: Bool = false

    @AppStorage("showUnitInMenuBar") private var showUnitInMenuBar = false
    @AppStorage("showSparkline") private var showSparkline = true
    @Environment(\.colorScheme) private var colorScheme

    @State private var rendered: NSImage?

    /// Everything the rendered image depends on, so the cache invalidates
    /// exactly when the picture would change (including light/dark flips,
    /// which arrive via the environment's color scheme).
    private struct RenderInputs: Equatable {
        let reading: GlucoseReading?
        let history: [GlucoseDataPoint]
        let unit: GlucoseUnit
        let isStale: Bool
        let showUnit: Bool
        let showSparkline: Bool
        let colorScheme: ColorScheme
    }

    private var renderInputs: RenderInputs {
        RenderInputs(
            reading: reading,
            history: history,
            unit: unit,
            isStale: isStale,
            showUnit: showUnitInMenuBar,
            showSparkline: showSparkline,
            colorScheme: colorScheme
        )
    }

    var body: some View {
        Group {
            if let reading {
                if let rendered {
                    Image(nsImage: rendered)
                } else {
                    // One-frame fallback before the first render lands.
                    Text(unit.format(reading.value))
                }
            } else {
                fallbackView
            }
        }
        .accessibilityLabel(accessibilityDescription)
        .onChange(of: renderInputs, initial: true) {
            if let reading {
                rendered = renderedImage(for: reading)
            } else {
                rendered = nil
            }
        }
    }

    private var accessibilityDescription: String {
        if let reading {
            var parts = ["Glucose \(unit.format(reading.value)) \(unit.label)", reading.trend.description]
            if isStale { parts.append("reading may be outdated") }
            return parts.joined(separator: ", ")
        }
        return switch status {
        case .connecting: "Glucose: connecting"
        case .error:      "Glucose: error"
        default:          "Glucose: disconnected"
        }
    }

    @ViewBuilder
    private var fallbackView: some View {
        switch status {
        case .connecting:
            Image(systemName: "arrow.triangle.2.circlepath")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
        default:
            Image(systemName: "drop.fill")
        }
    }

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
                .foregroundStyle(reading.trend.velocityColor)
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

    /// In the menu bar an in-range reading uses the label color, not green,
    /// so a healthy value doesn't shout for attention.
    private func numberColor(for status: GlucoseStatus) -> Color {
        switch status {
        case .low:    .red
        case .high:   .orange
        case .normal: .primary
        }
    }
}

// MARK: - Previews

#Preview("Connected") {
    let reading = GlucoseReading(
        value: 115,
        trend: .flat,
        timestamp: Date.now,
        isHigh: false,
        isLow: false
    )
    let history: [GlucoseDataPoint] = (0..<12).map { i in
        GlucoseDataPoint(
            value: Int.random(in: 95...140),
            timestamp: Date.now.addingTimeInterval(Double(-i) * 300)
        )
    }
    return MenuBarLabel(reading: reading, history: history, status: .connected)
}

#Preview("High") {
    let reading = GlucoseReading(
        value: 215,
        trend: .singleUp,
        timestamp: Date.now,
        isHigh: true,
        isLow: false
    )
    let history: [GlucoseDataPoint] = (0..<12).map { i in
        GlucoseDataPoint(
            value: 150 + i * 6,
            timestamp: Date.now.addingTimeInterval(Double(-12 + i) * 300)
        )
    }
    return MenuBarLabel(reading: reading, history: history, status: .connected)
}

#Preview("Disconnected") {
    MenuBarLabel(reading: nil, history: [], status: .disconnected)
}
