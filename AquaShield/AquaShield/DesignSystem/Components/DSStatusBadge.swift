//
//  DSStatusBadge.swift
//  AquaShield
//
//  Icon + word + color. The word is always there; color never stands alone.
//

import SwiftUI

extension DS {
    struct StatusBadge: View {
        enum Size { case regular, large }

        let level: Level
        /// Overrides the level word ("Above limit"). Keep it short.
        var text: String?
        var size: Size = .regular

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: DS.Corner.small, style: .continuous)
            Label {
                Text(text ?? level.label)
                    .foregroundStyle(DS.Colors.textPrimary)
            } icon: {
                Image(systemName: level.symbol)
                    .foregroundStyle(level.color)
            }
            .font(size == .large ? DS.Typography.headline : DS.Typography.subheadline.weight(.semibold))
            .padding(.horizontal, size == .large ? DS.Space.m : DS.Space.s)
            .padding(.vertical, size == .large ? DS.Space.s : DS.Space.xs)
            .background(level.color.opacity(0.12), in: shape)
            .overlay(shape.strokeBorder(level.color.opacity(0.45)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Status: \(text ?? level.label)"))
        }
    }
}

private struct StatusBadgeSamples: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            ForEach(DS.Level.allCases.reversed()) { level in
                HStack {
                    DS.StatusBadge(level: level)
                    DS.StatusBadge(level: level, size: .large)
                }
            }
            DS.StatusBadge(level: .unsafe, text: String(localized: "Above limit"))
        }
    }
}

#Preview("Light") { StatusBadgeSamples().dsPreview(.light) }
#Preview("Dark") { StatusBadgeSamples().dsPreview(.dark) }
#Preview("Largest text") { StatusBadgeSamples().dsPreview(.largestText) }
