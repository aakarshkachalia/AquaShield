//
//  DSRiskStyles.swift
//  ClearWellNC
//
//  Area-risk styling (map palette and level badge) and the compact lab-status styling.
//

import SwiftUI

extension RiskLevel {
    /// Map palette, light to dark (data colors from the spec). Lead's "Test regardless" uses the brand blue.
    var color: Color {
        switch self {
        case .lowerThanTypical: Color(hex: 0xFDE4D8)
        case .typical: Color(hex: 0xF9AB8F)
        case .elevated: Color(hex: 0xEC6246)
        case .high: Color(hex: 0xB3161F)
        case .testRegardless: .brandPrimaryFixed
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

extension ResultStatus.Kind {
    var color: Color {
        switch self {
        case .pass: .statusSafe
        case .notice: .statusWatch
        case .above: .statusDanger
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

/// Area risk level badge: color + icon + text.
struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Label(level.label, systemImage: level.symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(level.onColor)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(level.color, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.textPrimary.opacity(0.15)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Risk level: \(level.label)"))
    }
}
