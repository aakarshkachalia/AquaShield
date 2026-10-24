//
//  DesignSystemGalleryView.swift
//  ClearWellNC
//
//  Every token and component on one screen, for reviewing on a device. DEBUG builds only, from Settings.
//  The toolbar menu switches light/dark and the largest text size without leaving the app.
//

#if DEBUG
import SwiftUI

struct DesignSystemGalleryView: View {
    private enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark
        var id: Self { self }
        var scheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    @State private var appearance = Appearance.system
    @State private var largestText = false
    @State private var replay = 0
    @State private var choice: Int?
    @State private var showingFlow = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.xxl) {
                colors
                levels
                typography
                spacingAndShape
                icons
                components
                flow
                haptics
            }
            .dsScreen()
            // Changing the id re-creates the samples, so appear animations play again.
            .id(replay)
        }
        .background(DS.Colors.background)
        .navigationTitle("Design System")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Toggle("Largest text size", isOn: $largestText)
                    Button("Replay animations", systemImage: "play.circle") { replay += 1 }
                } label: {
                    Label("Display options", systemImage: "slider.horizontal.3")
                }
            }
        }
        .preferredColorScheme(appearance.scheme)
        .environment(\.dynamicTypeSize, largestText ? .accessibility5 : .large)
        .fullScreenCover(isPresented: $showingFlow) {
            GalleryFlowDemo { showingFlow = false }
                .preferredColorScheme(appearance.scheme)
                .environment(\.dynamicTypeSize, largestText ? .accessibility5 : .large)
        }
    }

    // MARK: Tokens

    private var colors: some View {
        section("Colors", note: "Every color has a light and dark value. Status colors pass WCAG AA (4.5:1) on background and cards in both modes.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: DS.Space.m)], spacing: DS.Space.m) {
                swatch("Background", DS.Colors.background)
                swatch("Surface", DS.Colors.surface)
                swatch("Surface raised", DS.Colors.surfaceRaised)
                swatch("Accent", DS.Colors.accent)
                swatch("Accent soft", DS.Colors.accentSoft)
                swatch("Water (decor)", DS.Colors.water)
                swatch("Text primary", DS.Colors.textPrimary)
                swatch("Text secondary", DS.Colors.textSecondary)
                ForEach(DS.Level.allCases.reversed()) { swatch($0.label, $0.color) }
            }
        }
    }

    private var levels: some View {
        section("Status levels", note: "Each level has its own icon and word, so it never relies on color.") {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                ForEach(DS.Level.allCases.reversed()) { level in
                    HStack {
                        DS.StatusBadge(level: level)
                        Spacer()
                        Text(level.symbol)
                            .font(.caption.monospaced())
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
            }
            .dsCard()
        }
    }

    private var typography: some View {
        section("Type", note: "All Dynamic Type text styles. Try the largest text size in the menu.") {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("Display 72").font(DS.Typography.display)
                Text("Title: Your water").font(DS.Typography.title)
                Text("Headline: Nitrate").font(DS.Typography.headline)
                Text("Body: Test your well once a year.").font(DS.Typography.body)
                Text("Callout: Results take about a week.").font(DS.Typography.callout)
                Text("Subheadline: Based on your test from May 2.").font(DS.Typography.subheadline)
                Text("Footnote: Limit 10 mg/L").font(DS.Typography.footnote)
                Text("CAPTION · QUESTION 2 OF 7").font(DS.Typography.caption)
                Text("6.2 mg/L").font(DS.Typography.metric)
            }
            .foregroundStyle(DS.Colors.textPrimary)
            .dsCard()
        }
    }

    private var spacingAndShape: some View {
        section("Spacing, corners, elevation") {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                ForEach([("xxs", DS.Space.xxs), ("xs", DS.Space.xs), ("s", DS.Space.s), ("m", DS.Space.m),
                         ("l", DS.Space.l), ("xl", DS.Space.xl), ("xxl", DS.Space.xxl), ("xxxl", DS.Space.xxxl)], id: \.0) { name, value in
                    HStack {
                        Text("\(name) · \(Int(value))").font(.caption.monospaced()).frame(width: 90, alignment: .leading)
                        RoundedRectangle(cornerRadius: 2).fill(DS.Colors.water).frame(width: value * 3, height: 10)
                    }
                    .foregroundStyle(DS.Colors.textSecondary)
                }
                HStack(spacing: DS.Space.m) {
                    ForEach([("small", DS.Corner.small), ("medium", DS.Corner.medium), ("large", DS.Corner.large)], id: \.0) { name, radius in
                        Text(name)
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(DS.Colors.separator))
                    }
                }
                Text("Card elevation: soft shadow in light mode, none in dark mode.")
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .dsCard()
                Text("Raised elevation")
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .dsCard(elevation: .raised)
            }
        }
    }

    private var icons: some View {
        section("Icons") {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                iconGrid("Contaminant categories", DS.ContaminantCategory.allCases.map { ($0.label, DS.Icon.category($0)) })
                iconGrid("Filter types", TreatmentKind.allCases.map { ($0.name, DS.Icon.filter($0)) })
                iconGrid("Alerts", DS.AlertKind.allCases.map { ($0.label, DS.Icon.alert($0)) })
                iconGrid("Status levels", DS.Level.allCases.reversed().map { ($0.label, $0.symbol) })
            }
        }
    }

    // MARK: Components

    private var components: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            section("ScoreRing", note: "VoiceOver: \"Water Health Score 72 out of 100, Fair\".") {
                HStack {
                    Spacer()
                    DS.ScoreRing(score: 72, level: .fair)
                    Spacer()
                }
                .dsCard(padding: DS.Space.xl)
            }
            section("LevelMeter") {
                VStack(spacing: DS.Space.m) {
                    DS.LevelMeter(name: "Nitrate", value: 2.1, limit: 10, unit: "mg/L", level: .good).dsCard()
                    DS.LevelMeter(name: "Arsenic", value: 7, limit: 10, unit: "µg/L", level: .fair).dsCard()
                    DS.LevelMeter(name: "Lead", value: 22, limit: 15, unit: "µg/L", level: .unsafe).dsCard()
                }
            }
            section("InfoCard") {
                VStack(spacing: DS.Space.m) {
                    DS.InfoCard(systemImage: DS.Icon.test, title: "Test for bacteria every year",
                                message: "Germs can get in after storms or repairs.",
                                learnMore: "Coliform bacteria show that surface water may be reaching your well. Testing once a year catches problems early.")
                    DS.InfoCard(systemImage: DS.Icon.contaminant(.lead), title: "Lead is above the limit",
                                message: "Use bottled water for drinking and cooking.", level: .unsafe)
                }
            }
            section("ActionCard") {
                VStack(spacing: DS.Space.m) {
                    DS.ActionCard(systemImage: DS.Icon.riskCheck, title: "Should I test my well?",
                                  subtitle: "7 quick questions", style: .prominent) {}
                    DS.ActionCard(systemImage: DS.Icon.scan, title: "Scan a lab report", subtitle: "Takes about a minute") {}
                }
            }
            section("ChoiceCard", note: "Selected: filled check, accent border, VoiceOver says \"Selected\".") {
                VStack(spacing: DS.Space.m) {
                    ForEach(Array(["Yes", "No", "I don't know"].enumerated()), id: \.offset) { i, title in
                        DS.ChoiceCard(title: title, systemImage: ["checkmark", "xmark", "questionmark"][i],
                                      isSelected: choice == i) { choice = i }
                    }
                }
            }
            section("EmptyStateView") {
                DS.EmptyStateView(systemImage: "doc.text.magnifyingglass", message: "You haven't added a lab report yet.",
                                  actionTitle: "Scan a report", actionImage: DS.Icon.scan) {}
            }
            section("Buttons") {
                VStack(spacing: DS.Space.m) {
                    Button("Primary") {}.buttonStyle(DS.PrimaryButtonStyle())
                    Button("Secondary") {}.buttonStyle(DS.SecondaryButtonStyle())
                    Button("Disabled") {}.buttonStyle(DS.PrimaryButtonStyle()).disabled(true)
                }
            }
        }
    }

    private var flow: some View {
        section("Step flow style", note: "Progress bar, Back, and Next, using ClearWellStepFlowStyle, which every flow in the app now uses.") {
            DS.ActionCard(systemImage: "rectangle.stack.fill", title: "Open a sample flow", subtitle: "4 questions") {
                showingFlow = true
            }
        }
    }

    private var haptics: some View {
        section("Haptics", note: "Try these on a phone.") {
            HStack(spacing: DS.Space.m) {
                Button("Success") { DS.Haptics.success() }
                Button("Selection") { DS.Haptics.selection() }
                Button("Warning") { DS.Haptics.warning() }
            }
            .buttonStyle(DS.SecondaryButtonStyle())
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, note: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(title)
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let note {
                    Text(note)
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            content()
        }
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous)
                .fill(color)
                .frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous).strokeBorder(DS.Colors.separator))
            Text(name)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.Colors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    private func iconGrid(_ title: String, _ items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(title).font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: DS.Space.m)], spacing: DS.Space.m) {
                ForEach(items, id: \.0) { label, symbol in
                    VStack(spacing: DS.Space.xs) {
                        DS.IconBadge(systemImage: symbol)
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(DS.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .dsCard()
        }
    }
}

/// A four-question flow in the new style, for trying Back, Next and progress.
private struct GalleryFlowDemo: View {
    let onClose: () -> Void

    @State private var flow = StepFlow(root: 1)
    @State private var answers: [Int: Int] = [:]
    private let order = [1, 2, 3, 4]
    private let questions = [
        1: "Was your well drilled before 2008?",
        2: "Is anyone pregnant, or is there a baby in your home?",
        3: "Has flooding affected your well?",
        4: "When was your well last tested?",
    ]

    var body: some View {
        StepFlowContainer(flow: $flow,
                          progress: { step in
                              StepProgress(position: step, total: order.count,
                                           label: String(localized: "Question \(step) of \(order.count)"))
                          },
                          primaryAction: { step in
                              guard answers[step] != nil else { return nil }
                              return StepAction(title: step == order.last ? "Done" : "Next", systemImage: "arrow.right") {
                                  if step == order.last {
                                      DS.Haptics.success()
                                      onClose()
                                  } else {
                                      flow.advance(in: order)
                                  }
                              }
                          },
                          onClose: onClose) { step in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    Text(questions[step] ?? "")
                        .font(DS.Typography.title)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, DS.Space.s)
                    ForEach(Array(["Yes", "No", "I don't know"].enumerated()), id: \.offset) { i, title in
                        DS.ChoiceCard(title: title, systemImage: ["checkmark", "xmark", "questionmark"][i],
                                      isSelected: answers[step] == i) {
                            answers[step] = i
                        }
                    }
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
        }
        .stepFlowStyle(ClearWellStepFlowStyle())
    }
}

#Preview("Light") {
    NavigationStack { DesignSystemGalleryView() }.preferredColorScheme(.light)
}

#Preview("Dark") {
    NavigationStack { DesignSystemGalleryView() }.preferredColorScheme(.dark)
}

#Preview("Largest text") {
    NavigationStack { DesignSystemGalleryView() }.environment(\.dynamicTypeSize, .accessibility5)
}
#endif
