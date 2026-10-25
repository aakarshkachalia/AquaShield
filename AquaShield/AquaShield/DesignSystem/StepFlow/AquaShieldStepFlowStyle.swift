//
//  AquaShieldStepFlowStyle.swift
//  AquaShield
//
//  The design system's look for step flows: a rounded progress bar with "Question 2 of 7", a large Next
//  button on a floating bar, and a centered resume prompt. Back stays the system chevron that
//  StepFlowContainer adds. Turn it on with `.stepFlowStyle(AquaShieldStepFlowStyle())`.
//

import SwiftUI

nonisolated struct AquaShieldStepFlowStyle: StepFlowStyle {
    @MainActor func makeProgress(_ configuration: StepFlowProgressConfiguration) -> some View {
        DSStepProgress(progress: configuration.progress)
            .padding(.horizontal, DS.Space.l)
            .padding(.top, DS.Space.xs)
            .padding(.bottom, DS.Space.m)
            .frame(maxWidth: DS.Size.readableWidth)
            .frame(maxWidth: .infinity)
            .background(DS.Colors.background)
    }

    @MainActor func makeActionBar(_ configuration: StepFlowActionConfiguration) -> some View {
        let action = configuration.action
        Button(action: action.action) {
            if let systemImage = action.systemImage {
                // Arrow after the word reads as "forward".
                HStack(spacing: DS.Space.s) {
                    Text(action.title)
                    Image(systemName: systemImage)
                }
            } else {
                Text(action.title)
            }
        }
        .buttonStyle(DS.PrimaryButtonStyle())
        .disabled(!action.isEnabled)
        .accessibilityIdentifier(action.identifier)
        .padding(.horizontal, DS.Space.l)
        .padding(.top, DS.Space.m)
        .padding(.bottom, DS.Space.s)
        .frame(maxWidth: DS.Size.readableWidth)
        .frame(maxWidth: .infinity)
        .background(M.Colors.tabBar)
        .overlay(alignment: .top) { Divider().opacity(0.6) }
    }

    @MainActor func makeResumePrompt(_ configuration: StepFlowResumeConfiguration) -> some View {
        ScrollView {
            VStack(spacing: DS.Space.xl) {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(.largeTitle, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: 96, height: 96)
                    .background(DS.Colors.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                VStack(spacing: DS.Space.s) {
                    Text("Pick up where you left off?")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(configuration.startedText)
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
                .multilineTextAlignment(.center)
                VStack(spacing: DS.Space.m) {
                    Button(action: configuration.onContinue) { Text("Continue") }
                        .buttonStyle(DS.PrimaryButtonStyle())
                        .accessibilityIdentifier("flow.continue")
                    Button(action: configuration.onStartOver) { Text("Start over") }
                        .buttonStyle(DS.SecondaryButtonStyle())
                        .accessibilityIdentifier("flow.startOver")
                }
            }
            .padding(.top, DS.Space.xxxl)
            .dsScreen()
        }
        .background(DS.Colors.background)
    }
}

/// Rounded bar that fills as the user moves forward, plus "Question 2 of 7".
struct DSStepProgress: View {
    let progress: StepProgress

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.Colors.track)
                    Capsule()
                        .fill(LinearGradient(colors: [DS.Colors.water, DS.Colors.accent],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * progress.fraction, 8))
                }
            }
            .frame(height: 8)
            .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: progress.fraction)
            Text(progress.text)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(progress.text))
        .accessibilityIdentifier("flow.progress")
    }
}

private struct StepFlowStyleSample: View {
    @State private var flow = StepFlow(root: 1)

    var body: some View {
        StepFlowContainer(flow: $flow,
                          progress: { StepProgress(position: $0, total: 4, label: String(localized: "Question \($0) of 4")) },
                          primaryAction: { step in
                              StepAction(title: step < 4 ? "Next" : "Done", systemImage: "arrow.right") {
                                  flow.advance(in: [1, 2, 3, 4])
                              }
                          },
                          onClose: {}) { step in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    Text("Was your well drilled before 2008?")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.textPrimary)
                    DS.ChoiceCard(title: "Yes", systemImage: "checkmark", isSelected: step % 2 == 0) {}
                    DS.ChoiceCard(title: "No", systemImage: "xmark", isSelected: false) {}
                    DS.ChoiceCard(title: "I don't know", systemImage: "questionmark", isSelected: false) {}
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .stepFlowStyle(AquaShieldStepFlowStyle())
    }
}

private struct ResumeSample: View {
    var body: some View {
        StepFlowContainer(flow: .constant(StepFlow(root: 0)),
                          resume: StepFlowResume(startedAt: .now.addingTimeInterval(-2 * 86_400),
                                                 onContinue: {}, onStartOver: {}),
                          onClose: {}) { _ in EmptyView() }
            .stepFlowStyle(AquaShieldStepFlowStyle())
    }
}

#Preview("Step · Light") { StepFlowStyleSample().preferredColorScheme(.light) }
#Preview("Step · Dark") { StepFlowStyleSample().preferredColorScheme(.dark) }
#Preview("Step · Largest text") { StepFlowStyleSample().environment(\.dynamicTypeSize, .accessibility5) }
#Preview("Resume · Light") { ResumeSample().preferredColorScheme(.light) }
#Preview("Resume · Dark") { ResumeSample().preferredColorScheme(.dark) }
#Preview("Resume · Largest text") { ResumeSample().environment(\.dynamicTypeSize, .accessibility5) }
