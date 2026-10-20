//
//  RiskCheckView.swift
//  ClearWellNC
//
//  "Should I test?" Risk Check (filled in Phase 3).
//

import SwiftUI

struct RiskCheckView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Risk Check")
                .toolbar { Button("Close") { dismiss() } }
        }
    }
}
