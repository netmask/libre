//
//  AccountSettingsView.swift
//  libre
//
//  LibreLink account tab: login form when signed out, connection
//  summary and log-out when signed in.
//

import SwiftUI

struct AccountSettingsView: View {
    @Environment(GlucoseService.self) private var glucoseService

    @State private var email = ""
    @State private var password = ""
    @State private var selectedRegion: LibreRegion = .us
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                if glucoseService.connectionStatus == .connected {
                    connectedContent
                } else {
                    loginForm
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
        .task {
            selectedRegion = glucoseService.selectedRegion
        }
    }

    @ViewBuilder
    private var connectedContent: some View {
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
    }

    @ViewBuilder
    private var loginForm: some View {
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
    AccountSettingsView()
        .environment(GlucoseService())
}
