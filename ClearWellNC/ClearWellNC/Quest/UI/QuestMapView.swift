//
//  QuestMapView.swift
//  ClearWellNC
//
//  The level-select path: one node per contaminant, then the score. Only the next node is playable.
//

import SwiftUI

struct QuestMapView: View {
    let run: QuestRun
    let scoreTitle: String
    let onPlayStop: (Int) -> Void
    let onPlayScore: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text("Report Quest")
                            .font(M.Font.screenTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("Read your report one result at a time.")
                            .foregroundStyle(M.Colors.muted)
                    }
                    Spacer(minLength: Spacing.s)
                    PointsChip(points: run.points)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(run.stops) { stop in
                        node(number: stop.id + 1, title: stop.name, state: state(of: stop),
                             isLast: false) { onPlayStop(stop.id) }
                    }
                    node(number: run.stops.count + 1, title: scoreTitle, state: scoreState,
                         isLast: true, symbol: "gauge.with.needle", action: onPlayScore)
                }
                .card()

                primaryButton
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
    }

    // MARK: Node

    enum NodeState { case locked, current, correct, tried }

    private func state(of stop: QuestStop) -> NodeState {
        if run.answer(for: stop) != nil { return run.isCorrect(stop) ? .correct : .tried }
        return run.currentStopIndex == stop.id ? .current : .locked
    }

    private var scoreState: NodeState {
        if run.isFinished { return run.scoreGuessCorrect || !run.hasScoreGuess ? .correct : .tried }
        return run.contaminantStopsDone ? .current : .locked
    }

    private func node(number: Int, title: String, state: NodeState, isLast: Bool,
                      symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Spacing.m) {
                VStack(spacing: 0) {
                    ZStack {
                        Circle()
                            .fill(fill(state))
                            .frame(width: 48, height: 48)
                        Circle()
                            .strokeBorder(state == .current ? Color.accentColor : Color.clear, lineWidth: 3)
                            .frame(width: 56, height: 56)
                        icon(state: state, number: number, symbol: symbol)
                    }
                    .frame(width: 56, height: 56)
                    if !isLast {
                        Rectangle()
                            .fill(M.Colors.ink.opacity(0.12))
                            .frame(width: 3, height: 20)
                    }
                }
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(M.Font.section)
                        .foregroundStyle(state == .locked ? M.Colors.muted : M.Colors.ink)
                    Text(stateText(state))
                        .font(.subheadline)
                        .foregroundStyle(M.Colors.muted)
                }
                .padding(.bottom, isLast ? 0 : 20)
                Spacer(minLength: 0)
                if state == .current {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .padding(.bottom, isLast ? 0 : 20)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Stop \(number) of \(run.stops.count + 1), \(title)"))
        .accessibilityValue(Text(stateText(state)))
        .accessibilityHint(state == .current ? Text("Starts this stop") : Text(""))
    }

    @ViewBuilder
    private func icon(state: NodeState, number: Int, symbol: String?) -> some View {
        switch state {
        case .correct:
            Image(systemName: "checkmark").font(M.Font.heading).foregroundStyle(.white)
        case .tried:
            Image(systemName: "checkmark").font(M.Font.heading).foregroundStyle(.white)
        case .current:
            if let symbol {
                Image(systemName: symbol).font(M.Font.heading).foregroundStyle(.white)
            } else {
                Text("\(number)").font(M.Font.heading).foregroundStyle(.white)
            }
        case .locked:
            Image(systemName: symbol ?? "lock.fill").font(M.Font.section).foregroundStyle(M.Colors.muted)
        }
    }

    private func fill(_ state: NodeState) -> Color {
        switch state {
        case .correct: .statusSafe
        case .tried: M.Colors.muted
        case .current: .accentColor
        case .locked: M.Colors.ink.opacity(0.08)
        }
    }

    private func stateText(_ state: NodeState) -> String {
        switch state {
        case .locked: String(localized: "Locked")
        case .current: String(localized: "Up next")
        case .correct: String(localized: "Done: correct")
        case .tried: String(localized: "Done")
        }
    }

    // MARK: Button

    @ViewBuilder
    private var primaryButton: some View {
        if let index = run.currentStopIndex {
            bigButton(String(localized: "Start stop \(index + 1): \(run.stops[index].name)")) { onPlayStop(index) }
        } else if !run.isFinished {
            bigButton(String(localized: "Go to the last stop")) { onPlayScore() }
        } else {
            bigButton(String(localized: "See your results")) { onFinish() }
        }
    }

    private func bigButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(M.Font.section)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}
