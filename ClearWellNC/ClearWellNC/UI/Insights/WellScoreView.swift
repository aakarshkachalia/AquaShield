//
//  WellScoreView.swift
//  ClearWellNC
//

import SwiftData
import SwiftUI

extension WellHealthScore.Band {
    var tier: Interpretation.Tier {
        switch self {
        case .good: .safe
        case .fair: .watch
        case .poor: .nuisance
        case .unsafe: .above
        }
    }
}

func incompleteText(_ result: WellHealthScore.Result) -> String {
    String(localized: "Incomplete — \(result.keyTestsOnFile) of \(result.keyTestsTotal) key tests on file")
}

/// Score inside a ring that fills to the score, colored by band. Number and band text carry the meaning;
/// the ring only reinforces them.
struct ScoreNumber: View {
    enum Size { case compact, large }

    let result: WellHealthScore.Result
    let size: Size
    @ScaledMetric(relativeTo: .largeTitle) private var largeDiameter: CGFloat = 168
    @ScaledMetric(relativeTo: .title) private var compactDiameter: CGFloat = 68
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shownFraction: Double = 0

    private var fraction: Double { Double(result.score ?? 0) / 100 }
    private var color: Color { result.band?.tier.color ?? .secondary }

    var body: some View {
        let diameter = size == .large ? largeDiameter : compactDiameter
        let lineWidth: CGFloat = size == .large ? 14 : 7
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shownFraction)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(result.score.map { "\($0)" } ?? "—")
                    .font(size == .large
                          ? .largeTitle.weight(.bold)
                          : .title2.weight(.bold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if size == .large, result.score != nil {
                    Text("out of 100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(lineWidth)
        }
        .frame(width: diameter, height: diameter)
        .onAppear { animate(to: fraction) }
        .onChange(of: fraction) { _, new in animate(to: new) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.score.map { Text("Score \($0) out of 100") } ?? Text("No score yet"))
    }

    private func animate(to value: Double) {
        if reduceMotion {
            shownFraction = value
        } else {
            withAnimation(.easeOut(duration: 0.6)) { shownFraction = value }
        }
    }
}

/// Full score screen: number, band, top 3 factors with actions, missing tests, disclaimer.
struct WellScoreView: View {
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Environment(AppSettings.self) private var settings
    private var waterSource: WaterSource { settings.waterSource }

    var body: some View {
        let result = WellHealthScore.compute(results.latestScoreInput)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                if result.eColiPositive {
                    DoNotDrinkBanner()
                }
                header(result)
                if !result.topFactors.isEmpty {
                    factors(result)
                }
                if !result.missingKeyTests.isEmpty {
                    missing(result)
                }
                howItWorks
                TestingDisclaimer(kind: .score)
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
        .navigationTitle(waterSource.scoreTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ result: WellHealthScore.Result) -> some View {
        VStack(spacing: DS.Space.l) {
            DS.ScoreRing(result: result)
                .frame(maxWidth: .infinity)
            if !result.isComplete {
                DS.InfoCard(systemImage: "list.bullet.clipboard", title: incompleteText(result),
                            message: result.score == nil
                                ? String(localized: "We don't guess. Tests you haven't done don't count as safe.")
                                : String(localized: "A known problem keeps the score this low, even with tests missing."))
            }
            if result.healthLimitExceeded && !result.eColiPositive {
                DS.InfoCard(systemImage: DS.Level.unsafe.symbol,
                            title: String(localized: "Score held at \(WellHealthScore.healthExceedanceCap) or lower"),
                            message: String(localized: "A result is above a health limit."),
                            level: .unsafe)
            }
        }
    }

    private func factors(_ result: WellHealthScore.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            sectionTitle("What's pulling your score down")
            ForEach(result.topFactors) { factor in
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    let name = factor.id.info.name
                    if let meter = DS.LevelMeter(name: name, interpretation: factor.interpretation) {
                        meter
                    } else {
                        InterpretationBlock(name: name, interpretation: factor.interpretation)
                    }
                    Label {
                        Text(factor.nextAction)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(DS.Colors.accent)
                    }
                    .font(DS.Typography.subheadline.weight(.medium))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .padding(DS.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Colors.accentSoft, in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Next step: \(factor.nextAction)"))
                }
                .dsCard()
            }
        }
    }

    private func missing(_ result: WellHealthScore.Result) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            sectionTitle("Tests still needed")
            VStack(alignment: .leading, spacing: DS.Space.m) {
                ForEach(result.missingKeyTests, id: \.self) { test in
                    Label {
                        Text("Test for \(test.name)")
                    } icon: {
                        Image(systemName: "circle.dashed").foregroundStyle(DS.Colors.textSecondary)
                    }
                    .font(DS.Typography.headline)
                    .foregroundStyle(DS.Colors.textPrimary)
                }
                Text("Your county health department or a state-certified lab can do these.")
                    .font(DS.Typography.footnote)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .dsCard()
        }
    }

    /// Band legend instead of a paragraph; the full rules sit behind "Learn why".
    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            sectionTitle("How the score works")
            VStack(alignment: .leading, spacing: DS.Space.s) {
                band(.good, "80–100")
                band(.fair, "60–79")
                band(.poor, "41–59")
                band(.unsafe, "0–40")
            }
            .dsCard()
            DS.InfoCard(systemImage: DS.Icon.score, title: String(localized: "Starts at 100"),
                        message: String(localized: "Each result close to its limit takes points away."),
                        learnMore: String(localized: "Health results take away up to 30 points each. Taste and staining issues like iron, hardness or pH take away less. Any result at or above a health limit holds the score at 40 or lower. E. coli holds it at 10 or lower."))
        }
    }

    private func band(_ level: DS.Level, _ range: String) -> some View {
        HStack {
            DS.StatusBadge(level: level)
            Spacer()
            Text(range)
                .font(DS.Typography.headline)
                .monospacedDigit()
                .foregroundStyle(DS.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(DS.Typography.title)
            .foregroundStyle(DS.Colors.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}

struct DoNotDrinkBanner: View {
    var body: some View {
        UrgentBanner {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Label("Do not drink untreated", systemImage: "exclamationmark.octagon.fill")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(ContaminantID.eColi.info.actionIfAbove)
            }
        }
    }
}
