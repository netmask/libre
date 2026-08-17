//
//  Sparkline.swift
//  libre
//
//  Miniature trend line rendered inside the menu bar label.
//

import SwiftUI

struct Sparkline: View {
    let points: [GlucoseDataPoint]
    var color: Color = .primary
    var lookback: TimeInterval = 3 * 3600 // 3 hours, matches the popover's shortest range

    private var trimmed: [GlucoseDataPoint] {
        let cutoff = Date.now.addingTimeInterval(-lookback)
        let recent = points.filter { $0.timestamp >= cutoff }
        if recent.count >= 2 { return recent }
        return Array(points.suffix(30))
    }

    private var normalized: [CGPoint] {
        let pts = trimmed
        guard pts.count >= 2, let first = pts.first, let last = pts.last else { return [] }
        let values = pts.map { Double($0.value) }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(maxV - minV, 1.0)
        let minT = first.timestamp.timeIntervalSinceReferenceDate
        let maxT = last.timestamp.timeIntervalSinceReferenceDate
        let timeSpan = max(maxT - minT, 1.0)
        return pts.map { p in
            CGPoint(
                x: (p.timestamp.timeIntervalSinceReferenceDate - minT) / timeSpan,
                y: 1 - (Double(p.value) - minV) / span
            )
        }
    }

    var body: some View {
        // Canvas draws the area fill, line, and end dot in a single layer,
        // avoiding a GeometryReader + ZStack of separate shapes.
        let pts = normalized
        Canvas { context, size in
            guard pts.count >= 2, let first = pts.first, let last = pts.last else { return }

            func scaled(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * size.width, y: p.y * size.height)
            }

            var line = Path()
            line.move(to: scaled(first))
            for p in pts.dropFirst() {
                line.addLine(to: scaled(p))
            }

            var area = line
            area.addLine(to: CGPoint(x: last.x * size.width, y: size.height))
            area.addLine(to: CGPoint(x: first.x * size.width, y: size.height))
            area.closeSubpath()

            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.50), color.opacity(0.05)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )
            context.stroke(
                line,
                with: .color(color),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
            )

            let dot = scaled(last)
            context.fill(
                Path(ellipseIn: CGRect(x: dot.x - 1.75, y: dot.y - 1.75, width: 3.5, height: 3.5)),
                with: .color(color)
            )
        }
    }
}
