//
//  DSCards.swift
//  AquaShield
//
//  Buttons and the four card types: InfoCard (read), ActionCard (do one thing), ChoiceCard (answer a
//  question) and EmptyStateView (nothing here yet, here's what to do).
//

import SwiftUI

// MARK: - Buttons

extension DS {
    /// The one filled button on a screen.
    struct PrimaryButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Colors.onAccent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: DS.Size.largeTapTarget)
                .padding(.horizontal, DS.Space.l)
                .background(DS.Colors.accent.opacity(isEnabled ? 1 : 0.35),
                            in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.88 : 1)
                .animation(DS.Motion.quick, value: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }

    /// Tinted button for the alternative action.
    struct SecondaryButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(DS.Typography.headline)
                .foregroundStyle(DS.Colors.accent.opacity(isEnabled ? 1 : 0.4))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: DS.Size.largeTapTarget)
                .padding(.horizontal, DS.Space.l)
                .background(DS.Colors.accentSoft.opacity(configuration.isPressed ? 0.7 : 1),
                            in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                .contentShape(Rectangle())
        }
    }
}

// MARK: - InfoCard

extension DS {
    /// Icon, title and at most two short lines. Longer explanations go behind "Learn why".
    struct InfoCard: View {
        let systemImage: String
        let title: String
        var message: String?
        /// Shown when the user taps "Learn why".
        var learnMore: String?
        /// Washes the card and icon with a status color.
        var level: Level?

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var expanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                HStack(alignment: .top, spacing: DS.Space.m) {
                    IconBadge(systemImage: systemImage, color: level?.color ?? DS.Colors.accent)
                    VStack(alignment: .leading, spacing: DS.Space.xs) {
                        Text(title)
                            .font(DS.Typography.headline)
                            .foregroundStyle(DS.Colors.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        if let message {
                            Text(message)
                                .font(DS.Typography.subheadline)
                                .foregroundStyle(DS.Colors.textSecondary)
                                // Two lines is the rule; at accessibility sizes never cut words off.
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                if let learnMore {
                    Button {
                        if let animation = DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion) {
                            withAnimation(animation) { expanded.toggle() }
                        } else {
                            expanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text(expanded ? "Hide" : "Learn why")
                            Image(systemName: "chevron.down")
                                .rotationEffect(.degrees(expanded ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                        .font(DS.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Colors.accent)
                        .frame(minHeight: DS.Size.tapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(expanded ? Text("Expanded") : Text("Collapsed"))
                    if expanded {
                        Text(learnMore)
                            .font(DS.Typography.subheadline)
                            .foregroundStyle(DS.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .dsCard(tint: level?.color)
        }
    }

    /// SF Symbol on a soft rounded square. Decorative.
    struct IconBadge: View {
        let systemImage: String
        var color: Color = DS.Colors.accent
        @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 44

        var body: some View {
            Image(systemName: systemImage)
                .font(M.Font.section)
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - ActionCard

extension DS {
    /// A whole card that does one thing. The entire card is the tap target.
    struct ActionCard: View {
        enum Style {
            /// Filled accent: the main thing to do on this screen. Use once per screen.
            case prominent
            /// Plain card.
            case standard
        }

        let systemImage: String
        let title: String
        var subtitle: String?
        var style: Style = .standard
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: DS.Space.m) {
                    icon
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(title)
                            .font(DS.Typography.headline)
                        if let subtitle {
                            Text(subtitle)
                                .font(DS.Typography.subheadline)
                                .opacity(style == .prominent ? 0.9 : 1)
                                .foregroundStyle(style == .prominent ? DS.Colors.onAccent : DS.Colors.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.s)
                    Image(systemName: "arrow.right")
                        .font(M.Font.section)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(style == .prominent ? DS.Colors.onAccent : DS.Colors.textPrimary)
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                .background(background)
                .contentShape(RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
            }
            .buttonStyle(PressableCardStyle())
        }

        @ViewBuilder
        private var icon: some View {
            if style == .prominent {
                Image(systemName: systemImage)
                    .font(M.Font.section)
                    .frame(width: 44, height: 44)
                    .background(DS.Colors.onAccent.opacity(0.18), in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                IconBadge(systemImage: systemImage)
            }
        }

        @ViewBuilder
        private var background: some View {
            let shape = RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous)
            switch style {
            case .prominent:
                shape.fill(DS.Colors.accent)
            case .standard:
                shape.fill(DS.Colors.surface)
                    .overlay(shape.strokeBorder(DS.Colors.separator))
                    .shadow(color: .black.opacity(DS.Elevation.card.opacity), radius: DS.Elevation.card.radius, y: DS.Elevation.card.y)
            }
        }
    }

    /// Slight press-down for tappable cards.
    struct PressableCardStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .opacity(configuration.isPressed ? 0.9 : 1)
                .animation(DS.Motion.quick, value: configuration.isPressed)
        }
    }
}

// MARK: - ChoiceCard

extension DS {
    /// A large answer card for questions (Risk Check, onboarding). Selected shows a filled check,
    /// accent border and tint, and VoiceOver hears "Selected".
    struct ChoiceCard: View {
        let title: String
        var subtitle: String?
        var systemImage: String?
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous)
            Button {
                DS.Haptics.selection()
                action()
            } label: {
                HStack(spacing: DS.Space.m) {
                    if let systemImage {
                        IconBadge(systemImage: systemImage)
                    }
                    VStack(alignment: .leading, spacing: DS.Space.xxs) {
                        Text(title)
                            .font(DS.Typography.headline)
                            .foregroundStyle(DS.Colors.textPrimary)
                        if let subtitle {
                            Text(subtitle)
                                .font(DS.Typography.subheadline)
                                .foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.Space.s)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(isSelected ? DS.Colors.accent : DS.Colors.textSecondary.opacity(0.6))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                }
                .padding(DS.Space.l)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .background(shape.fill(isSelected ? DS.Colors.accentSoft : DS.Colors.surface))
                .overlay(shape.strokeBorder(isSelected ? DS.Colors.accent : DS.Colors.separator,
                                            lineWidth: isSelected ? 2 : 1))
                .contentShape(shape)
            }
            .buttonStyle(PressableCardStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityValue(isSelected ? Text("Selected") : Text(""))
        }
    }
}

// MARK: - EmptyStateView

extension DS {
    /// Icon, one sentence, one button.
    struct EmptyStateView: View {
        let systemImage: String
        let message: String
        let actionTitle: String
        var actionImage: String?
        let action: () -> Void

        @ScaledMetric(relativeTo: .largeTitle) private var circle: CGFloat = 88

        var body: some View {
            VStack(spacing: DS.Space.l) {
                Image(systemName: systemImage)
                    .font(.system(.largeTitle, weight: .semibold))
                    .foregroundStyle(DS.Colors.accent)
                    .frame(width: circle, height: circle)
                    .background(DS.Colors.accentSoft, in: Circle())
                    .accessibilityHidden(true)
                Text(message)
                    .font(DS.Typography.body)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    if let actionImage {
                        Label(actionTitle, systemImage: actionImage)
                    } else {
                        Text(actionTitle)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.vertical, DS.Space.xl)
            .dsCard(padding: DS.Space.xl)
        }
    }
}

// MARK: - Previews

private struct CardSamples: View {
    @State private var answer: Int? = 1

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.l) {
            DS.InfoCard(systemImage: DS.Icon.test, title: "Test for bacteria every year",
                        message: "Germs can get in after storms or repairs.",
                        learnMore: "Coliform bacteria show that surface water may be reaching your well. E. coli means sewage or animal waste. Testing once a year catches problems early.")
            DS.InfoCard(systemImage: DS.Icon.contaminant(.lead), title: "Lead is above the limit",
                        message: "Use bottled water for drinking and cooking.", level: .unsafe)
            DS.ActionCard(systemImage: DS.Icon.riskCheck, title: "Should I test my well?",
                          subtitle: "7 quick questions", style: .prominent) {}
            DS.ActionCard(systemImage: DS.Icon.scan, title: "Scan a lab report", subtitle: "Takes about a minute") {}
            ForEach(0..<3) { i in
                DS.ChoiceCard(title: ["Yes", "No", "I don't know"][i],
                              systemImage: ["checkmark", "xmark", "questionmark"][i],
                              isSelected: answer == i) { answer = i }
            }
            DS.EmptyStateView(systemImage: "doc.text.magnifyingglass", message: "You haven't added a lab report yet.",
                              actionTitle: "Scan a report", actionImage: DS.Icon.scan) {}
            Button("Primary") {}.buttonStyle(DS.PrimaryButtonStyle())
            Button("Secondary") {}.buttonStyle(DS.SecondaryButtonStyle())
        }
    }
}

#Preview("Light") { CardSamples().dsPreview(.light) }
#Preview("Dark") { CardSamples().dsPreview(.dark) }
#Preview("Largest text") { CardSamples().dsPreview(.largestText) }
