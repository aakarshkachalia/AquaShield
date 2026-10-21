//
//  RiskCheckView.swift
//  ClearWellNC
//
//  "Should I test?" One question per screen with progress dots, then recommendations.
//

import SwiftUI

struct RiskCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings

    @State private var answers = RiskCheckAnswers()
    @State private var step = 0
    @State private var countyData = CountyWellData.loadBundled()
    @State private var trends = CountyTrendData.loadBundled()

    private let questionCount = 7

    var body: some View {
        NavigationStack {
            Group {
                if step < questionCount {
                    question
                } else {
                    results
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Should I test?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if step > 0 {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            go(to: step - 1)
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
            }
        }
        .onAppear {
            answers = settings.riskAnswers ?? RiskCheckAnswers()
            answers.county = answers.county ?? settings.county
        }
    }

    // MARK: Questions

    private var question: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                ProgressDots(current: step, total: questionCount)
                switch step {
                case 0: countyQuestion
                case 1: choice("Was your well drilled before 2008?", hint: "Look for a well permit or ask the previous owner.",
                               options: [("Yes", RiskCheckAnswers.WellAge.before2008), ("No, 2008 or later", .after2008),
                                         ("I don't know", .unknown)], selected: answers.wellAge) { answers.wellAge = $0 }
                case 2: yesNo("Is anyone pregnant, or is there a baby under 1 year old in your home?",
                              selected: answers.pregnantOrInfant) { answers.pregnantOrInfant = $0 }
                case 3: yesNo("Has flooding or a hurricane affected your well?",
                              hint: "For example, water covered the wellhead or the area flooded.",
                              selected: answers.flooding) { answers.flooding = $0 }
                case 4: yesNo("Are farm fields, livestock or a septic system near your well?",
                              selected: answers.nearbySources) { answers.nearbySources = $0 }
                case 5: choice("When was your well last tested?", hint: nil,
                               options: [("Never", RiskCheckAnswers.LastTest.never), ("1–3 years ago", .oneToThreeYears),
                                         ("More than 3 years ago", .threePlusYears)],
                               selected: answers.lastTest) { answers.lastTest = $0 }
                default: yesNo("Have you noticed changes in taste, smell, color or staining?",
                               selected: answers.noticedChanges) { answers.noticedChanges = $0 }
                }
            }
            .screenContainer()
        }
    }

    private var countyQuestion: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            questionTitle("Which county is your well in?", hint: "County data helps us spot local risks.")
            Picker("County", selection: $answers.county) {
                Text("Not sure").tag(String?.none)
                ForEach(CountyNames.all, id: \.self) { Text(String(localized: "\($0) County")).tag(Optional($0)) }
            }
            .pickerStyle(.wheel)
            .card()
            PrimaryButton(title: "Next") { go(to: 1) }
        }
    }

    private func questionTitle(_ title: LocalizedStringKey, hint: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(title)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let hint {
                Text(hint).font(.subheadline).foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func yesNo(_ title: LocalizedStringKey, hint: LocalizedStringKey? = nil, selected: Bool?,
                       set: @escaping (Bool) -> Void) -> some View {
        choice(title, hint: hint, options: [("Yes", true), ("No", false)], selected: selected, set: set)
    }

    private func choice<T: Equatable>(_ title: LocalizedStringKey, hint: LocalizedStringKey?,
                                      options: [(LocalizedStringKey, T)], selected: T?,
                                      set: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            questionTitle(title, hint: hint)
            ForEach(options.indices, id: \.self) { i in
                let isSelected = selected == options[i].1
                Button {
                    set(options[i].1)
                    go(to: step + 1)
                } label: {
                    HStack {
                        Text(options[i].0).font(.headline)
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(Color.brandPrimary)
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(Color.textPrimary)
                    .frame(minHeight: 52)
                    .padding(.horizontal, Spacing.l)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(isSelected ? Color.brandPrimary : Color.cardBorder, lineWidth: isSelected ? 2 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    // MARK: Results

    private var results: some View {
        let result = RiskCheckEngine.recommend(answers: answers, countyData: countyData, trends: trends,
                                               pfasCounties: HelpLibrary.pfasTestingCounties)
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                InfoCard(style: .status(.watch), systemImage: "testtube.2",
                         title: String(localized: "Your recommended tests"),
                         message: RiskCheckResult.disclaimer) {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        ForEach(result.tests) { test in
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Label(test.id.name, systemImage: "checkmark.square")
                                    .font(.headline)
                                Text(test.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(Color.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                PrimaryButton(title: "Get tested", systemImage: "arrow.right.circle.fill") {
                    dismiss()
                    router.openHelp(.testing)
                }

                if !result.countyFacts.isEmpty, let county = answers.county {
                    VStack(alignment: .leading, spacing: Spacing.m) {
                        HStack {
                            Text("\(county) County facts").font(.headline).accessibilityAddTraits(.isHeader)
                            Spacer()
                            if result.countyFacts.contains(where: \.isSample) { SampleDataTag() }
                        }
                        ForEach(result.countyFacts) { fact in
                            Text(fact.text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Counties average many wells. Yours can be very different.")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .card()
                }

                InfoCard(systemImage: "calendar", title: String(localized: "Best time of year to test"),
                         message: result.bestTimeToTest) {
                    if trends?.isSample == true { SampleDataTag() }
                }

                if answers.flooding == true {
                    SecondaryButton(title: "My well flooded: what to do", systemImage: "cloud.heavyrain.fill") {
                        dismiss()
                        router.openHelp(.emergency)
                    }
                }

                SecondaryButton(title: "Start over", systemImage: "arrow.counterclockwise") {
                    answers = RiskCheckAnswers(county: answers.county)
                    go(to: 0)
                }

                DisclaimerFooter(lead: RiskCheckResult.disclaimer)
            }
            .screenContainer()
        }
        .onAppear { save() }
    }

    // MARK: Helpers

    private func go(to next: Int) {
        if next >= questionCount { save() }
        if reduceMotion { step = next } else { withAnimation(.easeInOut(duration: 0.2)) { step = next } }
    }

    private func save() {
        settings.riskAnswers = answers
        if settings.county == nil, let county = answers.county { settings.county = county }
    }
}

/// "Question 2 of 7" dots. The text is read by VoiceOver.
struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: Spacing.s) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i <= current ? Color.brandPrimary : Color.textPrimary.opacity(0.15))
                    .frame(width: 10, height: 10)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Question \(current + 1) of \(total)"))
    }
}
