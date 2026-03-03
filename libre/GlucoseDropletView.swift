//
//  GlucoseDropletView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI

// MARK: - Glucose Droplet View (Metaball Lava Lamp)

struct GlucoseDropletView: View {
    let value: Int
    let trend: TrendArrow
    let unit: GlucoseUnit
    let status: GlucoseStatus

    @State private var isVisible = false

    private var blobColor: Color {
        switch status {
        case .low:
            return Color(red: 0.9, green: 0.2, blue: 0.2) // Red
        case .normal:
            return Color(red: 0.2, green: 0.8, blue: 0.4) // Green
        case .high:
            return Color(red: 1.0, green: 0.6, blue: 0.1) // Orange
        }
    }

    private var glowColor: Color {
        switch status {
        case .low:
            return Color(red: 1.0, green: 0.3, blue: 0.3)
        case .normal:
            return Color(red: 0.3, green: 1.0, blue: 0.5)
        case .high:
            return Color(red: 1.0, green: 0.7, blue: 0.2)
        }
    }

    var body: some View {
        ZStack {
            // Metaball water droplets animation (no clipping)
            MetaballCanvas(blobColor: blobColor, trend: trend, isAnimating: isVisible)
                .frame(width: 180, height: 180)

            // Value display overlay
            VStack(spacing: 2) {
                Text(unit.format(value))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)

                Text(unit.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

                HStack(spacing: 4) {
                    Image(systemName: trend.sfSymbol)
                        .font(.system(size: 14, weight: .semibold))
                    Text(trend.description)
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .padding(.top, 4)
            }
        }
        .frame(width: 180, height: 180)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

// MARK: - Metaball Canvas (Hydrophobic Water Effect)

struct MetaballCanvas: View {
    let blobColor: Color
    let trend: TrendArrow
    var isAnimating: Bool = true

    /// Returns vertical bias (-1 = down, 0 = stable, 1 = up) and horizontal drift
    private var trendBias: (vertical: Double, horizontal: Double) {
        switch trend {
        case .singleUp:
            return (vertical: -1.0, horizontal: 0.0)      // Strong upward
        case .fortyFiveUp:
            return (vertical: -0.6, horizontal: 0.3)      // Diagonal up-right
        case .flat:
            return (vertical: 0.0, horizontal: 0.2)       // Stable, slight horizontal
        case .fortyFiveDown:
            return (vertical: 0.6, horizontal: 0.3)       // Diagonal down-right
        case .singleDown:
            return (vertical: 1.0, horizontal: 0.0)       // Strong downward
        case .notComputable:
            return (vertical: 0.0, horizontal: 0.0)       // No bias
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/60, paused: !isAnimating)) { timeline in
            Canvas { ctx, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let bias = trendBias

                // Metaball effect: blur first, then threshold
                ctx.addFilter(.blur(radius: 12))
                ctx.addFilter(.alphaThreshold(min: 0.5, color: blobColor))

                ctx.drawLayer { ctx in
                    // Water droplets with surface tension movement
                    let droplets: [(baseX: Double, baseY: Double, xAmp: Double, yAmp: Double, xSpeed: Double, ySpeed: Double, radius: CGFloat, phase: Double)] = [
                        (0.5, 0.5, 0.06, 0.06, 0.5, 0.4, 32, 0),
                        (0.32, 0.38, 0.12, 0.1, 0.8, 0.7, 20, 1.0),
                        (0.68, 0.38, 0.1, 0.12, 0.7, 0.8, 18, 2.0),
                        (0.38, 0.65, 0.11, 0.09, 0.75, 0.65, 16, 3.0),
                        (0.62, 0.62, 0.09, 0.11, 0.65, 0.75, 17, 4.0),
                        (0.5, 0.3, 0.07, 0.1, 0.6, 0.55, 14, 5.0),
                        (0.5, 0.7, 0.08, 0.07, 0.55, 0.6, 15, 6.0),
                    ]

                    for droplet in droplets {
                        let wobbleX = sin(time * droplet.xSpeed + droplet.phase) * size.width * droplet.xAmp
                        let wobbleY = cos(time * droplet.ySpeed + droplet.phase * 0.7) * size.height * droplet.yAmp
                        let microWobble = sin(time * 2.0 + droplet.phase) * 2

                        // Apply trend bias - droplets drift in the direction of glucose trend
                        let trendWaveY = sin(time * 0.8 + droplet.phase * 0.5) * size.height * 0.08 * bias.vertical
                        let trendWaveX = sin(time * 0.6 + droplet.phase * 0.3) * size.width * 0.05 * bias.horizontal
                        let trendDriftY = bias.vertical * size.height * 0.06 // Constant offset in trend direction

                        let x = size.width * droplet.baseX + wobbleX + trendWaveX
                        let y = size.height * droplet.baseY + wobbleY + microWobble + trendWaveY + trendDriftY

                        let sizePulse = 1.0 + sin(time * 1.5 + droplet.phase) * 0.06
                        let radius = droplet.radius * sizePulse

                        let rect = CGRect(
                            x: x - radius,
                            y: y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )
                        ctx.fill(Circle().path(in: rect), with: .color(.white))
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Normal") {
    GlucoseDropletView(
        value: 105,
        trend: .flat,
        unit: .mgdL,
        status: .normal
    )
    .padding(40)
    .background(Color(.windowBackgroundColor))
}

#Preview("High") {
    GlucoseDropletView(
        value: 220,
        trend: .singleUp,
        unit: .mgdL,
        status: .high
    )
    .padding(40)
    .background(Color(.windowBackgroundColor))
}

#Preview("Low") {
    GlucoseDropletView(
        value: 55,
        trend: .singleDown,
        unit: .mmolL,
        status: .low
    )
    .padding(40)
    .background(Color(.windowBackgroundColor))
}

#Preview("Rising") {
    GlucoseDropletView(
        value: 145,
        trend: .fortyFiveUp,
        unit: .mgdL,
        status: .normal
    )
    .padding(40)
    .background(Color(.windowBackgroundColor))
}

#Preview("Falling") {
    GlucoseDropletView(
        value: 85,
        trend: .fortyFiveDown,
        unit: .mgdL,
        status: .normal
    )
    .padding(40)
    .background(Color(.windowBackgroundColor))
}
