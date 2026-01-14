//
//  DisclaimerView.swift
//  libre
//
//  Created by Jonathan Garay on 2026-01-09.
//

import SwiftUI

struct DisclaimerView: View {
    @Environment(\.dismissWindow) private var dismissWindow
    @Binding var hasAcceptedDisclaimer: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Important Disclaimer")
                .font(.title.bold())

            ScrollView {
                Text(disclaimerText)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 200)
            .padding()
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 12) {
                Button {
                    UserDefaults.standard.set(true, forKey: "hasAcceptedDisclaimer")
                    hasAcceptedDisclaimer = true
                    dismissWindow(id: "disclaimer")
                } label: {
                    Text("I Understand and Accept")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("Quit")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(30)
        .frame(width: 450)
    }

    private var disclaimerText: String {
        """
        This application is provided for INFORMATIONAL PURPOSES ONLY.

        This app is not a medical device and should not be used to make medical decisions. The glucose readings displayed are retrieved from LibreLinkUp and may be delayed, inaccurate, or incomplete.

        DO NOT use this application to make treatment decisions regarding insulin dosing, food intake, or any other medical interventions.

        ALWAYS consult your glucose meter, continuous glucose monitor, or healthcare provider before making any medical decisions.

        By using this application, you acknowledge that:

        • This app is not intended to replace professional medical advice, diagnosis, or treatment.

        • Any decisions you make based on information from this app are your sole responsibility.

        • The developers of this application are not liable for any harm, injury, or damages resulting from the use of this app.

        • You should always verify glucose readings with an approved medical device before taking action.

        If you experience a medical emergency, contact your healthcare provider or emergency services immediately.
        """
    }
}

#Preview {
    DisclaimerView(hasAcceptedDisclaimer: .constant(false))
}
