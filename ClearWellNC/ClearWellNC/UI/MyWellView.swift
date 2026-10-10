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

    @State private var addingResult = false
    @State private var editingResult: LabResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let latest = results.first, latest.eColi == .present {
                        EColiUrgentCard()
                    }
                    if savedWells.first != nil {
                        WeatherAlertsCard(store: alertsStore) {
                            Task { await refreshAlerts() }
                        }
                    }
                    if !systemsNeedingRetest.isEmpty {
                        RetestReminderCard(systems: systemsNeedingRetest)
                    }

                    locationSection

                    wellRecordHeader
                    if let latest = results.first {
                        LatestResultCard(result: latest)
                        ForEach(chartedAnalytes) { analyte in
                            TrendChart(analyte: analyte, results: results)
                        }
                        if !chartedAnalytes.isEmpty {
                            Text("Triangles mark results above the limit. Dashed lines show limits.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        pastResults
                    } else {
                        emptyRecord
                    }
                }
                .padding()
                .readableWidth()
            }
            .background(Color.appBackground)
            .refreshable { await refreshAlerts() }
            .navigationTitle("My Well")
            .sheet(isPresented: $addingResult) { LabResultForm() }
            .sheet(item: $editingResult) { LabResultForm(existing: $0) }
        }
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
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(well.placeName)
                        .font(.title2.bold())
                    if let tract = store.database?.tract(fips: well.fips), let county = tract.countyName {
                        Text("\(county) County")
                            .foregroundStyle(.secondary)
                    }
                    Text("Census tract \(well.fips)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive) {
                    modelContext.delete(well)
                    try? modelContext.save()
                } label: {
                    Label("Remove saved location", systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
            .card()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Label("No location saved", systemImage: "mappin.slash")
                    .font(.headline)
                Text("Check your area, then tap Save as My Well on the report. Your lab results below are kept either way.")
                    .foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private var wellRecordHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                recordTitle
                Spacer()
                addButton
            }
            VStack(alignment: .leading, spacing: 8) {
                recordTitle
                addButton
            }
        }
        .padding(.top, 8)
    }

    private var recordTitle: some View {
        Text("Well Record")
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
    }

    private var addButton: some View {
        Button {
            addingResult = true
        } label: {
            Label("Add lab result", systemImage: "plus")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    private var emptyRecord: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No lab results yet")
                .font(.headline)
            Text("When you get your lab report, add the numbers here to compare them with the limits and track them over time.")
                .foregroundStyle(.secondary)
        }
        .card()
    }

    private var pastResults: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("All results")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)
            ForEach(results) { result in
                Button {
                    editingResult = result
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
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
        var aboveCount = Analyte.allCases.filter { a in
            result.value(for: a).map { a.evaluate($0).kind == .above } ?? false
        }.count
        if result.totalColiform == .present { aboveCount += 1 }
        if result.eColi == .present { aboveCount += 1 }
        let lab = result.labName.isEmpty ? nil : result.labName
        let status = aboveCount == 0
            ? String(localized: "No health limits exceeded")
            : String(localized: "\(aboveCount) above a limit")
        return [lab, status].compactMap { $0 }.joined(separator: " · ")
    }
}
