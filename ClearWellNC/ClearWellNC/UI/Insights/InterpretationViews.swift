//
//  InterpretationViews.swift
//  ClearWellNC
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
                    Text(name).font(.body.weight(.semibold))
                    Spacer()
                    StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(name).font(.body.weight(.semibold))
                    StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text(interpretation.readingText)
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                if let percent = interpretation.percentText {
                    Text("· \(percent)")
                        .foregroundStyle(.secondary)
                }
            }
            if let percent = interpretation.percentOfLimit {
                LimitMeter(percent: percent, color: interpretation.tier.color)
            }
            Text(interpretation.limitText)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(color)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0))
            }
        }
        .frame(height: 6)
        .frame(maxWidth: 260)
        .accessibilityHidden(true)
    }
}

/// Required on every score and forecast screen.
struct TestingDisclaimer: View {
    var kind: Kind = .estimate

    enum Kind {
        case estimate, score, forecast
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                Text(message)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(.tint)
            }
            .font(.caption.weight(.medium))
            Link(destination: WellResources.ncdhhsPrivateWells) {
                Label("NC DHHS: private well testing", systemImage: "arrow.up.right.square")
                    .frame(minHeight: 44)
            }
            .font(.caption)
            Link(destination: WellResources.ncCountyHealthDepartments) {
                Label("Find your county health department", systemImage: "arrow.up.right.square")
                    .frame(minHeight: 44)
            }
            .font(.caption)
        }
        .card()
    }

    private var message: String {
        switch kind {
        case .estimate:
            String(localized: "This is an estimate, not a test result. Only a test from a state-certified lab tells you what is in your water.")
        case .score:
            String(localized: "This score summarizes the results you entered. It is not a lab result or medical advice. Only a test from a state-certified lab tells you what is in your water.")
        case .forecast:
            String(localized: "Forecasts are predictions from county-wide data, not test results for your well. Only a test from a state-certified lab tells you what is in your water.")
        }
    }
}
