//
//  OnboardingView.swift
//  ClearWellNC
//
//  First launch only, skippable: what ClearWell does → pick your county → "Do you have a lab report?"
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(StorageKey.hasOnboarded) private var hasOnboarded = false
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure

    @State private var page = 0
    @State private var county: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { finish() }
                    .font(.headline)
                    .frame(minWidth: TapTarget.minimum, minHeight: TapTarget.minimum)
                    .accessibilityHint(Text("Skips the welcome screens"))
            }
            .padding(.horizontal, Spacing.l)

            TabView(selection: $page) {
                welcome.tag(0)
                countyPage.tag(1)
                reportPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .background(Color.appBackground)
        .onAppear { county = settings.county }
    }

    // MARK: Pages

    private var welcome: some View {
        page {
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
        } action: {
            PrimaryButton(title: "Next") { go(to: 1) }
        }
    }

    private var countyPage: some View {
        page {
            Text("Which county do you live in?")
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text("Well risks differ across North Carolina's 100 counties. We use this for local facts and help programs. It stays on this device.")
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Picker("County", selection: $county) {
                Text("Choose later").tag(String?.none)
                ForEach(CountyNames.all, id: \.self) { name in
                    Text(String(localized: "\(name) County")).tag(Optional(name))
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .card()
        } action: {
            PrimaryButton(title: county == nil ? "Skip for now" : "Next") {
                settings.county = county
                go(to: 2)
            }
        }
    }

    private var reportPage: some View {
        page {
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
        } action: {
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

    private func page<Content: View, Action: View>(@ViewBuilder content: () -> Content,
                                                    @ViewBuilder action: () -> Action) -> some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    content()
                }
                .screenContainer()
            }
            action()
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.xxl + Spacing.l)   // clear the page dots
                .readableWidth()
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

    private func go(to next: Int) {
        if reduceMotion { page = next } else { withAnimation { page = next } }
    }

    private func finish() {
        if settings.county == nil { settings.county = county }
        // ClearWell is built for private wells; city-water users can change this in Settings.
        if waterSource == .notSure { waterSource = .privateWell }
        hasOnboarded = true
    }
}
