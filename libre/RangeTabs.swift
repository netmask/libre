//
//  RangeTabs.swift
//  libre
//
//  Segmented picker for the popover chart's time range.
//

import SwiftUI

struct RangeTabs: View {
    @Binding var selection: GlucoseTimeRange

    var body: some View {
        Picker("Range", selection: $selection) {
            ForEach(GlucoseTimeRange.allCases) { range in
                Text(range.label).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
