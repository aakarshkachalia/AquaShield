//
//  QuestStopView.swift
//  ClearWellNC
//
//  One contaminant stop: reading and limit, "Safe, Watch, or Above limit?", the reveal, a
//  "Did you know?" fact, and an optional bonus question. Serious results use a calm, neutral style.
//

import SwiftUI

struct QuestStopView: View {
    let stop: QuestStop
    let totalStops: Int
    @Binding var run: QuestRun
    let onNext: () -> Void

    @State private var celebration = 0
    @State private var showingBonus = false

    private var chosen: QuestAnswer? { run.answer(for: stop) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Text("Stop \(stop.id + 1) of \(totalStops)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                ReadingSummary(stop: stop)
                    .card()

                Text("Is this Safe, Watch, or Above limit?")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: Spacing.m) {
                    ForEach(QuestAnswer.allCases, id: \.self) { answer in
                        QuestChoiceButton(title: answer.label, systemImage: answer.symbol,
                                          tint: chosen == nil ? answer.tier.color : .secondary,
                                          state: choiceState(answer)) {
                            choose(answer)
                        }
                        .disabled(chosen != nil)
                    }
                }
                .overlay { SparkleBurst(trigger: celebration) }

                if let chosen {
                    reveal(chosen)
                    factCard
                    bonusSection
                    Button(action: onNext) {
                        Text("Next")
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
        // Light haptic only for a correct Safe/Watch answer on a non-serious result.
        .sensoryFeedback(.impact(weight: .light), trigger: celebration)
    }

    // MARK: Answering

    private func choiceState(_ answer: QuestAnswer) -> QuestChoiceButton.ChoiceState {
        guard let chosen else { return .idle }
        if answer == chosen { return answer == stop.correctAnswer ? .chosenCorrect : .chosenWrong }
        if answer == stop.correctAnswer { return .revealedCorrect }
        return .dimmed
    }

    private func choose(_ answer: QuestAnswer) {
        guard chosen == nil else { return }
        run.answer(stop, with: answer)
        if stop.celebrates(answer) { celebration += 1 }
    }

    // MARK: Reveal

    @ViewBuilder
    private func reveal(_ chosen: QuestAnswer) -> some View {
        let correct = chosen == stop.correctAnswer
        VStack(alignment: .leading, spacing: Spacing.m) {
            Label {
                Text(headline(correct: correct))
                    .font(.headline)
            } icon: {
                Image(systemName: stop.isSerious ? "info.circle.fill" : (correct ? "checkmark.circle.fill" : "lightbulb.fill"))
                    .foregroundStyle(stop.isSerious ? Color.secondary : (correct ? Color.statusSafe : Color.statusWatch))
            }
            .accessibilityAddTraits(.isHeader)

            StatusChip(tier: stop.interpretation.tier, label: stop.interpretation.chipLabel)
            Text(stop.explanation)
                .fixedSize(horizontal: false, vertical: true)

            if let action = stop.action {
                Label {
                    Text(QuestText.firstSentences(action, max: 2))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                }
                .font(.subheadline.weight(.semibold))
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.inner, style: .continuous))
            }
        }
        .card()
        .overlay {
            if stop.isSerious {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.statusAbove.opacity(0.5), lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Serious results never get celebratory wording.
    private func headline(correct: Bool) -> String {
        let points = QuestEngine.points(correct: correct)
        if stop.isSerious {
            return correct
                ? String(localized: "Correct — here's what to do")
                : String(localized: "The answer is Above limit — here's what to do")
        }
        return correct
            ? String(localized: "Correct! +\(points) points")
            : String(localized: "Not quite. It's \(stop.correctAnswer.label). +\(points) points for trying")
    }

    private var factCard: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Did you know?").font(.headline)
                Text(stop.fact).fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: "lightbulb.max.fill").foregroundStyle(Color.statusWatch)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    // MARK: Bonus

    @ViewBuilder
    private var bonusSection: some View {
        if let bonus = stop.bonus {
            if showingBonus || run.bonusAnswer(for: stop) != nil {
                bonusQuestion(bonus)
            } else {
                Button {
                    showingBonus = true
                } label: {
                    Label("Bonus question (optional)", systemImage: "plus.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func bonusQuestion(_ bonus: QuizQuestion) -> some View {
        let chosen = run.bonusAnswer(for: stop)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Bonus question")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(bonus.prompt)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(bonus.options.enumerated()), id: \.offset) { index, option in
                QuestChoiceButton(title: option, systemImage: "circle", tint: .secondary,
                                  state: bonusState(index, chosen: chosen, correct: bonus.correctIndex)) {
                    run.answerBonus(stop, optionIndex: index)
                }
                .disabled(chosen != nil)
            }
            if let chosen {
                let right = chosen == bonus.correctIndex
                Text("\(right ? String(localized: "Correct!") : String(localized: "Not quite.")) \(QuestText.firstSentences(bonus.explanation, max: 2)) +\(QuestEngine.points(correct: right)) points")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private func bonusState(_ index: Int, chosen: Int?, correct: Int) -> QuestChoiceButton.ChoiceState {
        guard let chosen else { return .idle }
        if index == chosen { return index == correct ? .chosenCorrect : .chosenWrong }
        return index == correct ? .revealedCorrect : .dimmed
    }
}
