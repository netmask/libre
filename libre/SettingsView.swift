//
//  SettingsView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI

struct SettingsView: View {
    @Environment(GlucoseService.self) private var glucoseService
    private var notificationService = NotificationService.shared

    @State private var email = ""
    @State private var password = ""
    @State private var selectedRegion: LibreRegion = .us
    @State private var refreshInterval: Double = 60
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        TabView {
            // Account Tab
            Form {
                Section {
                    if glucoseService.connectionStatus == .connected {
                        // Logged in state
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Connected", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)

                            if let name = glucoseService.patientName {
                                Text("Monitoring: \(name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Text("Region: \(glucoseService.selectedRegion.flag) \(glucoseService.selectedRegion.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button("Log Out", role: .destructive) {
                            glucoseService.logout()
                        }
                    } else {
                        // Region picker
                        Picker("Region", selection: $selectedRegion) {
                            ForEach(LibreRegion.allCases) { region in
                                Text("\(region.flag) \(region.displayName)")
                                    .tag(region)
                            }
                        }
                        .disabled(isLoggingIn)

                        // Login form
                        TextField("Email", text: $email)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.emailAddress)
                            .disabled(isLoggingIn)

                        SecureField("Password", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.password)
                            .disabled(isLoggingIn)

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        Button {
                            login()
                        } label: {
                            HStack {
                                if isLoggingIn {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                Text(isLoggingIn ? "Logging In..." : "Log In")
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
            .tabItem {
                Label("Account", systemImage: "person.circle")
            }

            // Preferences Tab
            Form {
                Section {
                    Picker("Glucose Unit", selection: Bindable(glucoseService).glucoseUnit) {
                        ForEach(GlucoseUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                } header: {
                    Text("Display")
                } footer: {
                    Text("Choose how glucose values are displayed.")
                }

                Section {
                    Picker("Refresh Interval", selection: $refreshInterval) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("2 minutes").tag(120.0)
                        Text("5 minutes").tag(300.0)
                    }
                    .onChange(of: refreshInterval) { _, newValue in
                        glucoseService.updateRefreshInterval(newValue)
                    }
                } header: {
                    Text("Data Refresh")
                } footer: {
                    Text("How often to fetch new glucose readings from LibreLink.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Preferences", systemImage: "slider.horizontal.3")
            }

            // Notifications Tab
            Form {
                Section {
                    Toggle("Enable Notifications", isOn: Bindable(notificationService).notificationsEnabled)

                    if !notificationService.isAuthorized {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Notifications not authorized")
                                .font(.caption)
                            Spacer()
                            Button("Open Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                            }
                            .buttonStyle(.link)
                        }
                    }
                } header: {
                    Text("Alerts")
                }

                Section {
                    HStack {
                        Text("Low")
                        Spacer()
                        TextField("", value: Bindable(notificationService).lowThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("mg/dL")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("High")
                        Spacer()
                        TextField("", value: Bindable(notificationService).highThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("mg/dL")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Alert Thresholds")
                } footer: {
                    Text("You'll be notified when glucose crosses these levels.")
                }

                Section {
                    HStack {
                        Text("Urgent Low")
                        Spacer()
                        TextField("", value: Bindable(notificationService).urgentLowThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("mg/dL")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Urgent High")
                        Spacer()
                        TextField("", value: Bindable(notificationService).urgentHighThreshold, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                        Text("mg/dL")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Urgent Thresholds")
                } footer: {
                    Text("Critical alerts with louder sounds for urgent glucose levels.")
                }

                Section {
                    LabeledContent("Falling Fast", value: "Enabled")
                    LabeledContent("Rising Fast", value: "Enabled")
                } header: {
                    Text("Trend Alerts")
                } footer: {
                    Text("Alerts when glucose is changing rapidly.")
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("Notifications", systemImage: "bell.badge")
            }

            // About Tab
            Form {
                Section {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Build", value: "1")
                }

                Section {
                    Link(destination: URL(string: "https://libreview.com")!) {
                        Label("LibreView Website", systemImage: "arrow.up.right.square")
                    }

                    Link(destination: URL(string: "https://www.freestylelibre.com")!) {
                        Label("FreeStyle Libre", systemImage: "arrow.up.right.square")
                    }
                }

                Section {
                    Text("This app uses the unofficial LibreLinkUp API to display glucose readings. It is not affiliated with Abbott Laboratories.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 400, height: 380)
        .onAppear {
            refreshInterval = glucoseService.refreshInterval
            selectedRegion = glucoseService.selectedRegion
        }
    }

    private func login() {
        isLoggingIn = true
        errorMessage = nil

        Task {
            do {
                try await glucoseService.login(email: email, password: password, region: selectedRegion)
                glucoseService.startMonitoring()
            } catch let error as LibreAPIError {
                errorMessage = error.localizedDescription
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
