//
//  StepFlowContainer.swift
//  AquaShield
//
//  The shell every multi-step flow uses: a NavigationStack over the flow's step path (system Back button
//  and swipe-back), a progress indicator, an optional Next/Save bar, Close, and the "Continue / Start over"
//  prompt for a saved draft. How those pieces look comes from the StepFlowStyle in the environment, so the
//  design system can restyle them without touching the flows.
//

import SwiftUI

/// The bottom-bar action for a step (Next, Save…).
struct StepAction {
    let title: LocalizedStringKey
    var systemImage: String?
    var isEnabled = true
    var identifier = "flow.next"
    let action: () -> Void
}

/// A saved draft the user can continue or throw away.
struct StepFlowResume {
    let startedAt: Date
    let onContinue: () -> Void
    let onStartOver: () -> Void
}

struct StepFlowContainer<Step: Hashable & Codable & Sendable, Page: View>: View {
    @Binding var flow: StepFlow<Step>
    /// Non-nil shows the Continue / Start over prompt instead of the steps.
    var resume: StepFlowResume?
    var progress: (Step) -> StepProgress? = { _ in nil }
    var primaryAction: (Step) -> StepAction? = { _ in nil }
    /// Nil hides Close (onboarding). Closing keeps the draft.
    var onClose: (() -> Void)?
    @ViewBuilder var page: (Step) -> Page

    @Environment(\.stepFlowStyle) private var style

    var body: some View {
        if let resume {
            NavigationStack {
                style.resumePrompt(StepFlowResumeConfiguration(
                    startedText: DraftAge.startedText(resume.startedAt),
                    onContinue: resume.onContinue,
                    onStartOver: resume.onStartOver))
                    .toolbar { closeItem }
            }
        } else {
            NavigationStack(path: $flow.path) {
                decorated(flow.root)
                    .navigationDestination(for: Step.self) { decorated($0) }
            }
        }
    }

    private func decorated(_ step: Step) -> some View {
        page(step)
            .safeAreaInset(edge: .top, spacing: 0) {
                if let progress = progress(step) {
                    style.progress(StepFlowProgressConfiguration(progress: progress))
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let action = primaryAction(step) {
                    style.actionBar(StepFlowActionConfiguration(action: action))
                }
            }
            // Back shows as a plain chevron labeled "Back", whatever the previous step's title.
            .toolbarRole(.editor)
            .toolbar { closeItem }
    }

    @ToolbarContentBuilder
    private var closeItem: some ToolbarContent {
        if let onClose {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark", action: onClose)
                    .accessibilityIdentifier("flow.close")
                    .accessibilityHint(Text("Your answers are kept"))
            }
        }
    }
}

// MARK: - Style

struct StepFlowProgressConfiguration {
    let progress: StepProgress
}

struct StepFlowActionConfiguration {
    let action: StepAction
}

struct StepFlowResumeConfiguration {
    /// "Started 2 days ago".
    let startedText: String
    let onContinue: () -> Void
    let onStartOver: () -> Void
}

/// How a step flow's shared pieces look. Swap with `.stepFlowStyle(_:)`.
protocol StepFlowStyle: Sendable {
    associatedtype ProgressBody: View
    associatedtype ActionBarBody: View
    associatedtype ResumePromptBody: View

    @MainActor @ViewBuilder func makeProgress(_ configuration: StepFlowProgressConfiguration) -> ProgressBody
    @MainActor @ViewBuilder func makeActionBar(_ configuration: StepFlowActionConfiguration) -> ActionBarBody
    @MainActor @ViewBuilder func makeResumePrompt(_ configuration: StepFlowResumeConfiguration) -> ResumePromptBody
}

/// Type-erased style for the environment.
nonisolated struct AnyStepFlowStyle: Sendable {
    private let makeProgress: @MainActor @Sendable (StepFlowProgressConfiguration) -> AnyView
    private let makeActionBar: @MainActor @Sendable (StepFlowActionConfiguration) -> AnyView
    private let makeResumePrompt: @MainActor @Sendable (StepFlowResumeConfiguration) -> AnyView

    init<S: StepFlowStyle>(_ style: S) {
        makeProgress = { AnyView(style.makeProgress($0)) }
        makeActionBar = { AnyView(style.makeActionBar($0)) }
        makeResumePrompt = { AnyView(style.makeResumePrompt($0)) }
    }

    @MainActor func progress(_ configuration: StepFlowProgressConfiguration) -> AnyView { makeProgress(configuration) }
    @MainActor func actionBar(_ configuration: StepFlowActionConfiguration) -> AnyView { makeActionBar(configuration) }
    @MainActor func resumePrompt(_ configuration: StepFlowResumeConfiguration) -> AnyView { makeResumePrompt(configuration) }
}

extension EnvironmentValues {
    @Entry var stepFlowStyle = AnyStepFlowStyle(DefaultStepFlowStyle())
}

extension View {
    func stepFlowStyle<S: StepFlowStyle>(_ style: S) -> some View {
        environment(\.stepFlowStyle, AnyStepFlowStyle(style))
    }
}

/// Behavior-first default. The design system pass restyles this.
nonisolated struct DefaultStepFlowStyle: StepFlowStyle {
    @MainActor func makeProgress(_ configuration: StepFlowProgressConfiguration) -> some View {
        StepProgressBar(progress: configuration.progress)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.s)
            .readableWidth()
            .background(Color.appBackground)
    }

    @MainActor func makeActionBar(_ configuration: StepFlowActionConfiguration) -> some View {
        let action = configuration.action
        PrimaryButton(title: action.title, systemImage: action.systemImage, action: action.action)
            .disabled(!action.isEnabled)
            .accessibilityIdentifier(action.identifier)
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.m)
            .readableWidth()
            .background(M.Colors.tabBar)
    }

    @MainActor func makeResumePrompt(_ configuration: StepFlowResumeConfiguration) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                InfoCard(systemImage: "arrow.uturn.forward.circle.fill",
                         title: String(localized: "Pick up where you left off?"),
                         message: configuration.startedText)
                PrimaryButton(title: "Continue", systemImage: "arrow.right", action: configuration.onContinue)
                    .accessibilityIdentifier("flow.continue")
                SecondaryButton(title: "Start over", systemImage: "arrow.counterclockwise", action: configuration.onStartOver)
                    .accessibilityIdentifier("flow.startOver")
            }
            .screenContainer()
        }
        .background(Color.appBackground)
    }
}

/// Thin bar plus "Step 2 of 7". Also used inline (Learn quizzes).
struct StepProgressBar: View {
    let progress: StepProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            ProgressView(value: progress.fraction)
                .tint(Color.brandPrimary)
            Text(progress.text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(progress.text))
        .accessibilityIdentifier("flow.progress")
    }
}

#Preview("Resume prompt") {
    StepFlowContainer(flow: .constant(StepFlow(root: 0)),
                      resume: StepFlowResume(startedAt: .now.addingTimeInterval(-2 * 86_400),
                                             onContinue: {}, onStartOver: {}),
                      onClose: {}) { _ in EmptyView() }
}

#Preview("Step") {
    StepFlowContainer(flow: .constant(StepFlow(root: 1)),
                      progress: { StepProgress(position: $0, total: 4) },
                      primaryAction: { _ in StepAction(title: "Next", action: {}) },
                      onClose: {}) { step in
        Text("Step \(step)").navigationTitle("Preview")
    }
}
