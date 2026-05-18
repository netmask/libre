//
//  SettingsView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI
import ServiceManagement

struct SettingsView: View {
    enum SettingsTab: Hashable {
        case account, preferences, notifications, about
    }

    @Environment(GlucoseService.self) private var glucoseService
    @State private var notificationService = NotificationService.shared
    @State private var selection: SettingsTab = .account

    @State private var email = ""
    @State private var password = ""
    @State private var selectedRegion: LibreRegion = .us
    @State private var refreshInterval: Double = 60
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var launchAtLogin = false
    @State private var cliInstalled = false
    @State private var cliErrorMessage: String?

    @AppStorage("showUnitInMenuBar") private var showUnitInMenuBar = false
    @AppStorage("showSparkline") private var showSparkline = true

    private var thresholdUnitLabel: String {
        glucoseService.glucoseUnit.label
    }

    var body: some View {
        @Bindable var glucoseService = glucoseService
        @Bindable var notificationService = notificationService

        TabView(selection: $selection) {
            Tab("Account", systemImage: "person.circle", value: SettingsTab.account) {
                Form {
                    Section {
                        if glucoseService.connectionStatus == .connected {
                            LabeledContent {
                                Button("Log Out", role: .destructive) {
                                    glucoseService.logout()
                                }
                                .controlSize(.small)
                            } label: {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }

                            if let name = glucoseService.patientName {
                                LabeledContent("Monitoring", value: name)
                            }

                            LabeledContent(
                                "Region",
                                value: "\(glucoseService.selectedRegion.flag) \(glucoseService.selectedRegion.displayName)"
                            )
                        } else {
                            Picker("Region", selection: $selectedRegion) {
                                ForEach(LibreRegion.allCases) { region in
                                    Text("\(region.flag) \(region.displayName)")
                                        .tag(region)
                                }
                            }
                            .disabled(isLoggingIn)

                            TextField("Email", text: $email)
                                .textContentType(.emailAddress)
                                .disabled(isLoggingIn)

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .disabled(isLoggingIn)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }

                            Button(action: login) {
                                HStack {
                                    if isLoggingIn {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    }
                                    Text(isLoggingIn ? "Logging In…" : "Log In")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(email.isEmpty || password.isEmpty || isLoggingIn)
                        }
                    } header: {
                        Text("LibreLink Account")
                    } footer: {
                        if glucoseService.connectionStatus != .connected {
                            Text("Use the same credentials as the LibreLinkUp mobile app. Select your region based on where your LibreView account was created.")
                        }
                    }
                }
                .formStyle(.grouped)
            }

            Tab("Preferences", systemImage: "slider.horizontal.3", value: SettingsTab.preferences) {
                Form {
                    Picker("Glucose Unit", selection: $glucoseService.glucoseUnit) {
                        ForEach(GlucoseUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }

                    Toggle("Show unit in menu bar", isOn: $showUnitInMenuBar)

                    Toggle("Show sparkline in menu bar", isOn: $showSparkline)

                    Picker("Refresh Interval", selection: $refreshInterval) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .onChange(of: refreshInterval) { _, newValue in
                        glucoseService.updateRefreshInterval(newValue)
                    }

                    Toggle("Launch at Login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = !enabled
                            }
                        }
                }
                .formStyle(.grouped)
            }

            Tab("Notifications", systemImage: "bell.badge", value: SettingsTab.notifications) {
                Form {
                    Section {
                        Toggle("Enable Notifications", isOn: $notificationService.notificationsEnabled)

                        if !notificationService.isAuthorized {
                            HStack(spacing: 6) {
                                Label("Not authorized", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .font(.caption)
                                Spacer()
                                Button("Open Settings", action: openSystemNotificationSettings)
                                    .buttonStyle(.link)
                                    .controlSize(.small)
                            }
                        }
                    }

                    Section {
                        thresholdPair(
                            leftTitle: "Low",
                            left: $notificationService.lowThreshold,
                            rightTitle: "High",
                            right: $notificationService.highThreshold
                        )
                        thresholdPair(
                            leftTitle: "Urgent Low",
                            left: $notificationService.urgentLowThreshold,
                            rightTitle: "Urgent High",
                            right: $notificationService.urgentHighThreshold
                        )
                    } header: {
                        Text("Thresholds (mg/dL)")
                    } footer: {
                        Text("Urgent thresholds use critical alert sounds.")
                    }
                }
                .formStyle(.grouped)
            }

            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                Form {
                    Section {
                        LabeledContent("Version", value: "1.0.0 (1)")
                        Link("LibreView Website", destination: URL(string: "https://libreview.com")!)
                        Link("FreeStyle Libre", destination: URL(string: "https://www.freestylelibre.com")!)
                    }

                    Section {
                        LabeledContent {
                            Button(cliInstalled ? "Reinstall" : "Install", action: installCLI)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Command Line Tool")
                                Text(cliInstalled ? "Installed at /usr/local/bin/libre" : "Not installed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let cliErrorMessage {
                                    Text(cliErrorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    } footer: {
                        Text("Install `libre` for shell prompt integration (e.g., Starship).")
                    }

                    Section {
                        Text("Unofficial LibreLinkUp client. Not affiliated with Abbott Laboratories.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320, idealHeight: 360)
        .task {
            refreshInterval = glucoseService.refreshInterval
            selectedRegion = glucoseService.selectedRegion
            launchAtLogin = SMAppService.mainApp.status == .enabled
            cliInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/libre")
        }
    }

    @ViewBuilder
    private func thresholdPair(
        leftTitle: String,
        left: Binding<Int>,
        rightTitle: String,
        right: Binding<Int>
    ) -> some View {
        HStack(spacing: 16) {
            HStack {
                Text(leftTitle)
                Spacer(minLength: 6)
                TextField("\(leftTitle) threshold", value: left, format: .number)
                    .labelsHidden()
                    .frame(width: 56)
            }
            Divider()
            HStack {
                Text(rightTitle)
                Spacer(minLength: 6)
                TextField("\(rightTitle) threshold", value: right, format: .number)
                    .labelsHidden()
                    .frame(width: 56)
            }
        }
    }

    // MARK: - Actions

    private func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    private func installCLI() {
        cliErrorMessage = nil

        guard let cliURL = Bundle.main.url(forAuxiliaryExecutable: "libre-cli") else {
            cliErrorMessage = "Bundled libre-cli not found"
            return
        }

        let escapedPath = cliURL.path.replacing("'", with: "'\\''")
        let script = "do shell script \"ln -sf '\(escapedPath)' /usr/local/bin/libre\" with administrator privileges"

        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)

        if let error {
            cliErrorMessage = error[NSAppleScript.errorMessage] as? String ?? "Failed to install"
            return
        }

        cliInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/libre")
    }

    private func login() {
        isLoggingIn = true
        errorMessage = nil

        Task {
            do {
                try await glucoseService.login(email: email, password: password, region: selectedRegion)
                glucoseService.startMonitoring()
                email = ""
                password = ""
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoggingIn = false
        }
    }
}

#Preview {
    SettingsView()
        .environment(GlucoseService())
}
