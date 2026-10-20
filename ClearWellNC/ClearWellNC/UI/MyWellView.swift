//
//  MyWellView.swift
//  ClearWellNC
//

import CoreLocation
import SwiftData
import SwiftUI

/// Saved location plus the Well Record of lab results.
struct MyWellView: View {
    @Environment(TractStore.self) private var store
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavedWell.savedAt, order: .reverse) private var savedWells: [SavedWell]
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @AppStorage(StorageKey.waterSource) private var waterSource: WaterSource = .notSure

    @State private var addingResult = false
    @State private var editingResult: LabResult?
    @State private var confirmingRemove = false
    @State private var questSession: QuestSession?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    if let latest = results.first, latest.eColi == .present {
                        EColiUrgentCard()
                    }

                    locationSection

                    if savedWells.first != nil {
                        WeatherAlertsCard(store: alertsStore) {
                            Task { await refreshAlerts() }
                        }
                    }
                    if !systemsNeedingRetest.isEmpty {
                        RetestReminderCard(systems: systemsNeedingRetest)
                    }
                    if !waterSource.showsWellCare {
                        CityWaterCard()
                    }

                    // What the numbers add up to, and when levels tend to change.
                    SectionHeader(title: "Insights")
                    WellScoreCard(result: WellHealthScore.compute(results.latestScoreInput))
                    NavigationLink {
                        SeasonalOutlookView(initialCounty: savedCounty)
                    } label: {
                        NavigationCardLabel(
                            title: Text("Seasonal outlook"),
                            subtitle: Text("When levels in your county usually rise or fall, and what to expect next."),
                            systemImage: "chart.line.uptrend.xyaxis")
                    }
                    .buttonStyle(.plain)

                    wellRecordHeader
                    if let latest = results.first {
                        LatestResultCard(result: latest)
                        Button {
                            questSession = QuestSession(report: QuestReport(result: latest))
                        } label: {
                            NavigationCardLabel(title: Text("Report Quest"),
                                                subtitle: Text("Learn to read this report in about 3 minutes."),
                                                systemImage: "map.fill")
                        }
                        .buttonStyle(.plain)
                        ForEach(chartedAnalytes) { analyte in
                            TrendChart(analyte: analyte, results: results)
                        }
                        if !chartedAnalytes.isEmpty {
                            Text("Triangles mark results above the limit. Dashed lines show limits.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        pastResults
                    } else {
                        emptyRecord
                    }
                }
                .padding(Spacing.l)
                .readableWidth()
            }
            .background(Color.appBackground)
            .refreshable { await refreshAlerts() }
            .navigationTitle(waterSource.homeTitle)
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
                                context: WellCareContext.make(results: results, county: savedCounty,
                                                              trends: CountyTrendData.loadBundled()))
            }
            .sheet(isPresented: $addingResult) { LabResultForm() }
            .sheet(item: $editingResult) { LabResultForm(existing: $0) }
        }
    }

    private var savedCounty: String? {
        savedWells.first.flatMap { store.database?.tract(fips: $0.fips)?.countyName }
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

    // MARK: Derived

    private var chartedAnalytes: [Analyte] {
        Analyte.allCases.filter { a in results.contains { $0.value(for: a) != nil } }
    }

    /// Systems logged after the most recent lab test date.
    private var systemsNeedingRetest: [TreatmentSystem] {
        let latestTest = results.first?.date
        return systems.filter { system in
            guard let latestTest else { return true }
            return Calendar.current.startOfDay(for: latestTest) < Calendar.current.startOfDay(for: system.addedAt)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var locationSection: some View {
        if let well = savedWells.first {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HStack(alignment: .top, spacing: Spacing.m) {
                    IconTile(systemImage: "mappin.and.ellipse")
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(well.placeName)
                            .font(.title2.bold())
                        if let tract = store.database?.tract(fips: well.fips), let county = tract.countyName {
                            Text("\(county) County")
                                .foregroundStyle(.secondary)
                        }
                        Text("Census tract \(well.fips)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                if let db = store.database, let tract = db.tract(fips: well.fips) {
                    NavigationLink {
                        ReportView(selection: AreaSelection(
                            tract: tract,
                            coordinate: CLLocationCoordinate2D(latitude: well.latitude, longitude: well.longitude),
                            placeName: well.placeName), meta: db.meta)
                    } label: {
                        Label("View my area's report", systemImage: "doc.text.magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
            .card()
        } else {
            HStack(alignment: .top, spacing: Spacing.m) {
                IconTile(systemImage: "mappin.slash", color: .secondary)
                VStack(alignment: .leading, spacing: Spacing.s) {
                    Text("No location saved")
                        .font(.headline)
                    Text("Check your area, then tap Save on the report. Your lab results below are kept either way.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
            .accessibilityElement(children: .combine)
        }
    }

    private var wellRecordHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                recordTitle
                Spacer()
                addButton
            }
            VStack(alignment: .leading, spacing: Spacing.s) {
                recordTitle
                addButton
            }
        }
        .padding(.top, Spacing.s)
    }

    private var recordTitle: some View {
        Text(waterSource.recordTitle)
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private var addButton: some View {
        Button {
            addingResult = true
        } label: {
            Label("Add lab result", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(minHeight: 44)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    private var emptyRecord: some View {
        VStack(spacing: Spacing.m) {
            IconTile(systemImage: "testtube.2")
            Text("No lab results yet")
                .font(.headline)
            Text("When you get your lab report, add the numbers here to compare them with the limits and track them over time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.s)
        .card()
        .accessibilityElement(children: .combine)
    }

    private var pastResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("All results")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, Spacing.s)
            ForEach(results) { result in
                Button {
                    editingResult = result
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(result.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.body.weight(.medium))
                            Text(summary(for: result))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Edit or delete this result"))
                if result.persistentModelID != results.last?.persistentModelID {
                    Divider()
                }
            }
        }
        .card()
    }

    private func summary(for result: LabResult) -> String {
        let aboveCount = result.aboveLimitCount
        let lab = result.labName.isEmpty ? nil : result.labName
        let status = aboveCount == 0
            ? String(localized: "No health limits exceeded")
            : String(localized: "\(aboveCount) above a limit")
        return [lab, status].compactMap { $0 }.joined(separator: " · ")
    }
}
