//
//  DSTokens.swift
//  AquaShield
//
//  Design system v2 tokens: color, type, spacing, corners, elevation and motion. Everything new lives in
//  the `DS` namespace so screens move over one at a time; the older tokens (Spacing, Radius, Color.surface…)
//  keep working until every screen has moved.
//
//  Contrast (WCAG 2.1), checked against both Background and Surface:
//    Light: text primary 16.4:1, text secondary 7.0:1, accent 8.4:1, status colors 4.5–6.0:1.
//    Dark:  text primary 14.8:1, text secondary 10.9:1, accent 7.1:1, status colors 5.9–10.6:1.
//    Status colors also pass 4.5:1 on their own 12% tint, so a badge icon reads on its badge.
//

import SwiftUI
import UIKit

/// Design system namespace.
enum DS {}

// MARK: - Color

extension DS {
    enum Colors {
        // Surfaces
        static let background = Color.appBackground
        static let surface = Color.surface
        /// A card inside a card, or a selected row.
        static let surfaceRaised = Color(light: 0xEBE3D6, dark: 0x2B251F)
        static let separator = Color.textPrimary.opacity(0.10)
        /// Empty part of a ring or meter.
        static let track = Color.textPrimary.opacity(0.08)

        // Brand
        static let accent = Color.brandPrimary
        /// Text and icons on a filled accent shape.
        static let onAccent = Color.onBrand
        /// Tinted accent fill (selected cards, icon tiles).
        static let accentSoft = Color(light: 0xDCCFBC, dark: 0x3A2F25)
        /// Light tan for decoration only (gradients, rings). Never for text.
        static let water = Color(light: 0xA8896A, dark: 0xC4A584)

        // Text
        static let textPrimary = Color.textPrimary
        static let textSecondary = Color.textSecondary

        // Status, one per level. Pick through `DS.Level.color`, never directly, so color always matches the label.
        static let excellent = Color(light: 0x1E7546, dark: 0x60BB83)
        static let good = Color(light: 0x4F7330, dark: 0x9EC773)
        static let fair = Color(light: 0x8F6A00, dark: 0xEEC05B)
        static let poor = Color(light: 0xB35A00, dark: 0xF59145)
        static let unsafe = Color(light: 0xBA0C09, dark: 0xFF7F6E)
    }
}

extension Color {
    /// A color with separate light and dark values (sRGB hex). Nonisolated because UIKit may resolve
    /// the provider off the main thread.
    nonisolated init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    nonisolated convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Status level

extension DS {
    /// The five levels every status in the app is shown as. Each has its own color, icon and word,
    /// so meaning never depends on color alone.
    nonisolated enum Level: Int, CaseIterable, Comparable, Sendable, Identifiable {
        case unsafe, poor, fair, good, excellent

        var id: Int { rawValue }

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .excellent: String(localized: "Excellent")
            case .good: String(localized: "Good")
            case .fair: String(localized: "Fair")
            case .poor: String(localized: "Poor")
            case .unsafe: String(localized: "Unsafe")
            }
        }

        /// Score bands have four levels today (no Excellent), so this never returns `.excellent`.
        init(_ band: WellHealthScore.Band) {
            switch band {
            case .good: self = .good
            case .fair: self = .fair
            case .poor: self = .poor
            case .unsafe: self = .unsafe
            }
        }

        /// A single reading's level. Nil for readings that are classified, not judged (hardness).
        init?(_ tier: Interpretation.Tier) {
            switch tier {
            case .safe: self = .good
            case .watch, .nuisance: self = .fair
            case .above: self = .unsafe
            case .info: return nil
            }
        }
    }
}

extension DS.Level {
    var color: Color {
        switch self {
        case .excellent: DS.Colors.excellent
        case .good: DS.Colors.good
        case .fair: DS.Colors.fair
        case .poor: DS.Colors.poor
        case .unsafe: DS.Colors.unsafe
        }
    }

    /// A different shape per level, readable without color.
    var symbol: String { DS.Icon.level(self) }
}

// MARK: - Type

extension DS {
    /// Every style is built on a Dynamic Type text style, so it scales with the user's text size.
    /// Older DS names, mapped onto the Modernist type scale (`M.Font`) so every screen uses the same sizes.
    enum Typography {
        /// Big screen titles.
        static let display = M.Font.screenTitle
        static let title = M.Font.heading
        static let headline = M.Font.section
        static let body = M.Font.row
        static let callout = M.Font.row
        static let subheadline = M.Font.row
        static let footnote = Font.footnote
        static let caption = Font.caption.weight(.semibold)
        /// Readings and values ("6.2 mg/L").
        static let metric = M.Font.number
        /// The number inside the score ring.
        static let score = Font.system(.largeTitle, weight: .light).monospacedDigit()

        // Light weights: thin at large sizes, never below regular at small sizes.
        static let lightTitle = Font.system(.title, weight: .light)
        static let lightTitle2 = M.Font.heading
        static let lightBody = Font.system(.subheadline, weight: .light)
        /// Small uppercase section labels.
        static let eyebrow = M.Font.label

        /// A big thin number that still follows Dynamic Type (size from @ScaledMetric).
        static func thinNumber(size: CGFloat) -> Font {
            .system(size: size, weight: .thin).monospacedDigit()
        }
    }
}

// MARK: - Spacing, corners, sizes

extension DS {
    /// 4-point scale.
    enum Space {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
    }

    enum Corner {
        /// Badges, small chips.
        static let small: CGFloat = 10
        /// Buttons, rows inside a card.
        static let medium: CGFloat = 14
        /// Cards.
        static let large: CGFloat = 22
    }

    enum Size {
        /// Apple's minimum tap target.
        static let tapTarget: CGFloat = 44
        /// Primary buttons and choice cards.
        static let largeTapTarget: CGFloat = 56
        /// Reading width on iPad.
        static let readableWidth: CGFloat = 700
    }
}

// MARK: - Elevation

extension DS {
    struct Elevation: Sendable {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat

        static let none = Elevation(opacity: 0, radius: 0, y: 0)
        /// Resting card.
        static let card = Elevation(opacity: 0.06, radius: 16, y: 6)
        /// Floating bar or pressed-up card.
        static let raised = Elevation(opacity: 0.10, radius: 24, y: 10)
    }
}

private struct DSCardModifier: ViewModifier {
    var padding: CGFloat
    var elevation: DS.Elevation
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(DS.Colors.surface)
                if let tint { shape.fill(tint.opacity(0.10)) }
            }
            .overlay(shape.strokeBorder(tint?.opacity(0.35) ?? DS.Colors.separator))
            // Dark mode separates cards by surface color, not shadow.
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : elevation.opacity),
                    radius: elevation.radius, y: elevation.y)
    }
}

extension View {
    /// The v2 card surface: rounded, hairline edge, soft shadow in light mode. `tint` washes it with a status color.
    func dsCard(padding: CGFloat = DS.Space.l, elevation: DS.Elevation = .card, tint: Color? = nil) -> some View {
        modifier(DSCardModifier(padding: padding, elevation: elevation, tint: tint))
    }

    /// Screen body: padded, readable width.
    func dsScreen() -> some View {
        padding(.horizontal, DS.Space.l)
            .padding(.vertical, DS.Space.xl)
            .frame(maxWidth: DS.Size.readableWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Motion

extension DS {
    enum Motion {
        static let standard = Animation.spring(duration: 0.45, bounce: 0.12)
        static let reveal = Animation.easeOut(duration: 0.9)
        static let quick = Animation.easeOut(duration: 0.2)

        /// The animation to use, or nil (no animation) when Reduce Motion is on.
        static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }
}
