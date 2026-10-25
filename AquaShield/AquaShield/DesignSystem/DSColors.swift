//
//  DSColors.swift
//  AquaShield
//
//  Named colors (Assets.xcassets, each with a dark-mode variant). Views use these, never raw hex.
//  Status colors are only ever chosen through `Interpretation.Tier.color`, which maps the app's
//  status classification to color, so color always agrees with the text label next to it.
//

import SwiftUI

// Named colors in Assets.xcassets get generated symbols (Color.brandPrimary, .onBrand, .appBackground,
// .surface, .textPrimary, .textSecondary, .statusSafe, .statusWatch, .statusDanger, .statusUnknown).

extension Color {
    // MARK: Brand

    /// Brand blue that stays dark in both modes, for white text on a filled shape.
    static let brandPrimaryFixed = Color(hex: 0x0B4A80)


    /// Hairline card edge, visible in both modes.
    static let cardBorder = Color.textPrimary.opacity(0.10)


    // MARK: Older names kept so existing views read the same tokens

    static let cardBackground = surface
    static let statusAbove = statusDanger
    /// Over a cosmetic guideline: shares the watch color; the icon and text say "not a health limit".
    static let statusNuisance = statusWatch

    // MARK: Helpers

    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Interpretation.Tier {
    /// The only place status maps to color.
    var color: Color {
        switch self {
        case .safe: .statusSafe
        case .watch, .nuisance: .statusWatch
        case .above: .statusDanger
        case .info: .statusUnknown
        }
    }

    /// Every status also has its own icon, so color is never the only signal.
    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .watch: "eye.fill"
        case .above: "exclamationmark.triangle.fill"
        case .nuisance: "exclamationmark.circle.fill"
        case .info: "info.circle.fill"
        }
    }
}
