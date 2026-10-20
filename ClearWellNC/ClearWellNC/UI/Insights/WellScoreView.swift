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
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure

    var body: some View {
        NavigationLink {
            WellScoreView()
        } label: {
            HStack(alignment: .center, spacing: Spacing.l) {
                ScoreNumber(result: result, size: .compact)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(waterSource.scoreTitle)
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
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
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
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure

    var body: some View {
        let result = WellHealthScore.compute(results.latestScoreInput)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
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
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle(waterSource.scoreTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func header(_ result: WellHealthScore.Result) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(spacing: Spacing.m) {
                ScoreNumber(result: result, size: .large)
                if let band = result.band {
                    StatusChip(tier: band.tier, label: band.label)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s)
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
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("What's pulling your score down")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(result.topFactors.enumerated()), id: \.element.id) { index, factor in
                VStack(alignment: .leading, spacing: Spacing.s) {
                    InterpretationBlock(name: "\(index + 1). \(factor.id.info.name)", interpretation: factor.interpretation)
                    Label {
                        Text(factor.nextAction)
                    } icon: {
                        Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(Spacing.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Next step: \(factor.nextAction)"))
                }
                if index < result.topFactors.count - 1 { Divider() }
            }
        }
        .card()
    }

    private func missing(_ result: WellHealthScore.Result) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
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
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var howItWorks: some View {
        DisclosureGroup {
            Text("The score starts at 100. Each health-based result takes away up to 30 points depending on how close it is to its limit. Cosmetic issues like iron, hardness or pH take away less. Any result at or above a health limit caps the score at 40, and E. coli caps it at 10. Bands: Good 80–100, Fair 60–79, Poor 41–59, Unsafe 0–40.")
                .font(.subheadline)
                .padding(.top, Spacing.s)
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
