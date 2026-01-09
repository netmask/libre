//
//  libreApp.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI
import SwiftData

@main
struct libreApp: App {
    let modelContainer: ModelContainer
    @State private var glucoseService: GlucoseService
    @State private var hasStarted = false

    init() {
        let schema = Schema([
            PersistedGlucoseReading.self,
            PersistedGlucoseDataPoint.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContainer = container
            let service = GlucoseService(modelContext: container.mainContext)
            // Load cached data immediately so menu bar shows reading on launch
            service.loadCachedData()
            self._glucoseService = State(initialValue: service)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(glucoseService)
                .modelContainer(modelContainer)
        } label: {
            MenuBarLabel(
                reading: glucoseService.currentReading,
                status: glucoseService.connectionStatus
            )
            .task {
                // Only run once on app launch
                guard !hasStarted else { return }
                hasStarted = true

                // Try auto-login and start monitoring
                let success = await glucoseService.tryAutoLogin()
                if success {
                    glucoseService.startMonitoring()
                }
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(glucoseService)
                .modelContainer(modelContainer)
        }
    }
}
