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

/// Older names, now pointing at the v2 tokens so every screen shares one look.
enum Radius {
    /// Cards, banners, buttons.
    static let card: CGFloat = DS.Corner.large
    /// Chips and rows inside a card.
    static let chip: CGFloat = DS.Corner.small
    /// Older name for rows inside a card.
    static let inner: CGFloat = chip
}

/// Minimum tap target.
enum TapTarget {
    static let minimum: CGFloat = 44
}

extension View {
    /// The standard card surface (same as `dsCard()`).
    func card() -> some View { dsCard() }

    /// Keeps reading width comfortable on iPad while filling the screen on iPhone.
    func readableWidth() -> some View {
        frame(maxWidth: 700).frame(maxWidth: .infinity)
    }

    /// Standard scrolling screen body: padded, readable width, app background.
    func screenContainer() -> some View {
        dsScreen()
    }
}
