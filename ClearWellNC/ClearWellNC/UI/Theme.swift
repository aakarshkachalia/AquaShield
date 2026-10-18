//
//  Theme.swift
//  ClearWellNC
//
//  Design system: "Accessible & Ethical" — calm water teal, high contrast, system type with
//  Dynamic Type, color never the only signal. Every screen should use these tokens and components.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Separate values for light and dark appearance.
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    /// Fixed deep teal, for places that need the brand color regardless of appearance (e.g. under white text).
    static let brandTeal = Color(hex: 0x0F5C73)

    /// Cool mist in light mode, system background in dark mode.
    static let appBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemBackground
            : UIColor(red: 0.949, green: 0.965, blue: 0.973, alpha: 1)
    })

    static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .white
    })

    /// Hairline card edge, visible in both modes.
    static let cardBorder = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor(red: 0.059, green: 0.361, blue: 0.451, alpha: 0.10)
    })

    // Status colors. Light values reach 4.5:1 on white; dark values reach 4.5:1 on the dark card.
    static let statusSafe = Color.dynamic(light: 0x047857, dark: 0x34D399)
    static let statusWatch = Color.dynamic(light: 0xB45309, dark: 0xFBBF24)
    static let statusNuisance = Color.dynamic(light: 0x8A5A00, dark: 0xE9B44C)
    static let statusAbove = Color.dynamic(light: 0xB3161F, dark: 0xFF7A7A)
}

/// Spacing scale. Use these instead of one-off numbers.
enum Spacing {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Radius {
    /// Cards and banners.
    static let card: CGFloat = 18
    /// Rows and tiles inside a card.
    static let inner: CGFloat = 12
}

private struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: shape)
            .overlay(shape.strokeBorder(Color.cardBorder))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.04), radius: 8, y: 2)
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Keeps reading width comfortable on iPad while filling the screen on iPhone.
    func readableWidth() -> some View {
        frame(maxWidth: 700).frame(maxWidth: .infinity)
    }
}

// MARK: - Components

/// SF Symbol on a tinted rounded square. Decorative: hidden from VoiceOver.
struct IconTile: View {
    let systemImage: String
    var color: Color = .accentColor
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icon tile, title, subtitle and chevron: the card used for every "go to" row.
struct NavigationCardLabel: View {
    let title: Text
    let subtitle: Text
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            IconTile(systemImage: systemImage)
            VStack(alignment: .leading, spacing: 2) {
                title
                    .font(.headline)
                    .foregroundStyle(.primary)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// Section title used between groups of cards.
struct SectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, Spacing.s)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Risk level styling

extension RiskLevel {
    /// Map palette, light to dark. Lead's "Test regardless" uses the brand teal.
    var color: Color {
        switch self {
        case .lowerThanTypical: Color(hex: 0xFDE4D8)
        case .typical: Color(hex: 0xF9AB8F)
        case .elevated: Color(hex: 0xEC6246)
        case .high: Color(hex: 0xB3161F)
        case .testRegardless: .brandTeal
        }
    }

    /// Text color with sufficient contrast on `color`.
    var onColor: Color {
        switch self {
        case .high, .testRegardless: .white
        case .elevated, .typical, .lowerThanTypical: Color(hex: 0x1A1A1A)
        }
    }

    var symbol: String {
        switch self {
        case .high: "exclamationmark.triangle.fill"
        case .elevated: "arrow.up.circle.fill"
        case .typical: "equal.circle.fill"
        case .lowerThanTypical: "arrow.down.circle.fill"
        case .testRegardless: "testtube.2"
        }
    }
}

// MARK: - Lab result styling

extension ResultStatus.Kind {
    var color: Color {
        switch self {
        case .pass: .statusSafe
        case .notice: .statusWatch
        case .above: .statusAbove
        }
    }

    var symbol: String {
        switch self {
        case .pass: "checkmark.circle.fill"
        case .notice: "exclamationmark.circle.fill"
        case .above: "exclamationmark.triangle.fill"
        }
    }
}

/// Icon + text status line for a lab value.
struct ResultStatusLabel: View {
    let status: ResultStatus

    var body: some View {
        Label {
            Text(status.text)
        } icon: {
            Image(systemName: status.kind.symbol)
                .foregroundStyle(status.kind.color)
        }
        .font(.subheadline)
    }
}

/// Level badge: color + icon + text, so color is never the only signal.
struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Label(level.label, systemImage: level.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(level.onColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(level.color, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Risk level: \(level.label)"))
    }
}

/// Red alert banner (E. coli). Fixed red so white text always passes contrast.
struct UrgentBanner<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RiskLevel.high.color, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}
