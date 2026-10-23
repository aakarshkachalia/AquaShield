//
//  OnboardingView.swift
//  ClearWellNC
//
//  First launch only, skippable: what ClearWell does → pick your county → "Do you have a lab report?"
//  Steps with Back and progress; the current step is saved so a force-quit resumes there.
//

import SwiftUI

nonisolated enum OnboardingStep: String, Codable, Hashable, Sendable, CaseIterable {
    case welcome, county, report
}

nonisolated struct OnboardingDraft: Codable, Sendable, Equatable {
    var flow = StepFlow(root: OnboardingStep.welcome)

    static let key = DraftKey<OnboardingDraft>(name: "onboarding", schemaVersion: 1)
}

struct OnboardingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @AppStorage(StorageKey.hasOnboarded) private var hasOnboarded = false

    @State private var draft = OnboardingDraft()
    @State private var resume: StepFlowResume?
    @State private var loaded = false

    private let order = OnboardingStep.allCases

    var body: some View {
        StepFlowContainer(flow: $draft.flow, resume: resume,
                          progress: { _ in draft.flow.progress(in: order) },
                          primaryAction: primaryAction) { step in
            page(for: step)
                .background(Color.appBackground)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Skip") { finish() }
                            .accessibilityIdentifier("onboarding.skip")
                            .accessibilityHint(Text("Skips the welcome screens"))
                    }
                }
        }
        .onAppear(perform: load)
        .onChange(of: draft) { _, newValue in
            // Saved on every step, so a force-quit resumes on the same screen.
            guard loaded else { return }
            if newValue.flow.canGoBack {
                settings.drafts.save(newValue, for: OnboardingDraft.key)
            } else {
                settings.drafts.discard(OnboardingDraft.key)
            }
        }
    }

    @ViewBuilder
    private func page(for step: OnboardingStep) -> some View {
        switch step {
        case .welcome: welcome
        case .county: countyPage
        case .report: reportPage
        }
    }

    private func primaryAction(_ step: OnboardingStep) -> StepAction? {
        switch step {
        case .welcome:
            StepAction(title: "Next", systemImage: "arrow.right") { draft.flow.advance(in: order) }
        case .county:
            StepAction(title: settings.county == nil ? "Skip for now" : "Next", systemImage: "arrow.right") {
                draft.flow.advance(in: order)
            }
        case .report:
            nil
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let saved = settings.drafts.load(OnboardingDraft.key), saved.payload.flow.isValid(in: order),
           saved.payload.flow.canGoBack {
            draft = saved.payload
            resume = StepFlowResume(startedAt: saved.startedAt,
                                    onContinue: { resume = nil },
                                    onStartOver: {
                                        resume = nil
                                        settings.drafts.discard(OnboardingDraft.key)
                                        draft = OnboardingDraft()
                                    })
        } else {
            settings.drafts.discard(OnboardingDraft.key)
        }
    }

    // MARK: Pages

    private var welcome: some View {
        content {
            Image(systemName: "drop.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text("ClearWell NC")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("From \"I've never tested my well\" to \"I know what's in it, what it means, and who will pay to fix it.\"")
                .font(.title2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Spacing.m) {
                bullet("checklist", "Find out if and what to test")
                bullet("doc.viewfinder", "Scan your lab report and understand every number")
                bullet("dollarsign.circle", "Find programs that test for free or help pay for fixes")
            }
            .card()
        }
    }

    private var countyPage: some View {
        @Bindable var settings = settings
        return content {
            Text("Which county do you live in?")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Well risks differ across North Carolina's 100 counties. We use this for local facts and help programs. It stays on this device.")
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            // Saved as soon as it changes.
            Picker("County", selection: $settings.county) {
                Text("Choose later").tag(String?.none)
                ForEach(CountyNames.all, id: \.self) { name in
                    Text(String(localized: "\(name) County")).tag(Optional(name))
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .card()
        }
    }

    private var reportPage: some View {
        content {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text("Do you have a lab report?")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("If your well has been tested, scan the report and we'll explain each result. If not, a quick Risk Check shows what to test for.")
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: Spacing.m) {
                PrimaryButton(title: "Yes, scan my report", systemImage: "doc.viewfinder") {
                    finish()
                    router.showingScanner = true
                }
                SecondaryButton(title: "Not yet, help me decide", systemImage: "checklist") {
                    finish()
                    router.showingRiskCheck = true
                }
            }
        }
    }

    // MARK: Helpers

    private func content<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                content()
            }
            .screenContainer()
        }
    }

    private func bullet(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.brandPrimary)
        }
        .font(.body)
    }

    private func finish() {
        settings.drafts.discard(OnboardingDraft.key)
        // ClearWell is built for private wells; city-water users can change this in Settings.
        if settings.waterSource == .notSure { settings.waterSource = .privateWell }
        hasOnboarded = true
    }
}
