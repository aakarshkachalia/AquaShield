//
//  QuestComponents.swift
//  ClearWellNC
//
//  Small shared pieces for Report Quest screens.
//

import SwiftData
import SwiftUI

extension QuestReport {
    /// The game's view of one saved lab result.
    init(result: LabResult) {
        self.init(date: result.date)
        for analyte in Analyte.allCases {
            if let value = result.value(for: analyte) { values[analyte.contaminant] = value }
        }
        if let coliform = result.totalColiform { presence[.totalColiform] = coliform == .present }
        if let eColi = result.eColi { presence[.eColi] = eColi == .present }
    }
}

/// What the badge rules need from the rest of the app: real test dates and the county's high seasons.
struct WellCareContext {
    let testDates: [Date]
    let highRiskMonths: Set<Int>
    let challenge: SeasonalChallenge?

    @MainActor
    static func make(results: [LabResult], county: String?, trends: CountyTrendData?) -> WellCareContext {
        guard let county, let trends else {
            return WellCareContext(testDates: results.map(\.date), highRiskMonths: [], challenge: nil)
        }
        return WellCareContext(testDates: results.map(\.date),
                               highRiskMonths: SeasonalChallengeRules.highRiskMonths(data: trends, county: county),
                               challenge: SeasonalChallengeRules.current(data: trends, county: county))
    }
}

/// Big, full-width game button: icon + text, at least 60 pt tall.
struct QuestChoiceButton: View {
    let title: String
    var detail: String?
    let systemImage: String
    var tint: Color = .accentColor
    var state: ChoiceState = .idle
    let action: () -> Void

    enum ChoiceState { case idle, chosenCorrect, chosenWrong, revealedCorrect, dimmed }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(M.Font.heading)
                        .foregroundStyle(.primary)
                    if let detail {
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(M.Colors.muted)
                    }
                }
                Spacer(minLength: 0)
                if let marker {
                    Image(systemName: marker.symbol)
                        .font(.title2)
                        .foregroundStyle(marker.color)
                        .accessibilityHidden(true)
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(border, lineWidth: 1.5))
            .opacity(state == .dimmed ? 0.55 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(accessibilityValue)
    }

    private var marker: (symbol: String, color: Color)? {
        switch state {
        case .chosenCorrect, .revealedCorrect: ("checkmark.circle.fill", .statusSafe)
        case .chosenWrong: ("xmark.circle.fill", M.Colors.muted)
        case .idle, .dimmed: nil
        }
    }

    private var background: Color {
        switch state {
        case .chosenCorrect, .revealedCorrect: Color.statusSafe.opacity(0.10)
        case .chosenWrong: M.Colors.ink.opacity(0.06)
        case .idle, .dimmed: Color.cardBackground
        }
    }

    private var border: Color {
        switch state {
        case .chosenCorrect, .revealedCorrect: Color.statusSafe.opacity(0.6)
        case .chosenWrong: M.Colors.ink.opacity(0.25)
        case .idle, .dimmed: Color.cardBorder
        }
    }

    private var accessibilityValue: Text {
        switch state {
        case .chosenCorrect: Text("Your answer, correct")
        case .chosenWrong: Text("Your answer, not correct")
        case .revealedCorrect: Text("Correct answer")
        case .idle, .dimmed: Text("")
        }
    }
}

/// A short sparkle when something goes well. With Reduce Motion it only fades.
struct SparkleBurst: View {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "star.fill")
                    .font(i.isMultiple(of: 2) ? .headline : .caption)
                    .foregroundStyle(i.isMultiple(of: 3) ? Color.statusWatch : Color.accentColor)
                    .offset(offset(i))
            }
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(reduceMotion ? 1 : (visible ? 1 : 0.4))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            withAnimation(reduceMotion ? .easeIn(duration: 0.2) : .spring(duration: 0.4)) { visible = true }
            withAnimation(.easeOut(duration: 0.5).delay(0.9)) { visible = false }
        }
    }

    private func offset(_ i: Int) -> CGSize {
        let angle = Double(i) / 6 * 2 * .pi
        let radius: Double = visible && !reduceMotion ? 36 : 22
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

/// Points chip for the top of the map and end screen.
struct PointsChip: View {
    let points: Int

    var body: some View {
        Label("\(points) points", systemImage: "star.fill")
            .font(M.Font.section)
            .monospacedDigit()
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
            .contentTransition(.numericText())
            .accessibilityLabel(Text("\(points) points"))
    }
}

/// Reading, limit and percent for one contaminant: the top of every stop.
struct ReadingSummary: View {
    let stop: QuestStop

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(stop.name)
                .font(M.Font.screenTitle)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                Text("Your reading:")
                    .foregroundStyle(M.Colors.muted)
                Text(stop.interpretation.readingText)
                    .font(M.Font.heading)
                    .monospacedDigit()
            }
            Label {
                Text(stop.interpretation.limitText)
            } icon: {
                Image(systemName: "ruler").foregroundStyle(M.Colors.muted)
            }
            .font(.subheadline)
        }
        .accessibilityElement(children: .combine)
    }
}
