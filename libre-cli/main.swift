//
//  main.swift
//  libre-cli
//
//  CLI tool for reading glucose data from the libre app's cache.
//  Designed for shell prompt integration (Starship/Spaceship).
//
//  Usage:
//    libre-cli           Print current reading (compact format)
//    libre-cli --json    Print current reading as JSON
//    libre-cli --refresh Fetch fresh data from API (used internally)
//    libre-cli --help    Show help
//

import Foundation
import SwiftData

// MARK: - Configuration

let stalenessThreshold: TimeInterval = 60  // Trigger background refresh if older than this

// MARK: - Argument Parsing

enum CLIMode {
    case printCached
    case json
    case backgroundRefresh
    case help
}

func parseArguments() -> CLIMode {
    let args = Set(CommandLine.arguments.dropFirst())
    if args.contains("--refresh") { return .backgroundRefresh }
    if args.contains("--json") { return .json }
    if args.contains("--help") || args.contains("-h") { return .help }
    return .printCached
}

// MARK: - Sandboxed App Container Access

/// The main app runs sandboxed, so its SwiftData store and UserDefaults
/// live inside ~/Library/Containers/<bundle-id>/Data/
let appBundleID = "garay.mx.libre"

func appContainerURL() -> URL? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let container = home
        .appendingPathComponent("Library/Containers")
        .appendingPathComponent(appBundleID)
        .appendingPathComponent("Data/Library/Application Support")
    // Verify the store actually exists
    if FileManager.default.fileExists(atPath: container.appendingPathComponent("default.store").path) {
        return container
    }
    return nil
}

func createModelContainer() throws -> ModelContainer {
    let schema = Schema([
        PersistedGlucoseReading.self,
        PersistedGlucoseDataPoint.self
    ])

    guard let storeDir = appContainerURL() else {
        fputs("error: could not find app's SwiftData store. Is the app installed and has been run at least once?\n", stderr)
        exit(1)
    }

    let storeURL = storeDir.appendingPathComponent("default.store")
    let config = ModelConfiguration(url: storeURL)

    return try ModelContainer(for: schema, configurations: [config])
}

func readAppUserDefaults() -> UserDefaults? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let plistPath = home
        .appendingPathComponent("Library/Containers")
        .appendingPathComponent(appBundleID)
        .appendingPathComponent("Data/Library/Preferences")
        .appendingPathComponent("\(appBundleID).plist")

    guard let dict = NSDictionary(contentsOf: plistPath) as? [String: Any] else {
        return nil
    }

    let defaults = UserDefaults(suiteName: "libre-cli-cache")
    dict.forEach { key, value in
        defaults?.set(value, forKey: key)
    }
    return defaults
}

func readLatestCached(from container: ModelContainer) throws -> PersistedGlucoseReading? {
    let context = ModelContext(container)
    let descriptor = FetchDescriptor<PersistedGlucoseReading>(
        predicate: #Predicate { $0.isLatest == true },
        sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
    )
    return try context.fetch(descriptor).first
}

// MARK: - Output Formatting

func formatReading(_ reading: PersistedGlucoseReading, unit: GlucoseUnit, asJSON: Bool) -> String {
    let trend = TrendArrow(rawValue: reading.trendRawValue) ?? .notComputable
    let ageSeconds = Int(-reading.timestamp.timeIntervalSinceNow)

    if asJSON {
        let json: [String: Any] = [
            "value": reading.value,
            "formatted_value": unit.format(reading.value),
            "unit": unit.rawValue,
            "trend": trend.symbol,
            "trend_description": trend.description,
            "timestamp": ISO8601DateFormatter().string(from: reading.timestamp),
            "is_high": reading.isHigh,
            "is_low": reading.isLow,
            "age_seconds": ageSeconds,
            "is_stale": ageSeconds > 300
        ]
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "{}"
    }

    // Compact format for shell prompts: "105 →"
    let formattedValue = unit.format(reading.value)

    // Add staleness indicator if data is older than 5 minutes
    if ageSeconds > 300 {
        let minutes = ageSeconds / 60
        return "\(formattedValue) \(trend.symbol) (\(minutes)m)"
    }

    return "\(formattedValue) \(trend.symbol)"
}

// MARK: - Background Refresh Trigger

func triggerBackgroundRefresh() {
    let executablePath = CommandLine.arguments[0]

    var pid: pid_t = 0
    let args = [executablePath, "--refresh"]
    let cArgs = args.map { strdup($0) } + [nil]
    defer { cArgs.forEach { free($0) } }

    var fileActions: posix_spawn_file_actions_t? = nil
    posix_spawn_file_actions_init(&fileActions)
    posix_spawn_file_actions_addopen(&fileActions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)
    defer { posix_spawn_file_actions_destroy(&fileActions) }

    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
    posix_spawnattr_setpgroup(&attr, 0)
    defer { posix_spawnattr_destroy(&attr) }

    _ = posix_spawn(
        &pid,
        executablePath,
        &fileActions,
        &attr,
        cArgs.map { UnsafeMutablePointer(mutating: $0) },
        environ
    )
}

// MARK: - Help

let helpText = """
libre - Glucose reading for shell prompts

USAGE:
    libre [OPTIONS]

OPTIONS:
    --json      Output as JSON
    --refresh   Fetch fresh data from API (used internally)
    -h, --help  Show this help message

OUTPUT FORMAT:
    Default:  105 →           (value + trend arrow)
    Stale:    105 → (3m)      (with age when >5min old)
    JSON:     {"value":105,"trend":"→",...}

INSTALL:
    Open libre.app > Settings > About > Install Command Line Tool
    This creates a symlink at /usr/local/bin/libre

STARSHIP INTEGRATION:
    Add to ~/.config/starship.toml:

    [custom.glucose]
    command = "libre"
    when = "test -x $(which libre)"
    format = "[$output]($style) "
    style = "bold green"
"""

// MARK: - Main

let mode = parseArguments()

switch mode {
case .help:
    print(helpText)
    exit(0)

case .backgroundRefresh:
    performBackgroundRefresh()
    exit(0)

case .printCached, .json:
    do {
        let container = try createModelContainer()
        guard let reading = try readLatestCached(from: container) else {
            print("--")
            exit(1)
        }

        // Read unit preference from the sandboxed app's UserDefaults
        let unit: GlucoseUnit
        let appDefaults = readAppUserDefaults()
        if let unitStr = appDefaults?.string(forKey: "glucoseUnit"),
           let parsed = GlucoseUnit(rawValue: unitStr) {
            unit = parsed
        } else {
            unit = .mgdL
        }

        print(formatReading(reading, unit: unit, asJSON: mode == .json))

        // Trigger background refresh if data is stale
        let ageSeconds = -reading.timestamp.timeIntervalSinceNow
        if ageSeconds > stalenessThreshold {
            triggerBackgroundRefresh()
        }

        exit(0)

    } catch {
        fputs("error: \(error)\n", stderr)
        print("--")
        exit(1)
    }
}
