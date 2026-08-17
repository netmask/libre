//
//  GlucoseStyling.swift
//  libre
//
//  Shared SwiftUI colors for glucose status and trend, so the popover,
//  chart, and menu bar label stay visually consistent.
//

import SwiftUI

extension GlucoseStatus {
    /// Standard tint for a glucose status (normal reads green).
    var tint: Color {
        switch self {
        case .low:    .red
        case .high:   .orange
        case .normal: .green
        }
    }
}

extension TrendArrow {
    /// Color communicating how urgent the current rate of change is.
    var velocityColor: Color {
        switch self {
        case .flat:                        .green
        case .fortyFiveUp, .fortyFiveDown: .yellow
        case .singleUp, .singleDown:       .red
        case .notComputable:               .secondary
        }
    }
}
