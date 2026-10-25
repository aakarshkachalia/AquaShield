//
//  V2Components.swift
//  ClearWellNC
//
//  Small pieces shared by the dashboard and its detail screens, built from DS tokens.
//

import SwiftUI

/// A square-ish dashboard card: icon, label, one big value, one short caption.
struct DashboardTile: View {
    let systemImage: String
    let title: String
    let value: String
    var caption: String?
    var level: DS.Level?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            HStack {
                Image(systemName: systemImage)
                    .font(M.Font.section)
                    .foregroundStyle(level?.color ?? DS.Colors.accent)
                    .accessibilityHidden(true)
                Text(title)
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
            }
            Text(value)
                .font(DS.Typography.metric)
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let caption {
                Text(caption)
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let level {
                DS.StatusBadge(level: level)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .dsCard(padding: DS.Space.m)
        .contentShape(Rectangle())
        // No accessibilityElement here: the NavigationLink around it already reads as one button, and an
        // inner element would hide the link's identifier from UI tests.
    }
}

/// A filter or reading flag: icon + words, never color alone.
struct FlagChip: View {
    let text: String
    var systemImage = "exclamationmark.triangle.fill"
    var color: Color = DS.Colors.fair

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(DS.Typography.footnote.weight(.semibold))
            .foregroundStyle(DS.Colors.textPrimary)
            .padding(.horizontal, DS.Space.s)
            .padding(.vertical, DS.Space.xs)
            .background(color.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.4)))
    }
}

/// Hard safety alert: fixed red in both modes so white text always passes contrast.
struct SafetyAlertCard: View {
    let alert: SafetyAlert

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Label(alert.title, systemImage: DS.Level.unsafe.symbol)
                .font(DS.Typography.headline)
                .accessibilityAddTraits(.isHeader)
            Text(alert.message)
                .font(DS.Typography.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xB3161F), in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
        .accessibilityElement(children: .combine)
        .onAppear { DS.Haptics.warning() }
    }
}

extension TapItem.Level {
    var dsLevel: DS.Level? {
        switch self {
        case .good: .good
        case .fair: .fair
        case .poor: .poor
        case .unsafe: .unsafe
        case .inconclusive, .notScored: nil
        }
    }
}

extension TapScoreResult {
    var dsLevel: DS.Level { DS.Level(band) }
}

extension FilterFlag {
    var symbol: String {
        switch self {
        case .uncertified: "questionmark.diamond.fill"
        case .expired: "clock.badge.exclamationmark.fill"
        case .aboveCertifiedLevel: "arrow.up.to.line"
        case .noChallengeLevel: "questionmark.circle.fill"
        case .notCovered: "minus.circle.fill"
        case .showerChlorineOnly: "shower.fill"
        case .uvMicrobesOnly: "sun.max.fill"
        }
    }
}

/// "Educational, not medical advice" footer for household and results screens.
struct MedicalDisclaimer: View {
    var body: some View {
        Label(ExposureRisk.disclaimer, systemImage: "stethoscope")
            .font(DS.Typography.footnote)
            .foregroundStyle(DS.Colors.textSecondary)
    }
}

/// Section title used across v2 screens.
struct DSSectionTitle: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(DS.Typography.title)
            .foregroundStyle(DS.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DS.Space.s)
    }
}

/// Equal-width columns; each row is as tall as its tallest tile. Every child is laid out (not lazy), so all
/// of them stay in the accessibility tree.
struct TileGrid: Layout {
    var columns: Int
    var spacing: CGFloat

    private func columnWidth(_ width: CGFloat) -> CGFloat {
        let count = CGFloat(max(columns, 1))
        return max(0, (width - spacing * (count - 1)) / count)
    }

    private func rowHeights(_ subviews: Subviews, width: CGFloat) -> [CGFloat] {
        let proposal = ProposedViewSize(width: columnWidth(width), height: nil)
        return stride(from: 0, to: subviews.count, by: max(columns, 1)).map { start in
            subviews[start..<min(start + max(columns, 1), subviews.count)]
                .map { $0.sizeThatFits(proposal).height }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 360
        let heights = rowHeights(subviews, width: width)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(heights.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = columnWidth(bounds.width)
        let heights = rowHeights(subviews, width: bounds.width)
        var y = bounds.minY
        for (row, height) in heights.enumerated() {
            for column in 0..<max(columns, 1) {
                let index = row * max(columns, 1) + column
                guard index < subviews.count else { break }
                let x = bounds.minX + CGFloat(column) * (width + spacing)
                subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                                      proposal: ProposedViewSize(width: width, height: height))
            }
            y += height + spacing
        }
    }
}

/// A compact icon shortcut for tab menus: icon in a soft circle, one-line title, optional caption.
struct ShortcutTile: View {
    let title: String
    let systemImage: String
    var caption: String?
    var tint: Color = DS.Colors.accent

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Image(systemName: systemImage)
                .font(.system(.title3, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(title)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Colors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let caption {
                Text(caption)
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
        .contentShape(Rectangle())
    }
}
