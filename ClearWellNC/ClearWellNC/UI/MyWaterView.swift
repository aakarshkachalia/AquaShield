//
//  MyWaterView.swift
//  ClearWellNC
//
//  Latest report (score + every reading), report history, and trend/forecast charts.
//  Tapping a reading opens its detail page.
//

import CoreLocation
import SwiftData
import SwiftUI

struct MyWaterView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(TractStore.self) private var store
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    private var waterSource: WaterSource { settings.waterSource }

    @State private var editingResult: LabResult?
    @State private var confirmingRemove = false
    @State private var questSession: QuestSession?

    private var county: String? {
        settings.effectiveCounty(savedWellCounty: savedWellCounty(savedWells, store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    PrimaryButton(title: "Scan Report", systemImage: "doc.viewfinder") { router.showingScanner = true }

                    if let latest = results.first {
                        if latest.eColi == .present { EColiUrgentCard() }
                        latestReport(latest)
                        history
                        trends
                    } else {
                        EmptyStateView(systemImage: "doc.text.magnifyingglass",
                                       title: "No reports yet",
                                       message: "Scan your lab report or enter the numbers by hand. ClearWell explains every result in plain English.",
                                       actionTitle: "Scan Report") { router.showingScanner = true }
                    }

                    more
                }
                .screenContainer()
            }
            .background(Color.appBackground)
            .navigationTitle("My Water")
            .refreshable { await refreshAlerts() }
            .toolbar {
                if savedWells.first != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Remove saved location", systemImage: "trash", role: .destructive) {
                                confirmingRemove = true
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis.circle")
                        }
                    }
                }
            }
            .confirmationDialog("Remove saved location?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove saved location", role: .destructive, action: removeSavedWell)
            } message: {
                Text("Your lab results are kept.")
            }
            .fullScreenCover(item: $questSession) { session in
                ReportQuestView(report: session.report,
                                context: WellCareContext.make(results: results, county: county,
                                                              trends: CountyTrendData.loadBundled()))
            }
            .sheet(item: $editingResult) { LabResultForm(existing: $0) }
        }
    }

    // MARK: Latest report

    private func latestReport(_ latest: LabResult) -> some View {
        let report = QuestReport(result: latest)
        let readings = latest.displayInterpretations
        let score = WellHealthScore.compute(results.latestScoreInput)
        return VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Latest report",
                          subtitle: subtitle(for: latest))

            NavigationLink {
                WellScoreView()
            } label: {
                HStack(spacing: Spacing.l) {
                    ScoreRing(result: score, diameter: 88)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(waterSource.scoreTitle).font(.headline)
                        if let band = score.band {
                            StatusChip(tier: band.tier, label: band.label)
                        }
                        if !score.isComplete {
                            Text(incompleteText(score))
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.textPrimary)
                .contentShape(Rectangle())
                .card()
                .accessibilityElement(children: .combine)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(readings.enumerated()), id: \.offset) { index, interpretation in
                    NavigationLink {
                        ContaminantDetailView(id: interpretation.id)
                    } label: {
                        ContaminantRow(name: interpretation.id.info.name, interpretation: interpretation)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Opens details, trend and what to do"))
                    if index < readings.count - 1 { Divider() }
                }
            }
            .card()

            Button {
                questSession = QuestSession(report: report.markingSample(settings.demoEnabled))
            } label: {
                NavigationCardLabel(title: Text("Play Report Quest"),
                                    subtitle: Text("Learn to read this report in about 3 minutes."),
                                    systemImage: "map.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func subtitle(for result: LabResult) -> String {
        let date = result.date.formatted(date: .long, time: .omitted)
        return result.labName.isEmpty ? date : "\(date) · \(result.labName)"
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Report history")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(results) { result in
                    Button {
                        editingResult = result
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.headline)
                                let findings = result.healthFindings.count
                                Label {
                                    Text(findings == 0 ? String(localized: "No health limits exceeded")
                                                       : String(localized: "\(findings) above a health limit"))
                                } icon: {
                                    let tier: Interpretation.Tier = findings == 0 ? .safe : .above
                                    Image(systemName: tier.symbol).foregroundStyle(tier.color)
                                }
                                .font(.subheadline)
                                .foregroundStyle(Color.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Color.textPrimary)
                        .frame(minHeight: TapTarget.minimum)
                        .padding(.vertical, Spacing.s)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(Text("Edit or delete this report"))
                    if result.persistentModelID != results.last?.persistentModelID { Divider() }
                }
            }
            .card()
        }
    }

    // MARK: Trends

    private var chartedAnalytes: [Analyte] {
        Analyte.allCases.filter { a in results.contains { $0.value(for: a) != nil } }
    }

    private var trends: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Trends & forecast")
            NavigationLink {
                SeasonalOutlookView(initialCounty: county)
            } label: {
                NavigationCardLabel(title: Text("Seasonal outlook"),
                                    subtitle: Text("When levels in your county usually rise or fall, and what to expect next."),
                                    systemImage: "chart.line.uptrend.xyaxis")
            }
            .buttonStyle(.plain)
            ForEach(chartedAnalytes) { analyte in
                TrendChart(analyte: analyte, results: results)
            }
            if !chartedAnalytes.isEmpty {
                Text("Triangles mark results above the limit. Dashed lines show limits.")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    // MARK: More

    @ViewBuilder
    private var more: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "More")
            if !systemsNeedingRetest.isEmpty {
                RetestReminderCard(systems: systemsNeedingRetest)
            }
            if savedWells.first != nil {
                WeatherAlertsCard(store: alertsStore) { Task { await refreshAlerts() } }
            }
            if !waterSource.showsWellCare {
                CityWaterCard()
            }
            NavigationLink {
                RemindersView()
                    .navigationTitle("Filters & reminders")
            } label: {
                NavigationCardLabel(title: Text("Filters & reminders"),
                                    subtitle: Text("Track filters and get reminders for well care and retests."),
                                    systemImage: "bell.fill")
            }
            .buttonStyle(.plain)
            if let well = savedWells.first, let db = store.database, let tract = db.tract(fips: well.fips) {
                NavigationLink {
                    ReportView(selection: AreaSelection(
                        tract: tract,
                        coordinate: CLLocationCoordinate2D(latitude: well.latitude, longitude: well.longitude),
                        placeName: well.placeName), meta: db.meta)
                } label: {
                    NavigationCardLabel(title: Text("My area's well risk"),
                                        subtitle: Text("Estimates for wells near \(well.placeName)."),
                                        systemImage: "map.fill")
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Systems logged after the most recent lab test date.
    private var systemsNeedingRetest: [TreatmentSystem] {
        let latestTest = results.first?.date
        return systems.filter { system in
            guard let latestTest else { return true }
            return Calendar.current.startOfDay(for: latestTest) < Calendar.current.startOfDay(for: system.addedAt)
        }
    }

    private func removeSavedWell() {
        guard let well = savedWells.first else { return }
        modelContext.delete(well)
        try? modelContext.save()
    }

    private func refreshAlerts() async {
        guard let well = savedWells.first else { return }
        await alertsStore.refresh(latitude: well.latitude, longitude: well.longitude)
    }
}

/// One contaminant: value vs. limit, what it means, its trend, and a link to its Learn card.
struct ContaminantDetailView: View {
    let id: ContaminantID

    @Environment(AppRouter.self) private var router
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]

    private var analyte: Analyte? { Analyte.allCases.first { $0.contaminant == id } }

    /// Latest reading of this contaminant across all reports.
    private var latest: (interpretation: Interpretation, date: Date)? {
        for result in results {
            if let analyte, let value = result.value(for: analyte) {
                if let limit = result.nonDetects[analyte] {
                    return (Interpretation.interpretNonDetect(id, detectionLimit: limit), result.date)
                }
                return (Interpretation.interpret(id, value: value), result.date)
            }
            if id == .totalColiform, let c = result.totalColiform { return (.interpret(id, present: c == .present), result.date) }
            if id == .eColi, let e = result.eColi { return (.interpret(id, present: e == .present), result.date) }
        }
        return nil
    }

    var body: some View {
        let info = id.info
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let latest {
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        InterpretationBlock(name: info.name, interpretation: latest.interpretation)
                        Text("Tested \(latest.date.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .card()

                    InfoCard(systemImage: "lightbulb.fill", title: String(localized: "What it means"),
                             message: info.plainSummary) {
                        if !info.sensitiveGroups.isEmpty {
                            Text("Most at risk: \(info.sensitiveGroups.map(\.label).formatted(.list(type: .and)))")
                                .font(.subheadline)
                        }
                    }

                    InfoCard(style: .status(latest.interpretation.tier), systemImage: "arrow.right.circle.fill",
                             title: String(localized: "What to do"), message: latest.interpretation.nextAction) {
                        if latest.interpretation.isHealthExceedance {
                            PrimaryButton(title: "Get help paying for a fix", systemImage: "dollarsign.circle") {
                                router.openHelp(.contaminant(id))
                            }
                        }
                    }
                } else {
                    EmptyStateView(systemImage: "testtube.2", title: "No results for this yet",
                                   message: "Add a lab report that includes this test.")
                }

                if let analyte, results.contains(where: { $0.value(for: analyte) != nil }) {
                    TrendChart(analyte: analyte, results: results)
                }

                if let article = LearnLibrary.article(for: id) {
                    NavigationLink {
                        LearnArticleView(article: article)
                    } label: {
                        NavigationCardLabel(title: Text("Learn about \(article.title.lowercased())"),
                                            subtitle: Text("Where it comes from, health effects, treatment and a quick quiz."),
                                            systemImage: article.symbol)
                    }
                    .buttonStyle(.plain)
                }

                DisclaimerFooter()
            }
            .screenContainer()
        }
        .background(Color.appBackground)
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
