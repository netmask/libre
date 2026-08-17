//
//  AboutSettingsView.swift
//  libre
//
//  Version info, links, and the command line tool installer.
//

import SwiftUI

struct AboutSettingsView: View {
    @State private var cliInstalled = false
    @State private var cliErrorMessage: String?

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: versionString)
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
        .task {
            cliInstalled = FileManager.default.fileExists(atPath: "/usr/local/bin/libre")
        }
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
}

#Preview {
    AboutSettingsView()
}
