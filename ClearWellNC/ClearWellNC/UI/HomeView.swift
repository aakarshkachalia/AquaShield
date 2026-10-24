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
    @State private var countyData = CountyWellData.loadBundled()

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
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    if !alertsStore.relevantAlerts.isEmpty {
                        WeatherAlertsCard(store: alertsStore) {}
                    }

                    switch state {
                    case .noResults:
                        noResults
                    case .allOK(let latest):
                        allOKCard(latest)
                    case .problem(let latest, let findings):
                        problemCard(latest, findings: findings)
                    }

                    StormHomeCard()

                    if let latest = results.first {
                        ReportQuestCard(latest: latest, context: wellCareContext)
                    }
                    if let challenge = wellCareContext.challenge {
                        SeasonalChallengeCard(challenge: challenge)
                    } else if case .allOK = state {
                        DS.InfoCard(systemImage: "leaf.fill",
                                    title: String(localized: "Test for germs every year"),
                                    message: String(localized: "And again after any flood or big storm."),
                                    level: .good)
                    }

                    if case .noResults = state {} else {
                        DisclaimerFooter()
                    }
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle("Home")
            .toolbar {
                if !results.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Scan Report", systemImage: DS.Icon.scan) { router.showingScanner = true }
                    }
                }
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

    @ViewBuilder
    private var noResults: some View {
        if let answers = settings.riskAnswers {
            recommendedTests(answers)
        } else {
            VStack(spacing: DS.Space.m) {
                DS.ActionCard(systemImage: DS.Icon.riskCheck, title: String(localized: "Should I test my well?"),
                              subtitle: String(localized: "7 quick questions"), style: .prominent) {
                    router.showingRiskCheck = true
                }
                DS.ActionCard(systemImage: DS.Icon.scan, title: String(localized: "Already tested? Scan your report"),
                              subtitle: String(localized: "We'll explain every number")) {
                    router.showingScanner = true
                }
            }
        }
    }

    /// After a finished Risk Check: its tests stay on Home until a report is added.
    private func recommendedTests(_ answers: RiskCheckAnswers) -> some View {
        let result = RiskCheckEngine.recommend(answers: answers, countyData: countyData, trends: trends,
                                               pfasCounties: HelpLibrary.pfasTestingCounties)
        return VStack(alignment: .leading, spacing: DS.Space.m) {
            VStack(alignment: .leading, spacing: DS.Space.m) {
                Text("Your recommended tests")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(result.tests) { test in
                    Label {
                        Text(test.id.name).font(DS.Typography.headline)
                    } icon: {
                        Image(systemName: DS.Icon.recommendedTest(test.id)).foregroundStyle(DS.Colors.accent)
                    }
                    .foregroundStyle(DS.Colors.textPrimary)
                }
            }
            .dsCard()
            DS.ActionCard(systemImage: "mappin.and.ellipse", title: String(localized: "Get tested"),
                          subtitle: String(localized: "Labs and free programs near you"), style: .prominent) {
                router.openHelp(.testing)
            }
            HStack {
                Button("Redo the Risk Check") { router.showingRiskCheck = true }
                Spacer()
                Button("Scan a report") { router.showingScanner = true }
            }
            .font(DS.Typography.subheadline.weight(.semibold))
            .foregroundStyle(DS.Colors.accent)
            .frame(minHeight: DS.Size.tapTarget)
        }
    }

    // MARK: b) All OK

    private func allOKCard(_ latest: LabResult) -> some View {
        let score = WellHealthScore.compute(results.latestScoreInput)
        let nextTest = QuestReminderRule.nextTestDue(testDates: results.map(\.date))
        return VStack(spacing: DS.Space.l) {
            DS.ScoreRing(result: score)
                .padding(.top, DS.Space.s)
            VStack(spacing: DS.Space.xs) {
                Text("Your water meets all health limits")
                    .font(DS.Typography.title)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text("From your test on \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(DS.Colors.textSecondary)
                if !score.isComplete {
                    Label(incompleteText(score), systemImage: "list.bullet.clipboard")
                        .font(DS.Typography.subheadline)
                        .foregroundStyle(DS.Colors.textSecondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                WellScoreView()
            } label: {
                Text("What's behind my score")
            }
            .buttonStyle(DS.PrimaryButtonStyle())
            Label {
                Text("Next test: \(nextTest.formatted(date: .long, time: .omitted))")
            } icon: {
                Image(systemName: "calendar.badge.clock").foregroundStyle(DS.Colors.accent)
            }
            .font(DS.Typography.subheadline.weight(.semibold))
            .foregroundStyle(DS.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity)
        .dsCard(padding: DS.Space.xl)
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
        let action = first.id.info.actionIfAbove
        let shortAction = QuestText.firstSentences(action, max: 1)
        return VStack(alignment: .leading, spacing: DS.Space.l) {
            Label {
                Text(title).font(DS.Typography.title)
            } icon: {
                Image(systemName: DS.Level.unsafe.symbol)
            }
            .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text("Do this now").font(DS.Typography.caption).textCase(.uppercase)
                Text(shortAction).font(DS.Typography.headline)
            }
            .fixedSize(horizontal: false, vertical: true)
            if shortAction != action {
                DisclosureGroup {
                    Text(action)
                        .font(DS.Typography.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DS.Space.s)
                } label: {
                    Text("Learn why").font(DS.Typography.subheadline.weight(.semibold))
                }
                .tint(.white)
            }
            Button {
                router.openHelp(.contaminant(first.id))
            } label: {
                Label("Get help paying for a fix", systemImage: "dollarsign.circle.fill")
                    .font(DS.Typography.headline)
                    .foregroundStyle(Color(hex: 0xB3161F))
                    .frame(maxWidth: .infinity, minHeight: DS.Size.largeTapTarget)
                    .background(.white, in: RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
            }
            .buttonStyle(.plain)
            Button("See all my results") { router.selectedTab = .myWater }
                .font(DS.Typography.subheadline.weight(.semibold))
                .underline()
                .frame(maxWidth: .infinity, minHeight: DS.Size.tapTarget)
                .buttonStyle(.plain)
            Text("From your test on \(latest.date.formatted(date: .abbreviated, time: .omitted))")
                .font(DS.Typography.footnote)
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Fixed red in both modes so white text always passes contrast.
        .background(Color(hex: 0xB3161F), in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
