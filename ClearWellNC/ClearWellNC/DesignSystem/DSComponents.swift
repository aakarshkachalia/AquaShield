//
//  DSComponents.swift
//  ClearWellNC
//
//  Reusable building blocks. Every screen composes these instead of styling things inline.
//

import SwiftUI

// MARK: - StatusChip

/// Icon + text + color. Color reinforces, but never replaces, the text.
struct StatusChip: View {
    let tier: Interpretation.Tier
    let label: String

    var body: some View {
        Label {
            Text(label)
                .foregroundStyle(Color.textPrimary)
        } icon: {
            Image(systemName: tier.symbol)
                .foregroundStyle(tier.color)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(tier.color.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(tier.color.opacity(0.6)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Status: \(label)"))
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.top, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - InfoCard

/// Icon, title, message and optional extra content on a card.
struct InfoCard<Content: View>: View {
    enum Style {
        case standard
        /// Tinted with a status color (watch, safe…).
        case status(Interpretation.Tier)
        /// Solid red: serious health problems only. Fixed colors so white text always passes contrast.
        case danger
    }

    var style: Style = .standard
    let systemImage: String
    let title: String
    var message: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            content
        }
        .foregroundStyle(textColor)
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(border))
    }

    private var iconColor: Color {
        switch style {
        case .standard: .brandPrimary
        case .status(let tier): tier.color
        case .danger: .white
        }
    }

    private var textColor: Color {
        if case .danger = style { return .white }
        return .textPrimary
    }

    private var background: Color {
        switch style {
        case .standard: .surface
        case .status(let tier): tier.color.opacity(0.10)
        case .danger: Color(hex: 0xB3161F)
        }
    }

    private var border: Color {
        switch style {
        case .standard: .cardBorder
        case .status(let tier): tier.color.opacity(0.5)
        case .danger: .clear
        }
    }
}

extension InfoCard where Content == EmptyView {
    init(style: Style = .standard, systemImage: String, title: String, message: String? = nil) {
        self.init(style: style, systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Buttons

/// Filled brand button for the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.onBrand)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, Spacing.l)
            .background(Color.brandPrimary.opacity(isEnabled ? 1 : 0.4),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// Outlined button for secondary actions.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Color.brandPrimary.opacity(isEnabled ? 1 : 0.4))
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
            .padding(.horizontal, Spacing.l)
            .background(Color.brandPrimary.opacity(configuration.isPressed ? 0.16 : 0.08),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.brandPrimary.opacity(0.35)))
            .contentShape(Rectangle())
    }
}

struct PrimaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .buttonStyle(PrimaryButtonStyle())
    }
}

struct SecondaryButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage { Label(title, systemImage: systemImage) } else { Text(title) }
        }
        .buttonStyle(SecondaryButtonStyle())
    }
}

// MARK: - ContaminantRow

/// One reading: name, status chip, value and one plain-English line. Tappable (wrap in a NavigationLink).
struct ContaminantRow: View {
    let name: String
    let interpretation: Interpretation
    var showsChevron = true

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(name).font(.headline)
                        Spacer(minLength: Spacing.s)
                        StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                    }
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(name).font(.headline)
                        StatusChip(tier: interpretation.tier, label: interpretation.chipLabel)
                    }
                }
                HStack(spacing: Spacing.s) {
                    Text(interpretation.readingText)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    if let percent = interpretation.percentText {
                        Text(percent)
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Text(QuestText.firstSentences(interpretation.sentence, max: 1))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, Spacing.xs)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Color.textPrimary)
        .padding(.vertical, Spacing.s)
        .frame(minHeight: TapTarget.minimum)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                PrimaryButton(title: actionTitle, action: action)
                    .padding(.top, Spacing.s)
            }
        }
        .padding(Spacing.xl)
        .frame(maxWidth: .infinity)
        .card()
        .accessibilityElement(children: .contain)
    }
}

// MARK: - DisclaimerFooter

/// Required on score, forecast, risk, help and storm screens.
struct DisclaimerFooter: View {
    /// Optional screen-specific sentence shown before the standard text.
    var lead: String?
    var showsLinks = true

    static var standardText: String {
        String(localized: "\(AppName.display) is educational and is not medical advice. Only a state-certified lab test can tell you what is in your water.")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Label {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if let lead { Text(lead) }
                    Text(Self.standardText)
                }
                .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "info.circle.fill").foregroundStyle(Color.brandPrimary)
            }
            .font(.caption)
            .foregroundStyle(Color.textSecondary)
            if showsLinks {
                Link(destination: WellResources.ncdhhsPrivateWells) {
                    Label("NC DHHS: private well testing", systemImage: "arrow.up.right.square")
                        .frame(minHeight: TapTarget.minimum)
                }
                Link(destination: WellResources.ncCountyHealthDepartments) {
                    Label("Find your county health department", systemImage: "arrow.up.right.square")
                        .frame(minHeight: TapTarget.minimum)
                }
            }
        }
        .font(.subheadline)
        .padding(.top, Spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Small pieces

/// SF Symbol on a tinted rounded square. Decorative: hidden from VoiceOver.
struct IconTile: View {
    let systemImage: String
    var color: Color = .brandPrimary
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.title2)
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Icon tile, title, subtitle and chevron: the card used for every "go to" row.
struct NavigationCardLabel: View {
    let title: Text
    let subtitle: Text
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.m) {
            IconTile(systemImage: systemImage)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                title
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: TapTarget.minimum)
        .contentShape(Rectangle())
        .card()
        .accessibilityElement(children: .combine)
    }
}

/// "Sample data" label shown on every screen that uses a demo report or placeholder data.
struct SampleDataBanner: View {
    var text: LocalizedStringKey = "Sample data: not a real test result"

    var body: some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.m)
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity)
            .background(Color.statusWatch.opacity(0.18))
            .accessibilityElement(children: .combine)
    }
}

/// Inline "Sample data" tag for cards.
struct SampleDataTag: View {
    var body: some View {
        Label("Sample data", systemImage: "info.circle.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(Color.statusWatch.opacity(0.18), in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}

/// Health Score ring. The number and band are text; the ring is decoration.
struct ScoreRing: View {
    let result: WellHealthScore.Result
    var diameter: CGFloat = 132

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let fraction = Double(result.score ?? 0) / 100
        let color = result.band?.tier.color ?? .statusUnknown
        ZStack {
            Circle().stroke(Color.textPrimary.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: shown ? fraction : 0)
                .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(result.score.map { "\($0)" } ?? "—")
                    .font(.largeTitle.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)   // stays inside the ring at the largest text sizes
                    .foregroundStyle(Color.textPrimary)
                Text("of 100")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(Spacing.l)
        }
        .frame(width: diameter, height: diameter)
        .onAppear {
            if reduceMotion { shown = true } else { withAnimation(.easeOut(duration: 0.6)) { shown = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.score.map { Text("Health score \($0) out of 100") } ?? Text("No health score yet"))
        .accessibilityValue(Text(result.band?.label ?? ""))
    }
}

/// Solid red alert banner (E. coli, health exceedances).
struct UrgentBanner<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .foregroundStyle(.white)
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xB3161F), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)
    }
}
