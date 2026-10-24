//
//  OnboardingView.swift
//  ClearWellNC
//
//  First launch only, skippable: what ClearWell does → where your water comes from → pick your county → "Do you have a lab report?"
//  Steps with Back and progress; the current step is saved so a force-quit resumes there.
//

import SwiftUI

nonisolated enum OnboardingStep: String, Codable, Hashable, Sendable, CaseIterable {
    case welcome, waterSource, county, report
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
        case .waterSource: waterSourcePage
        case .county: countyPage
        case .report: reportPage
        }
    }

    private func primaryAction(_ step: OnboardingStep) -> StepAction? {
        switch step {
        case .welcome, .waterSource:
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
            VStack(spacing: DS.Space.l) {
                Image(systemName: "drop.fill")
                    .font(.system(.largeTitle, weight: .semibold))
                    .imageScale(.large)
                    .foregroundStyle(DS.Colors.onAccent)
                    .frame(width: 112, height: 112)
                    .background(LinearGradient(colors: [DS.Colors.water, DS.Colors.accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: Circle())
                    .accessibilityHidden(true)
                Text("ClearWell NC")
                    .font(DS.Typography.display)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("Know what's in your water, and what to do about it.")
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.l)
            VStack(spacing: DS.Space.m) {
                feature(DS.Icon.riskCheck, "Find out what to test for")
                feature(DS.Icon.scan, "Understand every number on your report")
                feature("dollarsign.circle.fill", "Find free testing and help paying for fixes")
            }
        }
    }

    private var waterSourcePage: some View {
        content {
            pageTitle("Where does your water come from?",
                      subtitle: "Do you get a water bill? Is there a well head or pressure tank?")
            VStack(spacing: DS.Space.m) {
                ForEach(WaterSource.allCases) { source in
                    DS.ChoiceCard(title: source.choiceTitle, subtitle: source.choiceHint, systemImage: source.symbol,
                                  isSelected: settings.waterSource == source) {
                        settings.waterSource = source
                    }
                    .accessibilityIdentifier("onboarding.waterSource.\(source.rawValue)")
                }
            }
        }
    }

    private var countyPage: some View {
        @Bindable var settings = settings
        return content {
            pageTitle("Which county do you live in?",
                      subtitle: "We use it for local facts and help programs. It stays on this phone.")
            // Saved as soon as it changes.
            CountyPicker(selection: $settings.county, noneLabel: String(localized: "Choose later"))
        }
    }

    private var reportPage: some View {
        content {
            pageTitle("Do you have a lab report?",
                      subtitle: "We'll explain it. If not, we'll help you decide what to test.")
            VStack(spacing: DS.Space.m) {
                DS.ActionCard(systemImage: DS.Icon.scan, title: String(localized: "Yes, scan my report"),
                              subtitle: String(localized: "Takes about a minute"), style: .prominent) {
                    finish()
                    router.showingScanner = true
                }
                DS.ActionCard(systemImage: DS.Icon.riskCheck, title: String(localized: "Not yet, help me decide"),
                              subtitle: String(localized: "7 quick questions")) {
                    finish()
                    router.showingRiskCheck = true
                }
            }
        }
    }

    // MARK: Helpers

    private func content<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xl) {
                content()
            }
            .dsScreen()
        }
        .background(DS.Colors.background)
    }

    private func pageTitle(_ title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title)
                .font(DS.Typography.title)
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(DS.Typography.body)
                .foregroundStyle(DS.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func feature(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: DS.Space.m) {
            DS.IconBadge(systemImage: symbol)
            Text(text)
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .dsCard(padding: DS.Space.m)
        .accessibilityElement(children: .combine)
    }

    private func finish() {
        settings.drafts.discard(OnboardingDraft.key)
        hasOnboarded = true
    }
}
