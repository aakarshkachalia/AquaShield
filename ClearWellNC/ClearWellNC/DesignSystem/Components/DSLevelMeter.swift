//
//  DSLevelMeter.swift
//  ClearWellNC
//
//  One reading against its limit: name and status badge, the value, a bar with the limit marked, and the
//  limit as text. The bar is drawn so the limit sits at the same spot (two-thirds across) on every meter,
//  which makes meters easy to compare down a list.
//

import SwiftUI

extension DS {
    struct LevelMeter: View {
        let name: String
        let level: Level
        /// "6.2 mg/L"
        let valueText: String
        /// "10 mg/L"
        let limitText: String
        /// Reading divided by limit (1 = at the limit).
        let ratio: Double
        /// Overrides the badge word ("Above limit"). Defaults to the level name.
        var badgeText: String?

        /// Where the limit tick sits along the bar.
        static let limitPosition: Double = 2.0 / 3.0

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var shownFill: Double = 0

        private var fill: Double { min(max(ratio, 0) * Self.limitPosition, 1) }

        var body: some View {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                header
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(valueText)
                        .font(DS.Typography.metric)
                        .foregroundStyle(DS.Colors.textPrimary)
                    bar
                    Label {
                        Text("Limit: \(limitText)")
                    } icon: {
                        Image(systemName: "line.diagonal")
                            .rotationEffect(.degrees(45))
                    }
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .onAppear { reveal() }
            .onChange(of: fill) { _, _ in reveal() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(name))
            .accessibilityValue(Text("\(valueText). Limit \(limitText). \(badgeText ?? level.label)"))
        }

        @ViewBuilder
        private var header: some View {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    title
                    DS.StatusBadge(level: level, text: badgeText)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    title
                    Spacer(minLength: DS.Space.s)
                    DS.StatusBadge(level: level, text: badgeText)
                }
            }
        }

        private var title: some View {
            Text(name)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Colors.textPrimary)
        }

        private var bar: some View {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Colors.track)
                    Capsule()
                        .fill(level.color)
                        .frame(width: max(width * shownFill, 8))
                    // Limit tick, taller than the bar so it shows even when the fill passes it.
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(DS.Colors.textPrimary)
                        .frame(width: 3, height: 22)
                        .offset(x: width * Self.limitPosition - 1.5)
                }
                .frame(height: 22)
            }
            .frame(height: 22)
            .padding(.vertical, DS.Space.xs)
        }

        private func reveal() {
            if let animation = DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion) {
                withAnimation(animation) { shownFill = fill }
            } else {
                shownFill = fill
            }
        }
    }
}

extension DS.LevelMeter {
    /// From raw numbers: formats "6.2 mg/L" and "10 mg/L".
    init(name: String, value: Double, limit: Double, unit: String, level: DS.Level) {
        let format: (Double) -> String = { "\($0.formatted(.number.precision(.fractionLength(0...3)))) \(unit)" }
        self.init(name: name, level: level, valueText: format(value), limitText: format(limit),
                  ratio: limit > 0 ? value / limit : 0)
    }

    /// From an interpreted reading. Nil for readings with no single maximum (pH, hardness, bacteria).
    init?(name: String, interpretation: Interpretation) {
        guard let percent = interpretation.percentOfLimit, let level = DS.Level(interpretation.tier) else { return nil }
        self.init(name: name, level: level, valueText: interpretation.readingText,
                  limitText: interpretation.limitText, ratio: percent / 100, badgeText: interpretation.chipLabel)
    }
}

private struct LevelMeterSamples: View {
    var body: some View {
        VStack(spacing: DS.Space.l) {
            DS.LevelMeter(name: "Nitrate", value: 2.1, limit: 10, unit: "mg/L", level: .good)
                .dsCard()
            DS.LevelMeter(name: "Arsenic", value: 7, limit: 10, unit: "µg/L", level: .fair)
                .dsCard()
            DS.LevelMeter(name: "Lead", value: 22, limit: 15, unit: "µg/L", level: .unsafe)
                .dsCard()
        }
    }
}

#Preview("Light") { LevelMeterSamples().dsPreview(.light) }
#Preview("Dark") { LevelMeterSamples().dsPreview(.dark) }
#Preview("Largest text") { LevelMeterSamples().dsPreview(.largestText) }
