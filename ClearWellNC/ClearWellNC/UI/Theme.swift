//
//  Theme.swift
//  ClearWellNC
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Fixed deep teal, for places that need the brand color regardless of appearance (e.g. under white text).
    static let brandTeal = Color(hex: 0x0F5C73)

    /// Warm off-white in light mode, system background in dark mode.
    static let appBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemBackground
            : UIColor(red: 0.980, green: 0.969, blue: 0.949, alpha: 1)
    })

    static let cardBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .secondarySystemBackground : .white
    })
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

extension View {
    func card() -> some View { modifier(CardModifier()) }

    /// Keeps reading width comfortable on iPad while filling the screen on iPhone.
    func readableWidth() -> some View {
        frame(maxWidth: 700).frame(maxWidth: .infinity)
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
