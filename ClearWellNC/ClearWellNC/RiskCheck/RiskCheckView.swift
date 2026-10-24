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
                .background(DS.Colors.background)
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
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    question(step)
                    PrivacyNote()
                }
                .dsScreen()
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
                   options: [(String(localized: "Yes"), "checkmark", RiskCheckAnswers.WellAge.before2008),
                             (String(localized: "No, 2008 or later"), "xmark", .after2008),
                             (String(localized: "I don't know"), "questionmark", .unknown)],
                   selected: draft.answers.wellAge) { draft.answers.wellAge = $0 }
        case .pregnancy:
            yesNo(step, "Is anyone pregnant, or is there a baby under 1 in your home?",
                  selected: draft.answers.pregnantOrInfant) { draft.answers.pregnantOrInfant = $0 }
        case .flooding:
            yesNo(step, "Has a flood or hurricane reached your well?",
                  hint: "For example, water covered the top of the well.",
                  selected: draft.answers.flooding) { draft.answers.flooding = $0 }
        case .nearbySources:
            yesNo(step, "Are farm fields, animals or a septic system near your well?",
                  selected: draft.answers.nearbySources) { draft.answers.nearbySources = $0 }
        case .lastTest:
            choice(step, "When was your well last tested?", hint: nil,
                   options: [(String(localized: "Never"), "calendar.badge.exclamationmark", RiskCheckAnswers.LastTest.never),
                             (String(localized: "1–3 years ago"), "calendar", .oneToThreeYears),
                             (String(localized: "More than 3 years ago"), "calendar.badge.clock", .threePlusYears)],
                   selected: draft.answers.lastTest) { draft.answers.lastTest = $0 }
        case .noticedChanges:
            yesNo(step, "Has the taste, smell or color changed, or is there staining?",
                  selected: draft.answers.noticedChanges) { draft.answers.noticedChanges = $0 }
        case .results:
            EmptyView()
        }
    }

    private var countyQuestion: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            questionTitle("Which county is your well in?", hint: "This helps us spot local risks.")
            CountyPicker(selection: $draft.answers.county, noneLabel: String(localized: "Not sure"))
        }
    }

    private func questionTitle(_ title: LocalizedStringKey, hint: LocalizedStringKey?) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title)
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let hint {
                Text(hint)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, DS.Space.s)
    }

    private func yesNo(_ step: RiskCheckStep, _ title: LocalizedStringKey, hint: LocalizedStringKey? = nil,
                       selected: Bool?, set: @escaping (Bool) -> Void) -> some View {
        choice(step, title, hint: hint,
               options: [(String(localized: "Yes"), "checkmark", true), (String(localized: "No"), "xmark", false)],
               selected: selected, set: set)
    }

    /// Tapping an answer saves it and moves to the next question.
    private func choice<T: Equatable>(_ step: RiskCheckStep, _ title: LocalizedStringKey, hint: LocalizedStringKey?,
                                      options: [(title: String, icon: String, value: T)], selected: T?,
                                      set: @escaping (T) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            questionTitle(title, hint: hint)
            ForEach(options.indices, id: \.self) { i in
                DS.ChoiceCard(title: options[i].title, systemImage: options[i].icon,
                              isSelected: selected == options[i].value) {
                    set(options[i].value)
                    draft.flow.advance(in: order)
                }
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
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    DS.IconBadge(systemImage: DS.Icon.test)
                    Text("Test your well for these \(result.tests.count)")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(RiskCheckResult.disclaimer)
                        .font(DS.Typography.body)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                VStack(spacing: DS.Space.m) {
                    ForEach(result.tests) { test in
                        DS.InfoCard(systemImage: DS.Icon.recommendedTest(test.id), title: test.id.name,
                                    learnMore: test.reason.isEmpty ? nil : test.reason)
                    }
                }
                Button {
                    dismiss()
                    router.openHelp(.testing)
                } label: {
                    Label("Get tested", systemImage: "arrow.right.circle.fill")
                }
                .buttonStyle(DS.PrimaryButtonStyle())
                DS.ActionCard(systemImage: "person.2.fill", title: String(localized: "Add your household"),
                              subtitle: String(localized: "See risks for each person who drinks this water")) {
                    dismiss()
                    router.selectedTab = .home
                    router.showingHousehold = true
                }
                if draft.answers.flooding == true {
                    DS.ActionCard(systemImage: DS.Icon.alert(.flood), title: String(localized: "My well flooded"),
                                  subtitle: String(localized: "What to do first")) {
                        dismiss()
                        router.openHelp(.emergency)
                    }
                }
                if !result.countyFacts.isEmpty, let county = draft.answers.county {
                    VStack(alignment: .leading, spacing: DS.Space.m) {
                        HStack {
                            Label(String(localized: "\(county) County"), systemImage: "map.fill")
                                .font(DS.Typography.headline)
                                .foregroundStyle(DS.Colors.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            if result.countyFacts.contains(where: \.isSample) { SampleDataTag() }
                        }
                        ForEach(result.countyFacts) { fact in
                            Text(fact.text)
                                .font(DS.Typography.subheadline)
                                .foregroundStyle(DS.Colors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("Your well can be very different from the county average.")
                            .font(DS.Typography.footnote)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    .dsCard()
                }
                DS.InfoCard(systemImage: "calendar", title: String(localized: "Best time to test"),
                            message: result.bestTimeToTest)
                if trends?.isSample == true { SampleDataTag() }
                HStack {
                    Button("Start over", systemImage: "arrow.counterclockwise") { startOver() }
                    Spacer()
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.accent)
                .frame(minHeight: DS.Size.tapTarget)
                DisclaimerFooter()
            }
            .dsScreen()
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
