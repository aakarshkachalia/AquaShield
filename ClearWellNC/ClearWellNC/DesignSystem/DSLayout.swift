//
//  DSLayout.swift
//  ClearWellNC
//
//  Spacing scale, corner radii and the card surface. Use these instead of one-off numbers.
//

import SwiftUI

/// 4 / 8 / 12 / 16 / 24 / 32.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    /// Cards, banners, buttons.
    static let card: CGFloat = 12
    /// Chips and rows inside a card.
    static let chip: CGFloat = 8
    /// Older name for rows inside a card.
    static let inner: CGFloat = chip
}

/// Minimum tap target.
enum TapTarget {
    static let minimum: CGFloat = 44
}

private struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: shape)
            .overlay(shape.strokeBorder(Color.cardBorder))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: Spacing.s, y: 2)
    }
}

extension View {
    /// The standard card surface.
    func card() -> some View { modifier(CardModifier()) }

    /// Keeps reading width comfortable on iPad while filling the screen on iPhone.
    func readableWidth() -> some View {
        frame(maxWidth: 700).frame(maxWidth: .infinity)
    }

    /// Standard scrolling screen body: padded, readable width, app background.
    func screenContainer() -> some View {
        padding(Spacing.l)
            .readableWidth()
    }
}
