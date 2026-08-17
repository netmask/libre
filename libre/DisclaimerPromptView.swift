//
//  DisclaimerPromptView.swift
//  libre
//
//  Shown in the menu bar popover until the disclaimer has been accepted.
//

import SwiftUI

struct DisclaimerPromptView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
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
    }
}

#Preview {
    DisclaimerPromptView()
}
