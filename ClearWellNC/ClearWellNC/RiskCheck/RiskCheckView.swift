//
//  RiskCheckView.swift
//  ClearWellNC
//
//  "Should I test?" One question per step (Back, progress, saved after every answer), then recommendations.
//

import SwiftUI

struct RiskCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings

    @State private var draft = RiskCheckDraft()
    /// The draft as it was when opened; nothing is saved until the user changes something.
    @State private var pristine = RiskCheckDraft()
    @State private var resume: StepFlowResume?
    @State private var loaded = false
    @State private var countyData = CountyWellData.loadBundled()
    @State private var trends = CountyTrendData.loadBundled()

    private let order = RiskCheckStep.allCases

    var body: some View {
        StepFlowContainer(flow: $draft.flow, resume: resume,
                          progress: progress, primaryAction: primaryAction,
                          onClose: { dismiss() }) { step in
            page(step)
                .background(Color.appBackground)
                .navigationTitle("Should I test?")
                .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: load)
        .onChange(of: draft) { _, newValue in persist(newValue) }
    }

    @ViewBuilder
    private func page(_ step: RiskCheckStep) -> some View {
        if step == .results {
            results
        } else {
            ScrollView {
                question(step)
                    .screenContainer()
            }
        }
    }

    // MARK: Questions

    @ViewBuilder
    private func question(_ step: RiskCheckStep) -> some View {
        switch step {
        case .county: countyQuestion
        case .wellAge:
            choice(step, "Was your well drilled before 2008?", hint: "Look for a well permit or ask the previous owner.",
                   options: [("Yes", RiskCheckAnswers.WellAge.before2008), ("No, 2008 or later", .after2008),
                             ("I don't know", .unknown)], selected: draft.answers.wellAge) { draft.answers.wellAge = $0 }
        case .pregnancy:
            yesNo(step, "Is anyone pregnant, or is there a baby under 1 year old in your home?",
                  selected: draft.answers.pregnantOrInfant) { draft.answers.pregnantOrInfant = $0 }
        case .flooding:
            yesNo(step, "Has flooding or a hurricane affected your well?",
                  hint: "For example, water covered the wellhead or the area flooded.",
                  selected: draft.answers.flooding) { draft.answers.flooding = $0 }
        case .nearbySources:
            yesNo(step, "Are farm fields, livestock or a septic system near your well?",
                  selected: draft.answers.nearbySources) { draft.answers.nearbySources = $0 }
        case .lastTest:
            choice(step, "When was your well last tested?", hint: nil,
                   options: [("Never", RiskCheckAnswers.LastTest.never), ("1–3 years ago", .oneToThreeYears),
                             ("More than 3 years ago", .threePlusYears)],
                   selected: draft.answers.lastTest) { draft.answers.lastTest = $0 }
        case .noticedChanges:
            yesNo(step, "Have you noticed changes in taste, smell, color or staining?",
                  selected: draft.answers.noticedChanges) { draft.answers.noticedChanges = $0 }
        case .results:
            EmptyView()
        }
    }

    private var countyQuestion: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            questionTitle("Which county is your well in?", hint: "County data helps us spot local risks.")
            Picker("County", selection: $draft.answers.county) {
                Text("Not sure").tag(String?.none)
                ForEach(CountyNames.all, id: \.self) { Text(String(localized: "\($0) County")).tag(Optional($0)) }
            }
            .pickerStyle(.wheel)
            .card()
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

    private func yesNo(_ step: RiskCheckStep, _ title: LocalizedStringKey, hint: LocalizedStringKey? = nil,
                       selected: Bool?, set: @escaping (Bool) -> Void) -> some View {
        choice(step, title, hint: hint, options: [("Yes", true), ("No", false)], selected: selected, set: set)
    }

    private func choice<T: Equatable>(_ step: RiskCheckStep, _ title: LocalizedStringKey, hint: LocalizedStringKey?,
                                      options: [(LocalizedStringKey, T)], selected: T?,
                                      set: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            questionTitle(title, hint: hint)
            ForEach(options.indices, id: \.self) { i in
                let isSelected = selected == options[i].1
                Button {
                    set(options[i].1)
                    draft.flow.advance(in: order)
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
                .accessibilityIdentifier("riskCheck.\(step.rawValue).\(i)")
            }
        }
    }

    private func progress(_ step: RiskCheckStep) -> StepProgress? {
        guard step != .results, let index = RiskCheckStep.questions.firstIndex(of: step) else { return nil }
        let total = RiskCheckStep.questions.count
        return StepProgress(position: index + 1, total: total,
                            label: String(localized: "Question \(index + 1) of \(total)"))
    }

    /// Next on the county question, and on any question already answered (after going Back).
    private func primaryAction(_ step: RiskCheckStep) -> StepAction? {
        guard step != .results, draft.isAnswered(step) else { return nil }
        return StepAction(title: "Next", systemImage: "arrow.right") { draft.flow.advance(in: order) }
    }

    // MARK: Results

    private var results: some View {
        let result = RiskCheckEngine.recommend(answers: draft.answers, countyData: countyData, trends: trends,
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

                if !result.countyFacts.isEmpty, let county = draft.answers.county {
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

                if draft.answers.flooding == true {
                    SecondaryButton(title: "My well flooded: what to do", systemImage: "cloud.heavyrain.fill") {
                        dismiss()
                        router.openHelp(.emergency)
                    }
                }

                SecondaryButton(title: "Start over", systemImage: "arrow.counterclockwise") {
                    startOver()
                }

                DisclaimerFooter(lead: RiskCheckResult.disclaimer)
            }
            .screenContainer()
        }
        .onAppear(perform: finish)
    }

    // MARK: Draft

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let saved = settings.drafts.load(RiskCheckDraft.key), saved.payload.isResumable {
            draft = saved.payload
            pristine = saved.payload
            resume = StepFlowResume(startedAt: saved.startedAt,
                                    onContinue: { resume = nil },
                                    onStartOver: { resume = nil; startOver() })
        } else {
            settings.drafts.discard(RiskCheckDraft.key)
            // Start from the last finished answers, so a repeat check only needs changes.
            var answers = settings.riskAnswers ?? RiskCheckAnswers()
            answers.county = answers.county ?? settings.county
            draft = RiskCheckDraft(answers: answers)
            pristine = draft
        }
    }

    /// Saves on every answer. Untouched and finished checks keep no draft.
    private func persist(_ value: RiskCheckDraft) {
        guard loaded, value != pristine, value.flow.current != .results else { return }
        settings.drafts.save(value, for: RiskCheckDraft.key)
    }

    /// Reaching the results saves the answers for Help Finder and Home, and ends the draft.
    private func finish() {
        settings.riskAnswers = draft.answers
        if settings.county == nil, let county = draft.answers.county { settings.county = county }
        settings.drafts.discard(RiskCheckDraft.key)
    }

    private func startOver() {
        settings.drafts.discard(RiskCheckDraft.key)
        draft = RiskCheckDraft(answers: RiskCheckAnswers(county: draft.answers.county ?? settings.county))
        pristine = draft
    }
}
