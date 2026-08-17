//
//  StatRow.swift
//  libre
//
//  Compact statistics strip (TIR / GMI / Avg / Min / Max) under the chart.
//

import SwiftUI

struct StatRow: View {
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
        return (stats.timeInRange).formatted(.percent.precision(.fractionLength(0)))
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
        return (stats.gmi / 100).formatted(.percent.precision(.fractionLength(1)))
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
