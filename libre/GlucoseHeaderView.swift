//
//  GlucoseHeaderView.swift
//  libre
//
//  Large current-reading header shown at the top of the menu bar popover.
//

import SwiftUI

struct GlucoseHeaderView: View {
    let reading: GlucoseReading
    let unit: GlucoseUnit
    let isStale: Bool
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(unit.format(reading.value))
                    .font(.system(.largeTitle, design: .rounded).bold())
                    .foregroundStyle(reading.statusColor.tint)
                    .opacity(isStale ? 0.55 : 1.0)

                Text(unit.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Label(reading.trend.description, systemImage: reading.trend.sfSymbol)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(reading.trend.velocityColor)
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
