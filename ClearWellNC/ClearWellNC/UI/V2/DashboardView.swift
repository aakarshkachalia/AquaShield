//
//  DashboardView.swift
//  ClearWellNC
//
//  Home, in the ClearWell Redesign's Modernist style (Claude Design, 4a): source chip and settings, an
//  expandable alert bar, a dial gauge for the score, three thin metrics, every contaminant on one
//  "× of limit" log scale, and four flat tiles.
//

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    enum Route: Hashable {
        case score, taps, filters, findTesting, modes, household, remediation, contaminant(ContaminantID)
    }

    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Environment(WellCareStore.self) private var wellCare
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var trends = CountyTrendData.loadBundled()
    @State private var countyData = CountyWellData.loadBundled()
    @State private var path: [Route] = []
    @State private var alertsOpen = false
    @State private var showingSource = false
    @State private var sourceArea: WaterSystemArea?

    private var snapshot: WaterSnapshot {
        _ = settings.scopedRevision
        return WaterSnapshot.make(results: results, systems: systems, settings: settings)
    }

    private var wellCareContext: WellCareContext {
        WellCareContext.make(results: results, county: settings.county, trends: trends)
    }

    private func appAlerts(_ snapshot: WaterSnapshot) -> [AppAlert] {
        let weather = settings.isOptedIn(.stormAlerts) ? alertsStore.relevantAlerts.map(\.event) : []
        return AlertCenter.alerts(.from(snapshot, weatherEvents: weather, modes: settings.activeModes))
            .filter { $0.severity > .info }
    }

    var body: some View {
        let snapshot = snapshot
        let alerts = appAlerts(snapshot)
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(snapshot)
                    if !alerts.isEmpty {
                        alertBar(alerts, drinking: snapshot.drinking)
                            .padding(.horizontal, 16)
                    }
                    if snapshot.hasReadings, let drinking = snapshot.drinking {
                        Button { path.append(.score) } label: { DialGauge(score: drinking.score, worst: worst(drinking)) }
                            .buttonStyle(.plain)
                            .padding(.top, 14)
                            .accessibilityIdentifier("dashboard.score")
                        metrics(drinking, snapshot: snapshot)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                        contaminants(drinking, snapshot: snapshot)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    } else {
                        empty(snapshot)
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                    }
                    tiles(snapshot)
                        .padding(.horizontal, 16)
                        .padding(.top, 22)
                    M.Footer(sample: countyData?.sample == true || trends?.isSample == true)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: DS.Size.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .modernistScreen()
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .score: TapScoreView(tap: .kitchen)
                case .taps: TapScoresListView()
                case .filters: FiltersView()
                case .findTesting: FindTestingView()
                case .modes: ModesView()
                case .household: HouseholdView()
                case .remediation: RemediationView()
                case .contaminant(let id): ContaminantDetailView(id: id)
                }
            }
            .navigationDestination(isPresented: Bindable(router).showingHousehold) { HouseholdView() }
            .sheet(isPresented: $showingSource) { sourceSheet }
            .task(id: results.count) {
                guard !settings.demoEnabled else { return }
                wellCare.reload()
                wellCare.refreshBadges(testDates: wellCareContext.testDates, highRiskMonths: wellCareContext.highRiskMonths)
            }
            .task(id: settings.waterSourceEstimate?.pwsid) {
                guard let pwsid = settings.waterSourceEstimate?.pwsid else { sourceArea = nil; return }
                sourceArea = await Task.detached { WaterSystemIndex.bundled?.areas.first { $0.pwsid == pwsid } }.value
            }
        }
    }

    private func perform(_ action: AppAlert.Action) {
        switch action {
        case .safety, .remediation: path.append(.remediation)
        case .weather: router.selectedTab = .myWater
        case .filters: path.append(.filters)
        case .testing, .findTesting: path.append(.findTesting)
        case .modes: path.append(.modes)
        }
    }

    /// The reading furthest over (or closest to) its limit.
    private func worst(_ drinking: TapScoreResult) -> (name: String, ratio: Double)? {
        drinking.items.compactMap { item in item.ratio.map { (item.target.name, $0) } }.max { $0.1 < $1.1 }
    }

    // MARK: Header

    private func header(_ snapshot: WaterSnapshot) -> some View {
        HStack {
            Button { showingSource = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.source.hasUtility && !snapshot.source.hasWell ? "building.2" : "drop")
                        .font(.system(.footnote, weight: .light))
                    Text(sourceLine(snapshot)).font(.system(.footnote, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(.caption2, weight: .light))
                }
                .frame(minHeight: DS.Size.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows your water source on a map"))
            Spacer()
            NavigationLink { SettingsView() } label: {
                Image(systemName: "gearshape").font(.system(.title3, weight: .light))
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Settings"))
            .accessibilityIdentifier("dashboard.settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func sourceLine(_ snapshot: WaterSnapshot) -> String {
        var parts = [snapshot.source.settingName]
        if snapshot.source.hasUtility, let system = settings.waterSourceEstimate?.systemName { parts.append(system) }
        else if let county = settings.county { parts.append(String(localized: "\(county) Co.")) }
        return parts.joined(separator: " · ")
    }

    private var sourceSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let home = settings.homeLocation {
                    SourceMap(location: home, area: sourceArea).frame(height: 260)
                    Text(home.address).font(M.Font.row).foregroundStyle(M.Colors.muted)
                }
                Text(settings.waterSource.choiceTitle).font(M.Font.screenTitle)
                if let estimate = settings.waterSourceEstimate, estimate.kind != .unknown {
                    Text(estimate.headline).font(M.Font.row).foregroundStyle(M.Colors.muted)
                }
                Spacer()
            }
            .padding(20)
            .modernistScreen()
            .navigationTitle("Your water source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSource = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Alert bar

    private func alertBar(_ alerts: [AppAlert], drinking: TapScoreResult?) -> some View {
        let top = alerts[0]
        let worstItem = drinking.flatMap(worst)
        let red = top.severity == .critical
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.5, bounce: 0.1)) { alertsOpen.toggle() }
                DS.Haptics.selection()
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: red ? "exclamationmark.triangle" : top.symbol)
                            .font(.system(.body, weight: .light))
                            .foregroundStyle(red ? M.Colors.over : M.Colors.ink)
                        if red, let worstItem, worstItem.ratio >= 1 {
                            Text(worstItem.name).font(M.Font.section)
                            Text(M.times(worstItem.ratio)).font(M.Font.section.monospacedDigit()).foregroundStyle(M.Colors.overText)
                        } else {
                            Text(top.title).font(M.Font.section).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(alerts.count == 1 ? String(localized: "1 alert") : String(localized: "\(alerts.count) alerts"))
                            .font(M.Font.label).foregroundStyle(M.Colors.muted)
                        Image(systemName: "chevron.down").font(.system(.footnote, weight: .light))
                            .rotationEffect(.degrees(alertsOpen ? 180 : 0))
                    }
                    if let worstItem {
                        M.LimitTrack(ratio: worstItem.ratio, dotColor: M.Zone(ratio: worstItem.ratio).color)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Rectangle().fill(M.Colors.ink).frame(width: 1, height: 10)
                                        .offset(x: geo.size.width * M.limitPosition, y: 2)
                                }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(alerts.count) alerts. \(top.title)"))
            .accessibilityHint(Text(alertsOpen ? "Hides alerts" : "Shows alerts"))
            .accessibilityIdentifier("dashboard.alerts")

            if alertsOpen {
                ForEach(Array(alerts.enumerated()), id: \.element.id) { index, alert in
                    M.Rule(color: M.Colors.line)
                    HStack(spacing: 12) {
                        if index > 0 || !red {
                            Image(systemName: alert.symbol).font(.system(.footnote, weight: .light)).frame(width: 18)
                                .accessibilityHidden(true)
                        }
                        Text(index == 0 && red ? alert.detail : alert.title)
                            .font(M.Font.row)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        if index == 0 {
                            Button("\(alert.actionTitle) →") { perform(alert.action) }
                                .buttonStyle(M.InkButtonStyle())
                                .accessibilityIdentifier("dashboard.nextStep")
                        } else {
                            Button(alert.actionTitle) { perform(alert.action) }
                                .buttonStyle(M.OutlineButtonStyle())
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .background(M.Colors.surface)
        .onAppear { if red { DS.Haptics.warning() } }
    }

    // MARK: Metrics

    private func metrics(_ drinking: TapScoreResult, snapshot: WaterSnapshot) -> some View {
        let recommended = WellHealthScore.recommendedTargets(for: snapshot.source, isShower: false)
        let done = recommended.count - drinking.missingTests.count
        let shower = snapshot.showers.first?.score
        return VStack(spacing: 0) {
            M.Rule()
            HStack(spacing: 0) {
                metric(symbol: "drop", value: "\(drinking.score)", outOf: "/100", label: String(localized: "Drinking water"),
                       bar: Double(drinking.score) / 100, color: M.scoreColor(Double(drinking.score)))
                Rectangle().fill(M.Colors.line).frame(width: 1)
                metric(symbol: "shower", value: shower.map(String.init) ?? "—", outOf: shower == nil ? nil : "/100",
                       label: String(localized: "Shower water"),
                       bar: Double(shower ?? 0) / 100, color: M.scoreColor(Double(shower ?? 0)))
                Rectangle().fill(M.Colors.line).frame(width: 1)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "testtube.2").font(.system(.title3, weight: .ultraLight)).accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(done)").font(M.Font.number)
                        Text("/\(recommended.count)").font(M.Font.row).foregroundStyle(M.Colors.muted)
                    }
                    HStack(spacing: 3) {
                        ForEach(0..<recommended.count, id: \.self) { i in
                            Rectangle().fill(i < done ? M.Colors.ink : M.Colors.line).frame(height: 2)
                        }
                    }
                    Text("Key tests done").font(M.Font.tiny).foregroundStyle(M.Colors.muted)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(done) of \(recommended.count) key tests done"))
            }
            .fixedSize(horizontal: false, vertical: true)
            M.Rule()
        }
    }

    private func metric(symbol: String, value: String, outOf: String?, label: String, bar: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol).font(.system(.title3, weight: .ultraLight)).accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value).font(M.Font.number)
                if let outOf { Text(outOf).font(M.Font.row).foregroundStyle(M.Colors.muted) }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(M.Colors.line)
                    Rectangle().fill(color).frame(width: geo.size.width * min(max(bar, 0), 1))
                }
            }
            .frame(height: 2)
            Text(label).font(M.Font.tiny).foregroundStyle(M.Colors.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label) score \(value) out of 100"))
    }

    // MARK: Contaminants

    private struct Row: Identifiable {
        let id: ClaimTarget
        let name: String
        let ratio: Double?
        let countyRatio: Double?
    }

    private func rows(_ drinking: TapScoreResult, snapshot: WaterSnapshot) -> [Row] {
        var rows: [Row] = drinking.items.compactMap { item in
            guard let ratio = item.ratio else { return nil }
            return Row(id: item.target, name: item.target.name, ratio: ratio, countyRatio: countyRatio(item.target))
        }
        rows.sort { ($0.ratio ?? 0) > ($1.ratio ?? 0) }
        for target in drinking.missingTests where !rows.contains(where: { $0.id == target }) {
            rows.append(Row(id: target, name: target.name, ratio: nil, countyRatio: nil))
        }
        return rows
    }

    /// The county's mean as a multiple of the limit (sample data until real county data is added).
    private func countyRatio(_ target: ClaimTarget) -> Double? {
        guard let county = settings.county, let id = target.contaminantID,
              let record = countyData?.reportable(for: county).first(where: { $0.contaminantID == id }),
              let limit = TargetLimit.limit(for: target), limit.value > 0 else { return nil }
        let unit = ReadingUnit(rawValue: record.unit.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: "µg", with: "ug"))
            ?? ReadingUnit.allCases.first { $0.label == record.unit }
        let value = unit.flatMap { ReadingUnit.convert(record.meanConcentration, from: $0, to: ReadingUnit.canonical(for: target)) }
            ?? record.meanConcentration
        return value / limit.value
    }

    private func contaminants(_ drinking: TapScoreResult, snapshot: WaterSnapshot) -> some View {
        let rows = rows(drinking, snapshot: snapshot)
        return VStack(alignment: .leading, spacing: 10) {
            M.SectionHeader(title: String(localized: "Contaminants"), note: String(localized: "× of safe limit · log scale"))
            HStack(spacing: 14) {
                ForEach(M.Zone.allCases, id: \.self) { zone in
                    HStack(spacing: 5) { M.Dot(color: zone.color); Text(zone.label) }
                }
                if rows.contains(where: { $0.countyRatio != nil }) {
                    HStack(spacing: 5) { Rectangle().fill(M.Colors.ink).frame(width: 1, height: 9); Text("County avg") }
                }
            }
            .font(M.Font.tiny)
            .foregroundStyle(M.Colors.muted)
            .accessibilityElement(children: .combine)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    Button {
                        if let id = row.id.contaminantID { path.append(.contaminant(id)) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(row.name).font(M.Font.row).frame(width: 84, alignment: .leading).lineLimit(1)
                                .minimumScaleFactor(0.8)
                            M.LimitTrack(ratio: row.ratio, countyRatio: row.countyRatio)
                                .overlay(alignment: .leading) {
                                    GeometryReader { geo in
                                        Rectangle().fill(M.Colors.ink).frame(width: 1)
                                            .offset(x: geo.size.width * M.limitPosition)
                                    }
                                }
                            Text(row.ratio.map(M.times) ?? "—")
                                .font(M.Font.value)
                                .foregroundStyle(row.ratio.map { M.Zone(ratio: $0).textColor } ?? M.Colors.muted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: 54, alignment: .trailing)
                        }
                        .frame(minHeight: 40)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(row.name))
                    .accessibilityValue(row.ratio.map { Text("\(M.times($0)) of the limit, \(M.Zone(ratio: $0).label)") }
                                        ?? Text("Not tested"))
                    M.Rule(color: M.Colors.hairline)
                }
                // Axis: positions match the log scale.
                GeometryReader { geo in
                    let trackX: CGFloat = 94, trackW = geo.size.width - 94 - 64
                    ForEach([(0.1, "0.1×"), (1, String(localized: "Limit")), (2.5, "2.5×")], id: \.0) { value, label in
                        Text(label)
                            .font(value == 1 ? M.Font.label : M.Font.tiny)
                            .foregroundStyle(value == 1 ? M.Colors.ink : M.Colors.muted)
                            .fixedSize()
                            .position(x: trackX + trackW * M.logPosition(value), y: 10)
                    }
                }
                .frame(height: 22)
                .accessibilityHidden(true)
            }
        }
    }

    // MARK: Empty

    private func empty(_ snapshot: WaterSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(snapshot.source.hasUtility && !snapshot.source.hasWell
                 ? String(localized: "Add your water report to see your score.")
                 : String(localized: "Test your water to see your score."))
                .font(.system(.title2, weight: .light))
            if snapshot.source.showsCityContent {
                NavigationLink { UtilityReportView() } label: { Text("Add utility report →") }
                    .buttonStyle(M.InkButtonStyle())
            }
            if snapshot.source.showsWellCare {
                Button("Should I test my well? →") { router.showingRiskCheck = true }
                    .buttonStyle(M.OutlineButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(M.Colors.surface)
    }

    // MARK: Tiles

    private func tiles(_ snapshot: WaterSnapshot) -> some View {
        TileGrid(columns: 2, spacing: 8) {
            Button { path.append(.filters) } label: {
                tile(symbol: "line.3.horizontal.decrease", value: snapshot.filtersByDue.first.map { f in
                        f.days.map { $0 <= 0 ? String(localized: "Now") : String(localized: "\($0)d") } ?? f.filter.name
                    } ?? String(localized: "None"),
                     label: String(localized: "Filter")) {
                    if let soonest = snapshot.filtersByDue.first {
                        ProgressRing(fraction: Double(soonest.days ?? 0) / Double((soonest.filter.lifeMonths ?? 6) * 30))
                    } else {
                        dashedPlus
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.filters")

            Button { path.append(.modes) } label: {
                let due = snapshot.nextTest
                let days = due.map { max(0, Calendar.current.dateComponents([.day], from: snapshot.now, to: $0.due).day ?? 0) }
                tile(symbol: "calendar", value: due.map { $0.isOverdue(at: snapshot.now) ? String(localized: "Now") : String(localized: "\(days ?? 0)d") } ?? "—",
                     label: String(localized: "Next test")) {
                    ProgressRing(fraction: 1 - Double(days ?? 0) / 365)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.nextTest")

            Button { path.append(.household) } label: {
                tile(symbol: "person.2", value: snapshot.members.isEmpty ? String(localized: "Add") : "\(snapshot.members.count)",
                     label: String(localized: "Household")) {
                    if snapshot.members.isEmpty {
                        dashedPeople
                    } else {
                        HStack(spacing: -8) {
                            ForEach(snapshot.members.prefix(3)) { member in
                                MemberAvatar(member: member, flagged: !(snapshot.exposures[member.id]?.flags.isEmpty ?? true))
                                    .scaleEffect(0.6)
                                    .frame(width: 26, height: 26)
                            }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.household")

            Button { path.append(.taps) } label: {
                let count = Set(results.map(\.date)).count
                tile(symbol: "chart.line.uptrend.xyaxis",
                     value: count == 1 ? String(localized: "1 test") : String(localized: "\(count) tests"),
                     label: String(localized: "Trend")) {
                    MiniTrend(results: results).frame(width: 44, height: 30)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.taps")
        }
    }

    private func tile<Mini: View>(symbol: String, value: String, label: String, @ViewBuilder mini: () -> Mini) -> some View {
        M.Cell {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: symbol).font(.system(.footnote, weight: .light)).accessibilityHidden(true)
                    Text(value).font(.system(.subheadline, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(label).font(M.Font.tiny).foregroundStyle(M.Colors.muted)
                }
                Spacer(minLength: 0)
                mini().accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var dashedPlus: some View {
        ZStack {
            Circle().stroke(M.Colors.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            Image(systemName: "plus").font(.system(.caption, weight: .light))
        }
        .frame(width: 30, height: 30)
    }

    private var dashedPeople: some View {
        HStack(spacing: -6) {
            ForEach(0..<3, id: \.self) { i in
                Circle().stroke(M.Colors.ink, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .frame(width: i == 2 ? 10 : 14, height: i == 2 ? 10 : 14)
            }
        }
        .frame(width: 30, height: 30)
    }
}

// MARK: - Dial gauge

/// 270° dial: zone-colored ticks lit up to the score, zone labels, and a big thin number out of 100.
struct DialGauge: View {
    let score: Int
    let worst: (name: String, ratio: Double)?

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private let center = CGPoint(x: 150, y: 140)

    private func point(_ degrees: Double, _ radius: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(r), y: center.y - radius * cos(r))
    }

    var body: some View {
        // Read state here, not inside the Canvas closure, so changes redraw the dial.
        let progress = shown
        ZStack {
            Canvas { context, _ in
                for v in stride(from: 0, through: 100, by: 2) {
                    let angle = -135 + Double(v) * 2.7
                    let long = v % 10 == 0
                    var path = Path()
                    path.move(to: point(angle, 112))
                    path.addLine(to: point(angle, long ? 96 : 102))
                    let lit = Double(v) <= progress
                    context.stroke(path, with: .color(M.scoreColor(Double(v)).opacity(lit ? 1 : 0.28)),
                                   lineWidth: long ? 1.6 : 1)
                }
            }
            ForEach([(20.0, String(localized: "UNSAFE")), (50, String(localized: "POOR")),
                     (70, String(localized: "FAIR")), (90, String(localized: "GOOD"))], id: \.0) { value, text in
                let p = point(-135 + value * 2.7, 128)
                Text(text).font(.system(size: 9, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(M.scoreColor(value)).fixedSize()
                    .position(x: p.x, y: p.y - 4)
            }
            Text("0").font(M.Font.tiny).foregroundStyle(M.Colors.muted).position(x: 56, y: 232)
            Text("100").font(M.Font.tiny).foregroundStyle(M.Colors.muted).position(x: 250, y: 232)
            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(score)")
                        .font(M.Font.thin(min(numberSize, 80)))
                        .contentTransition(.numericText())
                    Text("/100").font(M.Font.row).foregroundStyle(M.Colors.muted)
                }
                if let worst, worst.ratio >= 1 {
                    HStack(spacing: 6) {
                        M.Dot(color: M.Colors.over, size: 6)
                        Text("\(worst.name) \(M.times(worst.ratio)) limit")
                    }
                    .font(M.Font.label)
                    .foregroundStyle(M.Colors.overText)
                } else {
                    Text(WellHealthScore.Band.from(score: score).label.uppercased())
                        .font(M.Font.label).tracking(0.8).foregroundStyle(M.scoreColor(Double(score)))
                }
            }
            .position(x: 150, y: 190)
        }
        .frame(width: 300, height: 250)
        .frame(maxWidth: .infinity)
        .onAppear {
            if reduceMotion { shown = Double(score) } else { withAnimation(.spring(duration: 1.6, bounce: 0.05)) { shown = Double(score) } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Water Health Score \(score) out of 100, \(WellHealthScore.Band.from(score: score).label)"))
        .accessibilityValue(worst.flatMap { $0.ratio >= 1 ? Text("\($0.name) is \(M.times($0.ratio)) the limit") : nil } ?? Text(""))
    }
}

/// A thin 30-pt progress ring.
struct ProgressRing: View {
    let fraction: Double
    var body: some View {
        ZStack {
            Circle().stroke(M.Colors.line, lineWidth: 1.5)
            Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(M.Colors.ink, style: StrokeStyle(lineWidth: 1.5))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 30, height: 30)
    }
}

/// The most-tested reading as a tiny line, with its limit dotted in red.
struct MiniTrend: View {
    let results: [LabResult]

    var body: some View {
        let series = Analyte.allCases
            .map { analyte in (analyte, results.compactMap { r in r.value(for: analyte).map { (r.date, $0) } }.sorted { $0.0 < $1.0 }) }
            .max { $0.1.count < $1.1.count }
        Canvas { context, size in
            var base = Path(); base.move(to: CGPoint(x: 2, y: size.height - 8)); base.addLine(to: CGPoint(x: size.width - 2, y: size.height - 8))
            context.stroke(base, with: .color(M.Colors.line), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            guard let series, let limitValue = { if case .maximum(let m) = series.0.info.limit { m } else { nil } }() else { return }
            let values = series.1.map(\.1)
            let top = max(values.max() ?? 0, limitValue) * 1.1
            let y: (Double) -> CGFloat = { size.height - 4 - CGFloat($0 / top) * (size.height - 8) }
            var limit = Path(); limit.move(to: CGPoint(x: 2, y: y(limitValue))); limit.addLine(to: CGPoint(x: size.width - 2, y: y(limitValue)))
            context.stroke(limit, with: .color(M.Colors.over), style: StrokeStyle(lineWidth: 0.75, dash: [1, 2]))
            let xs = values.indices.map { values.count == 1 ? size.width - 6 : 4 + CGFloat($0) / CGFloat(values.count - 1) * (size.width - 10) }
            if values.count > 1 {
                var line = Path()
                for (i, v) in values.enumerated() { i == 0 ? line.move(to: CGPoint(x: xs[i], y: y(v))) : line.addLine(to: CGPoint(x: xs[i], y: y(v))) }
                context.stroke(line, with: .color(M.Colors.ink), lineWidth: 1)
            }
            if let last = values.last {
                let p = CGPoint(x: xs.last ?? 0, y: y(last))
                context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
                             with: .color(last >= limitValue ? M.Colors.over : M.Colors.ink))
            }
        }
    }
}
