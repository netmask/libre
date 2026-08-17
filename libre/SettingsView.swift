//
//  SettingsView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI

struct SettingsView: View {
    enum SettingsTab: Hashable {
        case account, preferences, notifications, about
    }

    @State private var selection: SettingsTab = .account

    var body: some View {
        TabView(selection: $selection) {
            Tab("Account", systemImage: "person.circle", value: SettingsTab.account) {
                AccountSettingsView()
            }

            Tab("Preferences", systemImage: "slider.horizontal.3", value: SettingsTab.preferences) {
                PreferencesSettingsView()
            }

            Tab("Notifications", systemImage: "bell.badge", value: SettingsTab.notifications) {
                NotificationSettingsView()
            }

            Tab("About", systemImage: "info.circle", value: SettingsTab.about) {
                AboutSettingsView()
            }
        }
        .frame(minWidth: 380, idealWidth: 420, minHeight: 320, idealHeight: 360)
    }
}

#Preview {
    SettingsView()
        .environment(GlucoseService())
}
