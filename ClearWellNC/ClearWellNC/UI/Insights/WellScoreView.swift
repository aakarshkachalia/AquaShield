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

/// Compact score card for the top of My Well; links to the full score screen.
struct WellScoreCard: View {
    let result: WellHealthScore.Result

    var body: some View {
        NavigationLink {
            WellScoreView()
        } label: {
            HStack(alignment: .center, spacing: 16) {
                ScoreNumber(result: result, size: .compact)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Well Health Score")
                        .font(.headline)
                    if let band = result.band {
                        StatusChip(tier: band.tier, label: band.label)
                    }
                    if !result.isComplete {
                        Text(incompleteText(result))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Shows what is pulling the score down and what to do"))
    }
}

func incompleteText(_ result: WellHealthScore.Result) -> String {
    String(localized: "Incomplete — \(result.keyTestsOnFile) of \(result.keyTestsTotal) key tests on file")
}

struct ScoreNumber: View {
    enum Size { case compact, large }

    let result: WellHealthScore.Result
    let size: Size
    /// Big number that still scales with Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var largeSize: CGFloat = 72

    var body: some View {
        Group {
            Text(result.score.map { "\($0)" } ?? "—")
                .font(size == .large
                      ? .system(size: largeSize, weight: .bold, design: .rounded)
                      : .title.weight(.bold))
                .monospacedDigit()
        }
        .foregroundStyle(result.band?.tier.color ?? .secondary)
        .frame(minWidth: size == .large ? 110 : 56, alignment: .leading)
        .accessibilityLabel(result.score.map { Text("Score \($0) out of 100") } ?? Text("No score yet"))
    }
}

/// Full score screen: number, band, top 3 factors with actions, missing tests, disclaimer.
struct WellScoreView: View {
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]

    var body: some View {
        let result = WellHealthScore.compute(results.latestScoreInput)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
            .padding()
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Well Health Score")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ result: WellHealthScore.Result) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScoreNumber(result: result, size: .large)
                .padding(.vertical, 8)
            if let band = result.band {
                StatusChip(tier: band.tier, label: band.label)
            }
            if !result.isComplete {
                Label(incompleteText(result), systemImage: "list.bullet.clipboard")
                    .font(.headline)
                Text(result.score == nil
                     ? String(localized: "We won't guess a score for tests you haven't done. Missing tests are not counted as safe.")
                     : String(localized: "Some key tests are missing, but a known problem means the score can't be higher than this."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if result.healthLimitExceeded && !result.eColiPositive {
                Text("A health-based limit is exceeded, so the score is capped at \(WellHealthScore.healthExceedanceCap).")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func factors(_ result: WellHealthScore.Result) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's pulling your score down")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(result.topFactors.enumerated()), id: \.element.id) { index, factor in
                VStack(alignment: .leading, spacing: 6) {
                    InterpretationBlock(name: "\(index + 1). \(factor.id.info.name)", interpretation: factor.interpretation)
                    Label {
                        Text(factor.nextAction)
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                    }
                    .font(.subheadline.weight(.medium))
                    .accessibilityLabel(Text("Next step: \(factor.nextAction)"))
                }
                if index < result.topFactors.count - 1 { Divider() }
            }
        }
        .card()
    }

    private func missing(_ result: WellHealthScore.Result) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tests still needed")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(result.missingKeyTests, id: \.self) { test in
                Label {
                    Text("Test for \(test.name)")
                } icon: {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary)
                }
            }
            Text("Contact your county health department or a state-certified lab to order these tests.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var howItWorks: some View {
        DisclosureGroup {
            Text("The score starts at 100. Each health-based result takes away up to 30 points depending on how close it is to its limit. Cosmetic issues like iron, hardness or pH take away less. Any result at or above a health limit caps the score at 40, and E. coli caps it at 10. Bands: Good 80–100, Fair 60–79, Poor 41–59, Unsafe 0–40.")
                .font(.subheadline)
                .padding(.top, 6)
        } label: {
            Text("How the score works")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .card()
    }
}

struct DoNotDrinkBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Do not drink untreated", systemImage: "exclamationmark.octagon.fill")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text(ContaminantID.eColi.info.actionIfAbove)
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RiskLevel.high.color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
