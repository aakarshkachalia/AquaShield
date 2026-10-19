//
//  HomeView.swift
//  ClearWellNC
//
//  Dashboard: the most important things at a glance, and one tap to everything else.
//

import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case home, checkArea, myWater, learn, reminders
}

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
    @Binding var selectedTab: AppTab

    @Environment(TractStore.self) private var store
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.lastServiced) private var systems: [TreatmentSystem]

    @State private var addingResult = false
    @State private var addingFilter = false
    @State private var editingFilter: TreatmentSystem?
    @State private var trends = CountyTrendData.loadBundled()
    @Environment(WellCareStore.self) private var wellCare

    private let tileColumns = [GridItem(.adaptive(minimum: 160), spacing: Spacing.m, alignment: .top)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    header

                    if let latest = results.first, latest.eColi == .present {
                        EColiUrgentCard()
                    }
                    if !alertsStore.relevantAlerts.isEmpty {
                        WeatherAlertsCard(store: alertsStore) {}
                    }
                    if savedWells.isEmpty {
                        setupCard
                    }

                    SectionHeader(title: "At a glance")
                    LazyVGrid(columns: tileColumns, spacing: Spacing.m) {
                        scoreTile
                        lastTestTile
                        nextDueTile
                        if waterSource.showsWellCare, savedWells.first != nil {
                            areaTile
                        }
                    }

                    SectionHeader(title: "Quick actions")
                    LazyVGrid(columns: tileColumns, spacing: Spacing.m) {
                        QuickAction(title: "Add lab result", systemImage: "plus.circle.fill") { addingResult = true }
                        QuickAction(title: "Add filter", systemImage: "line.3.horizontal.decrease.circle.fill") { addingFilter = true }
                        QuickAction(title: "Check an area", systemImage: "magnifyingglass") { selectedTab = .checkArea }
                        NavigationLink {
                            ResourcesView()
                        } label: {
                            QuickActionLabel(title: "Find help nearby", systemImage: "mappin.and.ellipse")
                        }
                        .buttonStyle(.plain)
                    }

                    SectionHeader(title: "Learn your report")
                    ReportQuestCard(latest: results.first, context: wellCareContext)
                    if waterSource.showsWellCare, let challenge = wellCareContext.challenge {
                        SeasonalChallengeCard(challenge: challenge)
                    }
                    WellCareSummaryCard(context: wellCareContext)

                    filtersSection

                    if !waterSource.showsWellCare {
                        CityWaterCard()
                    }

                    NavigationLink {
                        ResourcesView()
                    } label: {
                        NavigationCardLabel(
                            title: Text("Help near you"),
                            subtitle: Text("Testing labs, filter dealers, plumbers and official resources in your area."),
                            systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .readableWidth()
            }
            .background(Color.appBackground)
            .navigationTitle("Home")
            .sheet(isPresented: $addingResult) { LabResultForm() }
            .sheet(isPresented: $addingFilter) { TreatmentForm() }
            .sheet(item: $editingFilter) { TreatmentForm(existing: $0) }
            // Badges can come from tests alone (Steady Keeper, Seasonal Scout), so re-check when tests change.
            .task(id: results.count) {
                wellCare.reload()
                wellCare.refreshBadges(testDates: wellCareContext.testDates, highRiskMonths: wellCareContext.highRiskMonths)
            }
        }
    }

    private var savedCounty: String? {
        savedWells.first.flatMap { store.database?.tract(fips: $0.fips)?.countyName }
    }

    private var wellCareContext: WellCareContext {
        WellCareContext.make(results: results, county: savedCounty, trends: trends)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            if let well = savedWells.first {
                Label(well.placeName, systemImage: "mappin.and.ellipse")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(statusHeadline)
                .font(.title2.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            WaterSourceMenu()
        }
    }

    /// One-line summary of where things stand, most urgent first.
    private var statusHeadline: String {
        if results.first?.eColi == .present { return String(localized: "Don't drink your water until it's treated") }
        if let latest = results.first, latest.aboveLimitCount > 0 { return String(localized: "Your last test needs attention") }
        if !overdueItems.isEmpty { return String(localized: "You have reminders overdue") }
        if results.isEmpty { return String(localized: "Let's get your water tested") }
        return String(localized: "Your water is on track")
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(alignment: .top, spacing: Spacing.m) {
                IconTile(systemImage: "house.fill")
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Add your home")
                        .font(.headline)
                    Text("Check your area and save it to see local risks, weather alerts and help near you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                selectedTab = .checkArea
            } label: {
                Text("Check my area")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: Radius.inner))
        }
        .card()
    }

    // MARK: Tiles

    private var scoreTile: some View {
        let result = WellHealthScore.compute(results.latestScoreInput)
        return NavigationLink {
            WellScoreView()
        } label: {
            DashboardTile(title: waterSource.scoreTitle, systemImage: "gauge.with.needle") {
                HStack(spacing: Spacing.m) {
                    ScoreNumber(result: result, size: .compact)
                    if let band = result.band {
                        Text(band.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(band.tier.color)
                    } else {
                        Text("Add a test to see it")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var lastTestTile: some View {
        Button {
            selectedTab = .myWater
        } label: {
            DashboardTile(title: String(localized: "Last test"), systemImage: "testtube.2") {
                if let latest = results.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(latest.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.title3.bold())
                        let above = latest.aboveLimitCount
                        Label {
                            Text(above == 0 ? String(localized: "No health limits exceeded")
                                            : String(localized: "\(above) above a limit"))
                        } icon: {
                            Image(systemName: above == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(above == 0 ? Color.statusSafe : Color.statusAbove)
                        }
                        .font(.subheadline)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("None yet").font(.title3.bold())
                        Text("Add your lab report").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var nextDueTile: some View {
        Button {
            selectedTab = .reminders
        } label: {
            DashboardTile(title: String(localized: "Next reminder"), systemImage: "bell.fill") {
                if let next = dueItems.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(next.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(next.dueText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(next.days < 0 ? Color.statusAbove : Color.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing due").font(.title3.bold())
                        Text("Add a filter to get reminders").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var areaTile: some View {
        if let well = savedWells.first, let db = store.database, let tract = db.tract(fips: well.fips) {
            let report = RiskEngine.report(for: tract, meta: db.meta)
            let flagged = report.risks.filter { $0.level == .high || $0.level == .elevated }
            NavigationLink {
                ReportView(selection: AreaSelection(
                    tract: tract,
                    coordinate: .init(latitude: well.latitude, longitude: well.longitude),
                    placeName: well.placeName), meta: db.meta)
            } label: {
                DashboardTile(title: String(localized: "Area risk"), systemImage: "map.fill") {
                    VStack(alignment: .leading, spacing: 2) {
                        if flagged.isEmpty {
                            Text("Nothing above typical").font(.headline)
                        } else {
                            Text(flagged.prefix(3).map(\.contaminant.name).formatted(.list(type: .and)))
                                .font(.headline)
                                .lineLimit(2)
                            Text("Higher than typical here")
                                .font(.subheadline)
                                .foregroundStyle(Color.statusWatch)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Filters

    private var filtersSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                SectionHeader(title: "My filters")
                Spacer()
                Button {
                    addingFilter = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                }
                .accessibilityLabel(Text("Add filter"))
            }
            if systems.isEmpty {
                Text("Track your pitcher, faucet, fridge or whole-house filter and we'll remind you when it's time to replace it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(systems.sorted { $0.dueDate < $1.dueDate }) { system in
                        Button {
                            editingFilter = system
                        } label: {
                            FilterRow(system: system)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Edit or delete this filter"))
                        if system.persistentModelID != systems.max(by: { $0.dueDate < $1.dueDate })?.persistentModelID {
                            Divider()
                        }
                    }
                }
                .card()
            }
        }
    }

    // MARK: Due items

    private struct DueItem {
        let title: String
        let days: Int
        let dueText: String
    }

    private var dueItems: [DueItem] {
        var items = systems.map { system in
            let days = DueText.daysRemaining(until: system.dueDate)
            return DueItem(title: system.displayName, days: days,
                           dueText: DueText.text(daysRemaining: days, isCheck: system.kind.isCheck))
        }
        if waterSource.showsWellCare {
            items += WellCareTask.allCases.map { task in
                let days = DueText.daysRemaining(until: task.dueDate(results: results))
                return DueItem(title: task.title, days: days, dueText: DueText.careText(daysRemaining: days))
            }
        }
        return items.sorted { $0.days < $1.days }
    }

    private var overdueItems: [DueItem] { dueItems.filter { $0.days < 0 } }
}

// MARK: - Dashboard components

/// Small labeled tile for the "At a glance" grid.
private struct DashboardTile<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            HStack(spacing: Spacing.s) {
                Image(systemName: systemImage)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            content
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
        .contentShape(Rectangle())
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct QuickActionLabel: View {
    let title: LocalizedStringKey
    let systemImage: String

    var body: some View {
        HStack(spacing: Spacing.m) {
            IconTile(systemImage: systemImage)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .card()
    }
}

private struct QuickAction: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            QuickActionLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct FilterRow: View {
    let system: TreatmentSystem

    var body: some View {
        let days = DueText.daysRemaining(until: system.dueDate)
        HStack(spacing: Spacing.m) {
            IconTile(systemImage: system.kind.symbol, color: days < 0 ? .statusAbove : .accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(system.displayName)
                    .font(.body.weight(.semibold))
                if let product = system.trimmedProductName {
                    Text(product)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(DueText.text(daysRemaining: days, isCheck: system.kind.isCheck))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(days < 0 ? Color.statusAbove : (days <= 14 ? Color.statusWatch : Color.secondary))
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.s)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
