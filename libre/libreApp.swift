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
    @Environment(\.openWindow) private var openWindow
    let modelContainer: ModelContainer
    @State private var glucoseService: GlucoseService
    @State private var hasStarted = false
    @AppStorage("hasAcceptedDisclaimer") private var hasAcceptedDisclaimer = false

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
            if hasAcceptedDisclaimer {
                MenuBarView()
                    .environment(glucoseService)
                    .modelContainer(modelContainer)
            } else {
                VStack(spacing: 12) {
                    Text("Please accept the disclaimer to continue")
                        .font(.headline)
                    Button("Show Disclaimer") {
                        openWindow(id: "disclaimer")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(width: 300)
                .onAppear {
                    openWindow(id: "disclaimer")
                }
            }
        } label: {
            MenuBarLabel(
                reading: hasAcceptedDisclaimer ? glucoseService.currentReading : nil,
                history: hasAcceptedDisclaimer ? glucoseService.historyData : [],
                status: hasAcceptedDisclaimer ? glucoseService.connectionStatus : .disconnected,
                unit: glucoseService.glucoseUnit,
                isStale: glucoseService.isDataStale
            )
            .task {
                guard !hasStarted, hasAcceptedDisclaimer else { return }
                hasStarted = true
                await bootstrap()
            }
            .onChange(of: hasAcceptedDisclaimer) { _, accepted in
                guard accepted else { return }
                Task { await bootstrap() }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Disclaimer", id: "disclaimer") {
            DisclaimerView(hasAcceptedDisclaimer: $hasAcceptedDisclaimer)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Settings {
            SettingsView()
                .environment(glucoseService)
                .modelContainer(modelContainer)
        }
    }

    private func bootstrap() async {
        await NotificationService.shared.requestAuthorization()
        if await glucoseService.tryAutoLogin() {
            glucoseService.startMonitoring()
        }
    }
}
