//
//  InterpretationViews.swift
//  AquaShield
//
//  Reusable views for the interpretation layer: status chip, reading block, disclaimer.
//

import SwiftUI

/// Name, chip, reading, % of limit, limit, and the plain-English sentence.
struct InterpretationBlock: View {
    let name: String
    let interpretation: Interpretation

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(name).font(M.Font.section)
                    Spacer()
                    StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(name).font(M.Font.section)
                    StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(interpretation.readingText)
                    .font(M.Font.heading)
                    .monospacedDigit()
                if let percent = interpretation.percentText {
                    Text("· \(percent)")
                        .foregroundStyle(M.Colors.muted)
                }
            }
            if let percent = interpretation.percentOfLimit {
                LimitMeter(percent: percent, color: interpretation.tier.color)
            }
            Text(interpretation.limitText)
                .font(.caption)
                .foregroundStyle(M.Colors.muted)
            Text(interpretation.sentence)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Spacing.s)
        .accessibilityElement(children: .combine)
    }
}

/// Bar showing how close a reading is to its limit. The end of the track is the limit.
/// Decorative: the "% of limit" text next to the reading says the same thing.
struct LimitMeter: View {
    let percent: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let fraction = min(max(percent / 100, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(M.Colors.ink.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 260)
        .accessibilityHidden(true)
    }
}

/// Score / forecast disclaimer: a screen-specific sentence plus the standard DisclaimerFooter text.
struct TestingDisclaimer: View {
    var kind: Kind = .estimate

    enum Kind {
        case estimate, score, forecast
    }

    var body: some View {
        DisclaimerFooter(lead: lead)
    }

    private var lead: String {
        switch kind {
        case .estimate: String(localized: "This is an estimate, not a test result.")
        case .score: String(localized: "This score summarizes the results you entered. It is not a lab result.")
        case .forecast: Wording.adapt(String(localized: "Forecasts are predictions from county-wide data, not test results for your well."))
        }
    }
}
