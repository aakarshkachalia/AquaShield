//
//  DashboardView.swift
//  ClearWellNC
//
//  Home tab. Top: drinking-water score, level, water source and confidence. Then tappable cards for
//  everything else; each opens its screen in one tap, so any main feature is at most two taps away.
//

import SwiftData
import SwiftUI

struct DashboardView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Environment(WellCareStore.self) private var wellCare
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var trends = CountyTrendData.loadBundled()
    @State private var sourceArea: WaterSystemArea?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var snapshot: WaterSnapshot {
        _ = settings.scopedRevision
        return WaterSnapshot.make(results: results, systems: systems, settings: settings)
    }

    private var wellCareContext: WellCareContext {
        WellCareContext.make(results: results, county: settings.county, trends: trends)
    }

    var body: some View {
        let snapshot = snapshot
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    ForEach(snapshot.alerts) { AlertBanner(alert: $0) }
                    if settings.isOptedIn(.stormAlerts), !alertsStore.relevantAlerts.isEmpty {
                        WeatherAlertsCard(store: alertsStore) {}
                    }
                    modes
                    hero(snapshot)
                    if snapshot.hasReadings {
                        tapRings(snapshot)
                    }
                    if snapshot.hasReadings || !snapshot.filters.isEmpty || !snapshot.members.isEmpty {
                        tiles(snapshot)
                    }
                    sourceCard
                    nextStep(snapshot)
                    StormHomeCard()
                    if let latest = results.first {
                        ReportQuestCard(latest: latest, context: wellCareContext)
                    }
                    if settings.waterSource.showsWellCare, let challenge = wellCareContext.challenge {
                        SeasonalChallengeCard(challenge: challenge)
                    }
                    if snapshot.hasReadings { DisclaimerFooter() }
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Scan Report", systemImage: DS.Icon.scan) { router.showingScanner = true }
                        .accessibilityIdentifier("dashboard.scan")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(isPresented: Bindable(router).showingHousehold) { HouseholdView() }
            .task(id: results.count) {
                guard !settings.demoEnabled else { return }
                wellCare.reload()
                wellCare.refreshBadges(testDates: wellCareContext.testDates, highRiskMonths: wellCareContext.highRiskMonths)
            }
        }
    }

    // MARK: Modes

    @ViewBuilder
    private var modes: some View {
        let active = WaterMode.allCases.filter { settings.activeModes.contains($0) }
        if !active.isEmpty {
            NavigationLink {
                ModesView()
            } label: {
                HStack(spacing: DS.Space.s) {
                    ForEach(active, id: \.self) { mode in
                        FlagChip(text: mode.label, systemImage: mode.symbol, color: DS.Colors.accent)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func hero(_ snapshot: WaterSnapshot) -> some View {
        if snapshot.hasReadings, let drinking = snapshot.drinking {
            NavigationLink {
                TapScoreView(tap: .kitchen)
            } label: {
                VStack(spacing: DS.Space.m) {
                    DS.ScoreRing(score: drinking.score, level: drinking.dsLevel,
                                 title: String(localized: "Drinking water score"))
                    Label(snapshot.source.settingName, systemImage: snapshot.source.symbol)
                        .font(DS.Typography.subheadline.weight(.semibold))
                        .foregroundStyle(DS.Colors.textSecondary)
                    ConfidenceBar(recommended: WellHealthScore.recommendedTargets(for: snapshot.source, isShower: false),
                                  missing: drinking.missingTests)
                    Text("See what's behind it")
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Colors.accent)
                }
                .frame(maxWidth: .infinity)
                .dsCard(padding: DS.Space.xl)
            }
            .buttonStyle(DS.PressableCardStyle())
            .accessibilityIdentifier("dashboard.score")
        } else {
            emptyHero(snapshot)
        }
    }

    @ViewBuilder
    private func emptyHero(_ snapshot: WaterSnapshot) -> some View {
        VStack(spacing: DS.Space.m) {
            if snapshot.source.showsWellCare {
                DS.ActionCard(systemImage: DS.Icon.riskCheck, title: String(localized: "Should I test my well?"),
                              subtitle: String(localized: "7 quick questions"), style: .prominent) {
                    router.showingRiskCheck = true
                }
            }
            if snapshot.source.showsCityContent {
                NavigationLink {
                    UtilityReportView()
                } label: {
                    NavigationCardLabel(title: Text("Add your utility's water report"),
                                        subtitle: Text("About 2 minutes, from your yearly report"),
                                        systemImage: "building.2.fill")
                }
                .buttonStyle(.plain)
            }
            DS.ActionCard(systemImage: DS.Icon.scan, title: String(localized: "Have test results? Scan them"),
                          subtitle: String(localized: "We'll explain every number")) {
                router.showingScanner = true
            }
            if snapshot.source == .notSure {
                NavigationLink {
                    SettingsView()
                } label: {
                    NavigationCardLabel(title: Text("Not sure where your water comes from?"),
                                        subtitle: Text("A water bill means city water. A pressure tank means a well."),
                                        systemImage: "questionmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Tiles

    private func tiles(_ snapshot: WaterSnapshot) -> some View {
        // Not a LazyVGrid: it left the last tile out of the accessibility tree (VoiceOver couldn't reach it).
        TileGrid(columns: dynamicTypeSize.isAccessibilitySize ? 1 : 2, spacing: DS.Space.m) {
            if let latest = snapshot.latest {
                NavigationLink { WellScoreView() } label: {
                    DashboardTile(systemImage: DS.Icon.test, title: String(localized: "Latest test"),
                                  value: latest.date.formatted(date: .abbreviated, time: .omitted),
                                  caption: latest.labName.isEmpty ? latest.testMethod.label : latest.labName)
                }
                .buttonStyle(DS.PressableCardStyle())
            }
            NavigationLink { FiltersView() } label: {
                if let soonest = snapshot.filtersByDue.first {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Label(String(localized: "Filters"), systemImage: DS.Icon.filter(.underSinkFilter))
                            .font(DS.Typography.caption)
                            .textCase(.uppercase)
                            .foregroundStyle(DS.Colors.textSecondary)
                        HStack(spacing: DS.Space.m) {
                            FilterLifeRing(daysLeft: soonest.days,
                                           totalDays: soonest.filter.lifeMonths.map { $0 * 30 })
                            Text(soonest.filter.name)
                                .font(DS.Typography.subheadline)
                                .foregroundStyle(DS.Colors.textPrimary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .dsCard(padding: DS.Space.m)
                } else {
                    DashboardTile(systemImage: DS.Icon.filter(.underSinkFilter), title: String(localized: "Filters"),
                                  value: String(localized: "None yet"), caption: String(localized: "Add one to see what it removes"))
                }
            }
            .buttonStyle(DS.PressableCardStyle())
            if let due = snapshot.nextTest {
                NavigationLink { ModesView() } label: {
                    DashboardTile(systemImage: "calendar.badge.clock", title: String(localized: "Next test"),
                                  value: due.isOverdue(at: snapshot.now) ? String(localized: "Due now")
                                      : due.due.formatted(date: .abbreviated, time: .omitted),
                                  caption: due.title,
                                  level: due.isOverdue(at: snapshot.now) ? .fair : nil)
                }
                .buttonStyle(DS.PressableCardStyle())
            }
            NavigationLink { HouseholdView() } label: {
                let flagged = snapshot.exposures.values.filter { !$0.flags.isEmpty }.count
                if !snapshot.members.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.s) {
                        Label(String(localized: "Household"), systemImage: "person.2.fill")
                            .font(DS.Typography.caption)
                            .textCase(.uppercase)
                            .foregroundStyle(DS.Colors.textSecondary)
                        HStack(spacing: -DS.Space.s) {
                            ForEach(snapshot.members.prefix(4)) { member in
                                MemberAvatar(member: member,
                                             flagged: !(snapshot.exposures[member.id]?.flags.isEmpty ?? true))
                            }
                        }
                        Text(flagged == 0 ? String(localized: "No risk flags") : String(localized: "\(flagged) with risk flags"))
                            .font(DS.Typography.footnote)
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                    .dsCard(padding: DS.Space.m)
                } else {
                DashboardTile(systemImage: "person.2.fill", title: String(localized: "Household"),
                              value: snapshot.members.isEmpty ? String(localized: "Add people")
                                  : String(localized: "\(snapshot.members.count) people"),
                              caption: snapshot.members.isEmpty ? String(localized: "See risks for each person")
                                  : (flagged == 0 ? String(localized: "No risk flags")
                                                  : String(localized: "\(flagged) with risk flags")),
                              level: flagged > 0 ? .fair : nil)
                }
            }
            .buttonStyle(DS.PressableCardStyle())
            .accessibilityIdentifier("dashboard.household")
        }
    }

    // MARK: Tap rings and source

    private func tapRings(_ snapshot: WaterSnapshot) -> some View {
        let taps = [snapshot.drinking].compactMap { $0 } + Array(snapshot.showers.prefix(1))
            + [snapshot.taps[.wholeHouse]].compactMap { $0 }
        return NavigationLink { TapScoresListView() } label: {
            TapRingsRow(results: taps)
                .dsCard()
        }
        .buttonStyle(DS.PressableCardStyle())
        .accessibilityIdentifier("dashboard.taps")
    }

    /// Small map of the home inside its water system, when the address and a system are known.
    @ViewBuilder
    private var sourceCard: some View {
        if let home = settings.homeLocation {
            VStack(alignment: .leading, spacing: DS.Space.s) {
                SourceMap(location: home, area: sourceArea)
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Corner.medium, style: .continuous))
                Label(settings.waterSourceEstimate?.systemName.map { String(localized: "\(settings.waterSource.choiceTitle) · \($0)") }
                      ?? settings.waterSource.choiceTitle, systemImage: settings.waterSource.symbol)
                    .font(DS.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .dsCard()
            .task(id: settings.waterSourceEstimate?.pwsid) {
                guard let pwsid = settings.waterSourceEstimate?.pwsid else { sourceArea = nil; return }
                sourceArea = await Task.detached { WaterSystemIndex.bundled?.areas.first { $0.pwsid == pwsid } }.value
            }
        }
    }

    // MARK: Next step

    private func nextStep(_ snapshot: WaterSnapshot) -> some View {
        NavigationLink {
            RemediationView()
        } label: {
            HStack(spacing: DS.Space.m) {
                DS.IconBadge(systemImage: "arrow.right.circle.fill")
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    Text("Your next step")
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .textCase(.uppercase)
                    Text(snapshot.topNextStep)
                        .font(DS.Typography.headline)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .dsCard()
        }
        .buttonStyle(DS.PressableCardStyle())
        .accessibilityIdentifier("dashboard.nextStep")
    }
}
