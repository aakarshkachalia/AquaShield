//
//  StormModeView.swift
//  ClearWellNC
//
//  Storm Mode (filled in Phase 5).
//

import SwiftUI

struct StormModeView: View {
    var body: some View {
        Text("My well flooded").navigationTitle("My well flooded")
    }
}

/// Home card shown when the Risk Check reported flooding.
struct StormHomeCard: View {
    var body: some View { EmptyView() }
}
