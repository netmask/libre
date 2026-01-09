//
//  GlucoseChartView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI
import Charts

struct GlucoseChartView: View {
    let data: [GlucoseDataPoint]
    let currentReading: GlucoseReading?

    private let lowThreshold = 70
    private let highThreshold = 180

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last 24 Hours")
                .font(.headline)
                .foregroundStyle(.secondary)

            if data.isEmpty {
                ContentUnavailableView {
                    Label("No Data", systemImage: "chart.line.downtrend.xyaxis")
                } description: {
                    Text("Glucose history will appear here")
                }
                .frame(height: 200)
            } else {
                Chart {
                    // Low threshold area
                    RectangleMark(
                        xStart: .value("Start", minTime),
                        xEnd: .value("End", maxTime),
                        yStart: .value("Low", 0),
                        yEnd: .value("LowEnd", lowThreshold)
                    )
                    .foregroundStyle(.red.opacity(0.1))

                    // High threshold area
                    RectangleMark(
                        xStart: .value("Start", minTime),
                        xEnd: .value("End", maxTime),
                        yStart: .value("High", highThreshold),
                        yEnd: .value("HighEnd", maxGlucose)
                    )
                    .foregroundStyle(.orange.opacity(0.1))

                    // Normal range area
                    RectangleMark(
                        xStart: .value("Start", minTime),
                        xEnd: .value("End", maxTime),
                        yStart: .value("NormalLow", lowThreshold),
                        yEnd: .value("NormalHigh", highThreshold)
                    )
                    .foregroundStyle(.green.opacity(0.1))

                    // Glucose line
                    ForEach(data) { point in
                        LineMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Glucose", point.value)
                        )
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }

                    // Data points
                    ForEach(data) { point in
                        PointMark(
                            x: .value("Time", point.timestamp),
                            y: .value("Glucose", point.value)
                        )
                        .foregroundStyle(colorForValue(point.value))
                        .symbolSize(20)
                    }

                    // Current reading marker
                    if let current = currentReading {
                        PointMark(
                            x: .value("Time", current.timestamp),
                            y: .value("Glucose", current.value)
                        )
                        .foregroundStyle(colorForStatus(current.statusColor))
                        .symbolSize(80)
                        .symbol(.circle)

                        RuleMark(y: .value("Current", current.value))
                            .foregroundStyle(.gray.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    }

                    // Threshold lines
                    RuleMark(y: .value("Low", lowThreshold))
                        .foregroundStyle(.red.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                    RuleMark(y: .value("High", highThreshold))
                        .foregroundStyle(.orange.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartYScale(domain: 40...max(maxGlucose, 220))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 4)) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [40, 70, 100, 140, 180, 220]) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel()
                    }
                }
                .frame(height: 200)
            }

            // Legend
            HStack(spacing: 16) {
                LegendItem(color: .green, label: "In Range")
                LegendItem(color: .orange, label: "High")
                LegendItem(color: .red, label: "Low")
            }
            .font(.caption2)
        }
    }

    private var minTime: Date {
        data.first?.timestamp ?? Date().addingTimeInterval(-86400)
    }

    private var maxTime: Date {
        data.last?.timestamp ?? Date()
    }

    private var maxGlucose: Int {
        max(data.map(\.value).max() ?? 180, currentReading?.value ?? 180, 200)
    }

    private func colorForValue(_ value: Int) -> Color {
        if value < lowThreshold { return .red }
        if value > highThreshold { return .orange }
        return .green
    }

    private func colorForStatus(_ status: GlucoseStatus) -> Color {
        switch status {
        case .low: return .red
        case .high: return .orange
        case .normal: return .green
        }
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    let sampleData: [GlucoseDataPoint] = (0..<24).map { hour in
        GlucoseDataPoint(
            value: Int.random(in: 80...160),
            timestamp: Date().addingTimeInterval(Double(-24 + hour) * 3600)
        )
    }

    let currentReading = GlucoseReading(
        value: 115,
        trend: .flat,
        timestamp: Date(),
        isHigh: false,
        isLow: false
    )

    return GlucoseChartView(data: sampleData, currentReading: currentReading)
        .padding()
        .frame(width: 350)
}
