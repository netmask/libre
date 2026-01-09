//
//  PersistentModels.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import Foundation
import SwiftData

// MARK: - Persistent Glucose Reading

@Model
final class PersistedGlucoseReading {
    var value: Int
    var trendRawValue: Int
    var timestamp: Date
    var isHigh: Bool
    var isLow: Bool
    var isLatest: Bool

    init(value: Int, trendRawValue: Int, timestamp: Date, isHigh: Bool, isLow: Bool, isLatest: Bool = false) {
        self.value = value
        self.trendRawValue = trendRawValue
        self.timestamp = timestamp
        self.isHigh = isHigh
        self.isLow = isLow
        self.isLatest = isLatest
    }

    convenience init(from reading: GlucoseReading, isLatest: Bool = false) {
        self.init(
            value: reading.value,
            trendRawValue: reading.trend.rawValue,
            timestamp: reading.timestamp,
            isHigh: reading.isHigh,
            isLow: reading.isLow,
            isLatest: isLatest
        )
    }

    func toGlucoseReading() -> GlucoseReading {
        GlucoseReading(
            value: value,
            trend: TrendArrow(rawValue: trendRawValue) ?? .notComputable,
            timestamp: timestamp,
            isHigh: isHigh,
            isLow: isLow
        )
    }
}

// MARK: - Persistent Glucose Data Point

@Model
final class PersistedGlucoseDataPoint {
    var value: Int
    var timestamp: Date

    init(value: Int, timestamp: Date) {
        self.value = value
        self.timestamp = timestamp
    }

    convenience init(from dataPoint: GlucoseDataPoint) {
        self.init(value: dataPoint.value, timestamp: dataPoint.timestamp)
    }

    func toGlucoseDataPoint() -> GlucoseDataPoint {
        GlucoseDataPoint(value: value, timestamp: timestamp)
    }
}
