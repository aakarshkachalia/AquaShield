//
//  HomeView.swift
//  ClearWellNC
//
//  Dashboard. Shows ONE of three states, most important first:
//    a) no results yet → "Should I test my well?" + scan;
//    b) results, no health problems → score ring, summary, next retest, seasonal tip;
//    c) a health limit exceeded → red status card, what to do now, help paying for a fix.
//

import SwiftData
import SwiftUI

extension LabResult {
    /// Values at or above a health limit, counting bacteria.
    var aboveLimitCount: Int {
        var count = Analyte.allCases.filter { a in
            value(for: a).map { a.evaluate($0).kind == .above } ?? false
        }.count
        if totalColiform == .present { count += 1 }
        if eColi == .present { count += 1 }
        return count
    }
}

struct HomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(TractStore.self) private var store
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Environment(WellCareStore.self) private var wellCare
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]

    @State private var trends = CountyTrendData.loadBundled()

    private enum State {
        case noResults
        case allOK(LabResult)
        case problem(LabResult, [Interpretation])
    }

    private var state: State {
        guard let latest = results.first else { return .noResults }
        let findings = latest.healthFindings
        return findings.isEmpty ? .allOK(latest) : .problem(latest, findings)
    }

    private var county: String? {
        settings.effectiveCounty(savedWellCounty: savedWellCounty(savedWells, store: store))
    }

    private var wellCareContext: WellCareContext {
        WellCareContext.make(results: results, county: county, trends: trends)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if !alertsStore.relevantAlerts.isEmpty {
                        WeatherAlertsCard(store: alertsStore) {}
                    }

                    switch state {
                    case .noResults:
                        noResultsCard
                    case .allOK(let latest):
                        allOKCard(latest)
                        PrimaryButton(title: "Scan Report", systemImage: "doc.viewfinder") { router.showingScanner = true }
                    case .problem(let latest, let findings):
                        problemCard(latest, findings: findings)
                        PrimaryButton(title: "Scan Report", systemImage: "doc.viewfinder") { router.showingScanner = true }
                    }

                    StormHomeCard()

                    if let latest = results.first {
                        ReportQuestCard(latest: latest, context: wellCareContext)
                    }
                    if let challenge = wellCareContext.challenge {
                        SeasonalChallengeCard(challenge: challenge)
                    } else if case .allOK = state {
                        seasonalTip
                    }

                    if case .noResults = state {} else {
                        DisclaimerFooter()
                    }
                }
                .screenContainer()
            }
            .background(Color.appBackground)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            // Badges can come from tests alone (Steady Keeper, Seasonal Scout). Demo data never earns badges.
            .task(id: results.count) {
                guard !settings.demoEnabled else { return }
                wellCare.reload()
                wellCare.refreshBadges(testDates: wellCareContext.testDates, highRiskMonths: wellCareContext.highRiskMonths)
            }
        }
    }

    // MARK: a) No results

    private var noResultsCard: some View {
        InfoCard(systemImage: "questionmark.circle.fill",
                 title: String(localized: "Should I test my well?"),
                 message: String(localized: "Answer 7 quick questions to see which tests your well needs and where to get them, often for free or low cost.")) {
            VStack(spacing: Spacing.m) {
                PrimaryButton(title: "Start the Risk Check", systemImage: "checklist") { router.showingRiskCheck = true }
                SecondaryButton(title: "Already have a report? Scan it", systemImage: "doc.viewfinder") {
                    router.showingScanner = true
                }
            }
        }
    }

    // MARK: b) All OK

    private func allOKCard(_ latest: LabResult) -> some View {
        let score = WellHealthScore.compute(results.latestScoreInput)
        let nextTest = QuestReminderRule.nextTestDue(testDates: results.map(\.date))
        return VStack(alignment: .leading, spacing: Spacing.l) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.l) {
                    ScoreRing(result: score)
                    summary(score: score, latest: latest)
                }
                VStack(alignment: .leading, spacing: Spacing.l) {
                    ScoreRing(result: score)
                    summary(score: score, latest: latest)
                }
            }
            Label {
                Text("Next retest: \(nextTest.formatted(date: .long, time: .omitted))")
            } icon: {
                Image(systemName: "calendar.badge.clock").foregroundStyle(Color.brandPrimary)
            }
            .font(.subheadline.weight(.semibold))
            NavigationLink {
                WellScoreView()
            } label: {
                Label("What's behind my score", systemImage: "chevron.right")
                    .labelStyle(.titleOnly)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .card()
    }

    private func summary(score: WellHealthScore.Result, latest: LabResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text("Your water meets all health limits")
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let band = score.band {
                StatusChip(tier: band.tier, label: band.label)
            }
            Text("Based on your test from \(latest.date.formatted(date: .abbreviated, time: .omitted)).")
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
            if !score.isComplete {
                Text(incompleteText(score))
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var seasonalTip: some View {
        InfoCard(style: .status(.safe), systemImage: "leaf.fill",
                 title: String(localized: "Seasonal tip"),
                 message: String(localized: "Test for bacteria every year, and again after any flooding or heavy storms."))
    }

    // MARK: c) Problem

    private func problemCard(_ latest: LabResult, findings: [Interpretation]) -> some View {
        let first = findings[0]
        let name = first.id.info.name
        let title: String = if first.id == .eColi {
            String(localized: "E. coli was found in your water")
        } else if findings.count == 1 {
            String(localized: "\(name) is above the safe limit")
        } else {
            String(localized: "\(name) and \(findings.count - 1) more are above health limits")
        }
        return InfoCard(style: .danger, systemImage: "exclamationmark.octagon.fill", title: title,
                        message: String(localized: "From your test on \(latest.date.formatted(date: .abbreviated, time: .omitted)).")) {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("What to do now")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(first.id.info.actionIfAbove)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    router.openHelp(.contaminant(first.id))
                } label: {
                    Label("Get help paying for a fix", systemImage: "dollarsign.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Color(hex: 0xB3161F))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
                .buttonStyle(.plain)
                Button {
                    router.selectedTab = .myWater
                } label: {
                    Text("See all my results")
                        .font(.headline)
                        .underline()
                        .frame(maxWidth: .infinity, minHeight: TapTarget.minimum)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
