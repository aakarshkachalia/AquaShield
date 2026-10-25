//
//  MyWaterView.swift
//  AquaShield
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
    @State private var section = Pane.latest

    private enum Pane: CaseIterable, Identifiable {
        case latest, history, trends
        var id: Self { self }
        var title: String {
            switch self {
            case .latest: String(localized: "Latest")
            case .history: String(localized: "History")
            case .trends: String(localized: "Trends")
            }
        }
    }

    private var county: String? {
        settings.effectiveCounty(savedWellCounty: savedWellCounty(savedWells, store: store))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    M.UnderlineTabs(tabs: Pane.allCases.map { ($0, $0.title) }, selection: $section)
                        .padding(.horizontal, 20)
                    if let latest = results.first {
                        if latest.eColi == .present { EColiUrgentCard().padding(.horizontal, 16).padding(.top, 16) }
                        switch section {
                        case .latest: latestList(latest).padding(.horizontal, 20)
                        case .history: historyTimeline.padding(.leading, 46).padding(.trailing, 20).padding(.top, 22)
                        case .trends: trendsSection.padding(.horizontal, 20).padding(.top, 22)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Add your lab report and we'll explain every result.")
                                .font(.system(.title3, weight: .light))
                            Button("Scan a report →") { router.showingScanner = true }
                                .buttonStyle(M.InkButtonStyle())
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(M.Colors.surface)
                        .padding(16)
                    }
                    more.padding(.horizontal, 16).padding(.top, 24)
                    M.Footer(sample: section == .trends).padding(.horizontal, 20)
                }
                .frame(maxWidth: DS.Size.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .modernistScreen()
            .toolbarVisibility(.hidden, for: .navigationBar)
            .refreshable { await refreshAlerts() }
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

    // MARK: Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Water").font(M.Font.screenTitle).accessibilityAddTraits(.isHeader)
            Spacer()
            if let latest = results.first {
                Label(subtitle(for: latest), systemImage: "doc.text")
                    .font(M.Font.small).foregroundStyle(M.Colors.muted).lineLimit(1)
            }
            if savedWells.first != nil {
                Menu {
                    Button("Remove saved location", systemImage: "trash", role: .destructive) { confirmingRemove = true }
                } label: {
                    Image(systemName: "ellipsis").frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                }
                .accessibilityLabel(Text("More"))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    // MARK: Latest

    private func subtitle(for result: LabResult) -> String {
        let date = result.date.formatted(date: .abbreviated, time: .omitted)
        return result.labName.isEmpty ? date : "\(date) · \(result.labName)"
    }

    /// Short chemical-style marks for the reading rings.
    static func mark(_ id: ContaminantID) -> String {
        switch id {
        case .arsenic: "As"
        case .lead: "Pb"
        case .nitrate: "NO₃"
        case .nitrite: "NO₂"
        case .uranium: "U"
        case .manganese: "Mn"
        case .iron: "Fe"
        case .copper: "Cu"
        case .fluoride: "F"
        case .totalColiform: "TC"
        case .eColi: "EC"
        case .pH: "pH"
        case .hardness: "H"
        case .radon: "Rn"
        case .pfoa: "PFOA"
        case .pfos: "PFOS"
        case .genx: "GX"
        }
    }

    private func zone(_ interpretation: Interpretation) -> M.Zone {
        if let percent = interpretation.percentOfLimit { return M.Zone(ratio: percent / 100) }
        switch interpretation.tier {
        case .above: return .over
        case .watch, .nuisance: return .watch
        case .safe, .info: return .low
        }
    }

    private func latestList(_ latest: LabResult) -> some View {
        let readings = latest.displayInterpretations
        let score = WellHealthScore.compute(results.latestScoreInput)
        let report = QuestReport(result: latest)
        return VStack(spacing: 0) {
            NavigationLink { WellScoreView() } label: {
                HStack(spacing: 14) {
                    Text(score.score.map(String.init) ?? "—").font(M.Font.thin(40))
                        .foregroundStyle(score.score.map { M.scoreColor(Double($0)) } ?? M.Colors.muted)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(waterSource.scoreTitle).font(M.Font.section)
                        Text(score.isComplete ? String(localized: "All key tests on file") : incompleteText(score))
                            .font(M.Font.small).foregroundStyle(M.Colors.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(.footnote, weight: .light)).foregroundStyle(M.Colors.muted)
                }
                .padding(14)
                .background(M.Colors.surface)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.bottom, 6)
            ForEach(Array(readings.enumerated()), id: \.offset) { _, interpretation in
                NavigationLink { ContaminantDetailView(id: interpretation.id) } label: {
                    readingRow(interpretation)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens details, trend and what to do"))
            }
            Button {
                questSession = QuestSession(report: report.markingSample(settings.demoEnabled))
            } label: {
                HStack {
                    Image(systemName: "map").font(.system(.body, weight: .light))
                    Text("Play Report Quest").font(M.Font.section)
                    Spacer()
                    Text("3 min").font(M.Font.small).foregroundStyle(M.Colors.muted)
                }
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func readingRow(_ interpretation: Interpretation) -> some View {
        let zone = zone(interpretation)
        let fraction = (interpretation.percentOfLimit ?? (interpretation.tier == .above ? 100 : 0)) / 100
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(M.Colors.line, lineWidth: 1.5)
                Circle().trim(from: 0, to: min(max(fraction, 0.02), 1))
                    .stroke(zone.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(Self.mark(interpretation.id))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(zone.textColor)
                    .minimumScaleFactor(0.6)
                    .padding(4)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(interpretation.id.info.name).font(M.Font.row)
                Text(verbatim: "\(interpretation.readingText) · \(interpretation.limitText)")
                    .font(M.Font.small).foregroundStyle(M.Colors.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                M.Dot(color: zone.color, size: 6)
                Text(interpretation.chipLabel)
            }
            .font(M.Font.label)
            .foregroundStyle(zone.textColor)
        }
        .frame(minHeight: 64)
        .overlay(alignment: .bottom) { M.Rule(color: M.Colors.hairline) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: History

    private var historyTimeline: some View {
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(M.Colors.line).frame(width: 1).padding(.top, 6).offset(x: -21)
            VStack(alignment: .leading, spacing: 26) {
                if let next = snapshot.nextTest {
                    let days = max(0, Calendar.current.dateComponents([.day], from: .now, to: next.due).day ?? 0)
                    node(.dashed) {
                        Text(next.isOverdue(at: .now) ? String(localized: "Due now")
                             : String(localized: "\(next.due.formatted(.dateTime.month(.abbreviated).year())) · due in \(days) days"))
                            .font(M.Font.small).foregroundStyle(M.Colors.muted)
                        Text(next.title).font(M.Font.section)
                    }
                }
                ForEach(results) { result in
                    let input = [result].latestScoreInput
                    let score = WellHealthScore.compute(input)
                    let finding = result.healthFindings.first
                    node(finding == nil ? .good : .over) {
                        Text(subtitle(for: result)).font(M.Font.small).foregroundStyle(M.Colors.muted)
                        Button { editingResult = result } label: {
                            HStack(spacing: 16) {
                                Text(score.score.map(String.init) ?? "—").font(M.Font.thin(40))
                                    .foregroundStyle(score.score.map { M.scoreColor(Double($0)) } ?? M.Colors.muted)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("\(score.keyTestsOnFile) of \(score.keyTestsTotal) key tests").font(M.Font.small)
                                    if let finding, let percent = finding.percentOfLimit {
                                        Text("\(finding.id.info.name) \(M.times(percent / 100))")
                                            .font(M.Font.value).foregroundStyle(M.Colors.overText)
                                    } else if finding != nil {
                                        Text(finding!.id.info.name).font(M.Font.value).foregroundStyle(M.Colors.overText)
                                    } else {
                                        Text("No health limits exceeded").font(M.Font.small).foregroundStyle(M.Colors.muted)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .background(M.Colors.surface)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Edit or delete this report"))
                    }
                }
                node(.empty) {
                    Text("Before").font(M.Font.small).foregroundStyle(M.Colors.muted)
                    Button("Scan an old report to add one") { router.showingScanner = true }
                        .font(M.Font.row).buttonStyle(.plain)
                }
            }
        }
    }

    private enum NodeStyle { case dashed, good, over, empty }

    private func node<Content: View>(_ style: NodeStyle, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) { content() }
            .overlay(alignment: .topLeading) {
                Group {
                    switch style {
                    case .dashed: Circle().stroke(M.Colors.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    case .good: Circle().fill(M.Colors.good)
                    case .over: Circle().fill(M.Colors.over)
                    case .empty: Circle().stroke(M.Colors.line, lineWidth: 1)
                    }
                }
                .background(Circle().fill(M.Colors.ground))
                .frame(width: 11, height: 11)
                .offset(x: -26, y: 3)
                .accessibilityHidden(true)
            }
    }

    // MARK: Trends

    @ViewBuilder
    private var trendsSection: some View {
        let focus = trendFocus
        VStack(alignment: .leading, spacing: 0) {
            if let focus, let county {
                CountyTrendChart(contaminant: focus.id, county: county, yours: focus.value)
            }
            if !chartedAnalytes.isEmpty {
                M.SectionHeader(title: String(localized: "Your results over time")).padding(.top, 24)
                ForEach(chartedAnalytes) { analyte in
                    TrendChart(analyte: analyte, results: results).padding(.top, 12)
                }
                Text("Triangles mark results above the limit. Dashed lines show limits.")
                    .font(M.Font.tiny).foregroundStyle(M.Colors.muted).padding(.top, 8)
            }
        }
    }

    /// The reading closest to (or furthest over) its limit, for the county chart.
    private var trendFocus: (id: ContaminantID, value: Double)? {
        guard let latest = results.first else { return nil }
        return latest.displayInterpretations
            .compactMap { i -> (ContaminantID, Double, Double)? in
                guard let p = i.percentOfLimit, let analyte = Analyte.allCases.first(where: { $0.contaminant == i.id }),
                      let v = latest.value(for: analyte) else { return nil }
                return (i.id, p, v)
            }
            .max { $0.1 < $1.1 }
            .map { ($0.0, $0.2) }
    }

    private var chartedAnalytes: [Analyte] {
        Analyte.allCases.filter { a in results.contains { $0.value(for: a) != nil } }
    }

    // MARK: More

    @ViewBuilder
    private var more: some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            Text("MORE").tracking(1).font(DS.Typography.eyebrow).foregroundStyle(DS.Colors.textSecondary)
            if !systemsNeedingRetest.isEmpty {
                RetestReminderCard(systems: systemsNeedingRetest)
            }
            if savedWells.first != nil {
                if settings.isOptedIn(.stormAlerts) {
                    WeatherAlertsCard(store: alertsStore) { Task { await refreshAlerts() } }
                } else {
                    OptInCard(feature: .stormAlerts)
                }
            }
            TileGrid(columns: 2, spacing: DS.Space.m) {
                if waterSource.showsCityContent {
                    NavigationLink { UtilityReportView() } label: {
                        ShortcutTile(title: String(localized: "My water utility"), systemImage: "building.2",
                                     caption: String(localized: "Yearly report"))
                    }
                    .buttonStyle(DS.PressableCardStyle())
                }
                NavigationLink { FiltersView() } label: {
                    ShortcutTile(title: String(localized: "Filters"), systemImage: "line.3.horizontal.decrease.circle",
                                 caption: String(localized: "Life and coverage"))
                }
                .buttonStyle(DS.PressableCardStyle())
                NavigationLink { ModesView() } label: {
                    ShortcutTile(title: String(localized: "Testing and modes"), systemImage: "calendar",
                                 caption: String(localized: "What's due"))
                }
                .buttonStyle(DS.PressableCardStyle())
                NavigationLink { ReportExportView() } label: {
                    ShortcutTile(title: String(localized: "Share a report"), systemImage: "square.and.arrow.up",
                                 caption: String(localized: "PDF"))
                }
                .buttonStyle(DS.PressableCardStyle())
                if waterSource.showsWellCare, let well = savedWells.first, let db = store.database,
                   let tract = db.tract(fips: well.fips) {
                    NavigationLink {
                        ReportView(selection: AreaSelection(
                            tract: tract,
                            coordinate: CLLocationCoordinate2D(latitude: well.latitude, longitude: well.longitude),
                            placeName: well.placeName), meta: db.meta)
                    } label: {
                        ShortcutTile(title: String(localized: "My area's well risk"), systemImage: "map",
                                     caption: well.placeName)
                    }
                    .buttonStyle(DS.PressableCardStyle())
                }
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
        guard let well = savedWells.first, settings.isOptedIn(.stormAlerts) else { return }
        await alertsStore.refresh(latitude: NetworkFeature.coarse(well.latitude),
                                  longitude: NetworkFeature.coarse(well.longitude))
    }
}

