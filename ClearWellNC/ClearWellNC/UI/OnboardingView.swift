//
//  OnboardingView.swift
//  ClearWellNC
//

import SwiftUI

/// UserDefaults keys for small on-device preferences.
enum StorageKey {
    static let hasOnboarded = "hasOnboarded"
    static let waterSource = "waterSource"
    static let infantInHome = "infantInHome"
}

enum WaterSource: String, CaseIterable, Identifiable {
    case privateWell
    case publicWater
    case notSure

    var id: String { rawValue }

    var label: LocalizedStringKey {
        switch self {
        case .privateWell: "Yes"
        case .publicWater: "No, city or county water"
        case .notSure: "Not sure"
        }
    }
}

struct OnboardingView: View {
    @AppStorage(StorageKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(StorageKey.waterSource) private var storedSource = ""
    @AppStorage(StorageKey.infantInHome) private var infantInHome = false
    @State private var answer: WaterSource?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    Image(systemName: "drop.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    Text("ClearWell NC")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Understand your area's well-water risk, decide what to test for, and keep track of your results.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: Spacing.m) {
                    Text("Does your home get water from a private well?")
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    ForEach(WaterSource.allCases) { source in
                        choiceButton(source)
                    }
                }

                if let answer {
                    explanation(for: answer)
                    infantToggle
                    Button {
                        storedSource = answer.rawValue
                        hasOnboarded = true
                    } label: {
                        Text(answer == .publicWater ? "Explore anyway" : "Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(Spacing.xl)
            .readableWidth()
            .animation(.default, value: answer)
        }
        .background(Color.appBackground)
    }

    private func choiceButton(_ source: WaterSource) -> some View {
        let selected = answer == source
        return Button {
            answer = source
        } label: {
            HStack {
                Text(source.label)
                    .font(.body.weight(.medium))
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
            .padding(Spacing.l)
            .frame(minHeight: 44)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func explanation(for answer: WaterSource) -> some View {
        switch answer {
        case .privateWell:
            EmptyView()
        case .publicWater:
            infoCard(
                title: "You're probably on public water",
                text: "Public water systems publish a yearly Consumer Confidence Report that shows what is in your water. Ask your water provider for a copy. You can still explore well-water risk in North Carolina.")
        case .notSure:
            infoCard(
                title: "How to tell",
                text: "If you get a water bill, you are probably not on a well. If you have a well pump or pressure tank and no water bill, you probably have a well.")
        }
    }

    private func infoCard(title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label(title, systemImage: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(.tint)
            Text(text)
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private var infantToggle: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Toggle("A baby under 6 months lives here", isOn: $infantInHome)
                .frame(minHeight: 44)
            Text("Optional. This is stored only on this device and adds a nitrate note to your report.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .card()
    }
}

#Preview {
    OnboardingView()
}
