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
    var unit: GlucoseUnit = .mgdL
    var range: GlucoseTimeRange = .h24

    @State private var hoverTime: Date?

    private let lowThresholdMgdL = GlucoseStats.lowThresholdMgdL
    private let highThresholdMgdL = GlucoseStats.highThresholdMgdL

    private var lowThreshold: Double { unit.convert(lowThresholdMgdL) }
    private var highThreshold: Double { unit.convert(highThresholdMgdL) }

    var body: some View {
        // Snapshot the clock and filter once per body evaluation, so every mark,
        // axis, and hover lookup below shares consistent data and time bounds.
        let now = Date.now
        let minTime = now.addingTimeInterval(-range.interval)
        let filtered = data.filter { $0.timestamp >= minTime }

        Group {
            if filtered.isEmpty {
                ContentUnavailableView {
                    Label("No Data", systemImage: "chart.line.downtrend.xyaxis")
                } description: {
                    Text("Glucose history will appear here")
                }
                .frame(height: 180)
            } else {
                chart(filtered: filtered, minTime: minTime, maxTime: now)
            }
        }
    }

    private func chart(filtered: [GlucoseDataPoint], minTime: Date, maxTime: Date) -> some View {
        let hovered = hoveredPoint(in: filtered)
        let lineColor = lineColor
        let maxY = maxYScale(filtered: filtered)

        return Chart {
            RectangleMark(
                xStart: .value("Start", minTime),
                xEnd: .value("End", maxTime),
                yStart: .value("NormalLow", lowThreshold),
                yEnd: .value("NormalHigh", highThreshold)
            )
            .foregroundStyle(.green.opacity(0.05))

            ForEach(filtered) { point in
                AreaMark(
                    x: .value("Time", point.timestamp),
                    yStart: .value("Floor", minYScale),
                    yEnd: .value("Glucose", unit.convert(point.value))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(areaGradient(for: lineColor))
            }

            ForEach(filtered) { point in
                LineMark(
                    x: .value("Time", point.timestamp),
                    y: .value("Glucose", unit.convert(point.value))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(lineColor.gradient)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            if let current = currentReading, current.timestamp >= minTime, hovered == nil {
                let currentValue = unit.convert(current.value)
                let dotColor = current.statusColor.tint

                PointMark(
                    x: .value("Time", current.timestamp),
                    y: .value("Glucose", currentValue)
                )
                .symbolSize(260)
                .foregroundStyle(dotColor.opacity(0.18))

                PointMark(
                    x: .value("Time", current.timestamp),
                    y: .value("Glucose", currentValue)
                )
                .symbolSize(70)
                .foregroundStyle(dotColor.gradient)
            }

            if let hovered {
                let hoveredValue = unit.convert(hovered.value)
                let hoveredColor = hovered.statusColor.tint

                RuleMark(x: .value("Hover", hovered.timestamp))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                PointMark(
                    x: .value("Time", hovered.timestamp),
                    y: .value("Glucose", hoveredValue)
                )
                .symbolSize(60)
                .foregroundStyle(hoveredColor.gradient)
                .annotation(
                    position: .top,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    HoverReadout(
                        value: unit.format(hovered.value),
                        unit: unit.label,
                        time: hovered.timestamp,
                        format: hoverTimeFormat,
                        accent: hoveredColor
                    )
                }
            }
        }
        .chartLegend(.hidden)
        .chartXSelection(value: $hoverTime)
        .chartYScale(domain: minYScale...maxY)
        .chartXAxis {
            AxisMarks(values: xAxisStride) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                AxisValueLabel(format: xAxisFormat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel()
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 180)
    }

    private func hoveredPoint(in filtered: [GlucoseDataPoint]) -> GlucoseDataPoint? {
        guard let hoverTime, !filtered.isEmpty else { return nil }
        return filtered.min(by: {
            abs($0.timestamp.timeIntervalSince(hoverTime)) < abs($1.timestamp.timeIntervalSince(hoverTime))
        })
    }

    private var hoverTimeFormat: Date.FormatStyle {
        switch range {
        case .h3, .h6, .h12: .dateTime.hour().minute()
        case .h24:           .dateTime.weekday(.abbreviated).hour().minute()
        }
    }

    private func maxYScale(filtered: [GlucoseDataPoint]) -> Double {
        let highestValue = max(
            filtered.map(\.value).max() ?? highThresholdMgdL,
            currentReading?.value ?? highThresholdMgdL,
            220
        )
        return unit.convert(highestValue)
    }

    private var minYScale: Double {
        unit.convert(40)
    }

    private var yAxisValues: [Double] {
        switch unit {
        case .mgdL:  [40, 70, 100, 140, 180, 220]
        case .mmolL: [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]
        }
    }

    private var xAxisStride: AxisMarkValues {
        switch range {
        case .h3:  .stride(by: .minute, count: 30)
        case .h6:  .stride(by: .hour, count: 1)
        case .h12: .stride(by: .hour, count: 2)
        case .h24: .stride(by: .hour, count: 4)
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .h3: .dateTime.hour().minute()
        default:  .dateTime.hour()
        }
    }

    private var lineColor: Color {
        if let current = currentReading {
            current.statusColor.tint
        } else {
            .blue
        }
    }

    private func areaGradient(for lineColor: Color) -> LinearGradient {
        LinearGradient(
            colors: [
                lineColor.opacity(0.32),
                lineColor.opacity(0.10),
                lineColor.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private struct HoverReadout: View {
    let value: String
    let unit: String
    let time: Date
    let format: Date.FormatStyle
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(accent.gradient)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.callout.weight(.semibold).monospacedDigit())
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(time, format: format)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: .rect(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(.separator.opacity(0.6), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .fixedSize()
    }
}

#Preview {
    let sampleData: [GlucoseDataPoint] = (0..<24).map { hour in
        GlucoseDataPoint(
            value: Int.random(in: 80...160),
            timestamp: Date.now.addingTimeInterval(Double(-24 + hour) * 3600)
        )
    }

    let currentReading = GlucoseReading(
        value: 115,
        trend: .flat,
        timestamp: Date.now,
        isHigh: false,
        isLow: false
    )

    return GlucoseChartView(data: sampleData, currentReading: currentReading, range: .h24)
        .padding()
        .frame(width: 350)
}
