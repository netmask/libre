//
//  PreferencesSettingsView.swift
//  libre
//
//  Display and behavior preferences: unit, menu bar extras,
//  refresh cadence, launch at login.
//

import SwiftUI
import ServiceManagement

struct PreferencesSettingsView: View {
    @Environment(GlucoseService.self) private var glucoseService

    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    @AppStorage("showUnitInMenuBar") private var showUnitInMenuBar = false
    @AppStorage("showSparkline") private var showSparkline = true

    var body: some View {
        @Bindable var glucoseService = glucoseService

        Form {
            Picker("Glucose Unit", selection: $glucoseService.glucoseUnit) {
                ForEach(GlucoseUnit.allCases, id: \.self) { unit in
                    Text(unit.label).tag(unit)
                }
            }

            Toggle("Show unit in menu bar", isOn: $showUnitInMenuBar)

            Toggle("Show sparkline in menu bar", isOn: $showSparkline)

            Picker("Refresh Interval", selection: $glucoseService.refreshInterval) {
                Text("30 seconds").tag(30.0)
                Text("1 minute").tag(60.0)
                Text("2 minutes").tag(120.0)
                Text("5 minutes").tag(300.0)
            }
            .onChange(of: glucoseService.refreshInterval) {
                glucoseService.restartMonitoringIfActive()
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled)
                    }

                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = !enabled
            launchAtLoginError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }
}

#Preview {
    PreferencesSettingsView()
        .environment(GlucoseService())
}
