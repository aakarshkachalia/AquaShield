//
//  DSPreviewSupport.swift
//  ClearWellNC
//
//  Every component previews in light, dark and the largest accessibility text size.
//

import SwiftUI

enum DSPreviewMode: String, CaseIterable, Identifiable {
    case light, dark, largestText

    var id: Self { self }
}

extension View {
    /// Wraps a component sample for the Xcode canvas: scrolling, padded, app background, the given mode.
    func dsPreview(_ mode: DSPreviewMode) -> some View {
        ScrollView {
            self
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DS.Colors.background)
        .preferredColorScheme(mode == .dark ? .dark : .light)
        .environment(\.dynamicTypeSize, mode == .largestText ? .accessibility5 : .large)
    }
}
