//
//  QuestScoreAndEndViews.swift
//  ClearWellNC
//
//  The last stop (guess your score, then the real score with its top factors) and the end screen
//  (points, what you can now read, and ONE next action).
//

import SwiftUI

struct QuestScoreStopView: View {
    let title: String
    @Binding var run: QuestRun
    let onNext: () -> Void

    @State private var celebration = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Last stop")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(M.Colors.muted)
                Text(title)
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)

                if run.hasScoreGuess {
                    if let guess = run.scoreGuess {
                        reveal(guess: guess)
                    } else {
                        guessQuestion
                    }
                } else {
                    incomplete
                }

                if run.isFinished {
                    Button(action: onNext) {
                        Text("See your results")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .sensoryFeedback(.impact(weight: .light), trigger: celebration)
    }

    private var isSerious: Bool { run.score.healthLimitExceeded || run.score.eColiPositive }

    private var guessQuestion: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Which range do you think your score is in?")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text("The score runs from 0 to 100 and sums up every result on your report.")
                .foregroundStyle(M.Colors.muted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(QuestEngine.scoreChoices, id: \.self) { band in
                QuestChoiceButton(title: QuestEngine.scoreRangeText(band), detail: band.label,
                                  systemImage: band.tier.symbol, tint: band.tier.color) {
                    run.guessScore(band)
                    if run.scoreGuessCorrect && !isSerious && (band == .good || band == .fair) {
                        celebration += 1
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func reveal(guess: WellHealthScore.Band) -> some View {
        let correct = guess == run.score.band
        VStack(spacing: Spacing.m) {
            ScoreNumber(result: run.score, size: .large)
                .overlay { SparkleBurst(trigger: celebration) }
            if let band = run.score.band {
                StatusChip(tier: band.tier, label: band.label)
            }
            Text(revealText(correct: correct, guess: guess))
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .combine)

        if !run.score.topFactors.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("What's pulling it down")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(run.score.topFactors.enumerated()), id: \.element.id) { index, factor in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        HStack {
                            Text("\(index + 1). \(factor.id.info.name)").font(.body.weight(.semibold))
                            Spacer()
                            StatusChip(tier: factor.interpretation.tier, label: factor.interpretation.chipLabel)
                        }
                        Label {
                            Text(QuestText.firstSentences(factor.nextAction, max: 2))
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                        }
                        .font(.subheadline)
                    }
                    .accessibilityElement(children: .combine)
                    if index < run.score.topFactors.count - 1 { Divider() }
                }
            }
            .card()
        }
    }

    private func revealText(correct: Bool, guess: WellHealthScore.Band) -> String {
        let points = QuestEngine.points(correct: correct)
        if isSerious {
            return correct
                ? String(localized: "Correct. A health problem keeps the score low until it's fixed.")
                : String(localized: "The score is lower than \(QuestEngine.scoreRangeText(guess)) because of a health problem.")
        }
        return correct
            ? String(localized: "You guessed it! +\(points) points")
            : String(localized: "Not quite. +\(points) points for trying")
    }

    private var incomplete: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(incompleteText(run.score), systemImage: "list.bullet.clipboard")
                .font(.headline)
            Text("We won't guess a score for tests you haven't done.")
                .foregroundStyle(M.Colors.muted)
            ForEach(run.score.missingKeyTests, id: \.self) { test in
                Label {
                    Text("Test for \(test.name)")
                } icon: {
                    Image(systemName: "circle.dashed").foregroundStyle(M.Colors.muted)
                }
            }
        }
        .card()
    }
}

struct QuestEndView: View {
    let run: QuestRun
    let newBadges: [Badge]
    let onFullReport: () -> Void
    let onDone: () -> Void

    @State private var celebration = 0

    private var isSerious: Bool { QuestEngine.requiresSafetyAlert(run.report) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(spacing: Spacing.s) {
                    Image(systemName: isSerious ? "checkmark.circle" : "flag.checkered")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                        .overlay { SparkleBurst(trigger: celebration) }
                    Text("Quest complete")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    PointsChip(points: run.points)
                    Text("You can now read \(run.stops.count) of \(run.report.interpretations.count) results on your report.")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .card()

                nextActionCard

                if run.report.isSample {
                    Label("This was sample data, so points and badges weren't saved.", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(M.Colors.muted)
                } else if !newBadges.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        Text("New badge")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(newBadges) { badge in
                            HStack(spacing: Spacing.m) {
                                IconTile(systemImage: badge.symbol)
                                VStack(alignment: .leading, spacing: Spacing.xs) {
                                    Text(badge.title).font(.body.weight(.semibold))
                                    Text(badge.howToEarn).font(.subheadline).foregroundStyle(M.Colors.muted)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .card()
                }

                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(PrimaryButtonStyle())
                Button(action: onFullReport) {
                    Text("See full report")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .onAppear {
            // No celebration when the report has a health problem.
            if !isSerious { celebration += 1 }
        }
    }

    private var nextActionCard: some View {
        let next = run.nextAction
        let urgent = next.kind == .urgent
        return VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Your next step")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            Label {
                Text(QuestText.firstSentences(next.text, max: 2))
                    .font(.body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: symbol(next.kind))
                    .foregroundStyle(urgent ? Color.statusAbove : Color.accentColor)
            }
        }
        .card()
        .overlay {
            if urgent {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.statusAbove.opacity(0.5), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func symbol(_ kind: QuestEngine.NextActionKind) -> String {
        switch kind {
        case .urgent: "exclamationmark.octagon.fill"
        case .fix: "wrench.and.screwdriver.fill"
        case .test: "testtube.2"
        case .retest: "calendar.badge.clock"
        case .allSet: "checkmark.seal.fill"
        }
    }
}

/// Every result on the report, no game. Reachable from every Report Quest screen.
struct QuestFullReportView: View {
    let report: QuestReport
    let scoreTitle: String

    var body: some View {
        let score = WellHealthScore.compute(report.scoreInput)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Full report")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(report.date.formatted(date: .long, time: .omitted))
                        .foregroundStyle(M.Colors.muted)
                }
                if QuestEngine.eColiPositive(report) {
                    DoNotDrinkBanner()
                }
                HStack(spacing: Spacing.l) {
                    ScoreNumber(result: score, size: .compact)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(scoreTitle).font(.headline)
                        if let band = score.band {
                            StatusChip(tier: band.tier, label: band.label)
                        } else {
                            Text(incompleteText(score)).font(.subheadline).foregroundStyle(M.Colors.muted)
                        }
                    }
                }
                .card()
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: Spacing.s) {
                    ForEach(Array(report.interpretations.enumerated()), id: \.offset) { index, interpretation in
                        InterpretationBlock(name: interpretation.id.info.name, interpretation: interpretation)
                        if index < report.interpretations.count - 1 { Divider() }
                    }
                }
                .card()
                TestingDisclaimer(kind: .score)
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
    }
}
