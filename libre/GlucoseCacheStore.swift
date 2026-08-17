//
//  GlucoseCacheStore.swift
//  libre
//
//  Shared SwiftData cache logic used by both the app (GlucoseService)
//  and the CLI's background refresh, so the write/dedupe/prune rules
//  live in exactly one place.
//

import Foundation
import SwiftData

nonisolated struct GlucoseCacheStore {
    static let retentionInterval: TimeInterval = 24 * 60 * 60

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// The most recent reading flagged as latest, if any.
    func latestReading() throws -> PersistedGlucoseReading? {
        let descriptor = FetchDescriptor<PersistedGlucoseReading>(
            predicate: #Predicate { $0.isLatest == true },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    /// History points within the retention window, oldest first.
    func recentHistory(now: Date = .now) throws -> [PersistedGlucoseDataPoint] {
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        let descriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
            predicate: #Predicate { $0.timestamp >= cutoff },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        return try context.fetch(descriptor)
    }

    /// Replaces the latest reading, merges new history points (deduplicated
    /// by timestamp), prunes anything past the retention window, and saves.
    func save(current: GlucoseReading, history: [GlucoseDataPoint], now: Date = .now) throws {
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)

        // Clear old "latest" flag
        let latestDescriptor = FetchDescriptor<PersistedGlucoseReading>(
            predicate: #Predicate { $0.isLatest == true }
        )
        for reading in try context.fetch(latestDescriptor) {
            reading.isLatest = false
        }

        context.insert(PersistedGlucoseReading(from: current, isLatest: true))

        // Prune readings and history points past retention
        let oldReadingsDescriptor = FetchDescriptor<PersistedGlucoseReading>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        for reading in try context.fetch(oldReadingsDescriptor) {
            context.delete(reading)
        }

        let oldPointsDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
            predicate: #Predicate { $0.timestamp < cutoff }
        )
        for point in try context.fetch(oldPointsDescriptor) {
            context.delete(point)
        }

        // Batch-check existing timestamps to avoid N+1 queries
        let existingDescriptor = FetchDescriptor<PersistedGlucoseDataPoint>(
            predicate: #Predicate { $0.timestamp >= cutoff }
        )
        let existingTimestamps = Set(try context.fetch(existingDescriptor).map(\.timestamp))

        for dataPoint in history where !existingTimestamps.contains(dataPoint.timestamp) {
            context.insert(PersistedGlucoseDataPoint(from: dataPoint))
        }

        try context.save()
    }
}
