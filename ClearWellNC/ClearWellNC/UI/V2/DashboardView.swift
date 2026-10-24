//
//  DashboardView.swift
//  ClearWellNC
//
//  The landing page. Minimal, glanceable, complete: one score, one verdict, one nudge, one chart of every
//  reading against its limit, four tiles, one next step. A bell with a count opens every alert.
//

import Charts
import SwiftData
import SwiftUI

struct DashboardView: View {
    enum Route: Hashable {
        case score, taps, filters, findTesting, modes, household, remediation
    }

    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Environment(WeatherAlertsStore.self) private var alertsStore
    @Environment(WellCareStore.self) private var wellCare
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var trends = CountyTrendData.loadBundled()
    @State private var path: [Route] = []
    @State private var showingAlerts = false
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
    }

    var body: some View {
        let snapshot = snapshot
        let alerts = appAlerts(snapshot)
        let badge = AlertCenter.badgeCount(alerts)
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.xl) {
                    header(snapshot)
                    if let top = alerts.first(where: { $0.severity >= .attention }) {
                        nudge(top, more: badge - 1)
                    }
                    if snapshot.hasReadings, let drinking = snapshot.drinking {
                        hero(drinking, snapshot: snapshot)
                        atAGlance(drinking)
                    } else {
                        emptyHero(snapshot)
                    }
                    tiles(snapshot)
                    nextStep(snapshot)
                    Text(ExposureRisk.disclaimer)
                        .font(DS.Typography.footnote)
                        .foregroundStyle(DS.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, DS.Space.l)
                .padding(.bottom, DS.Space.xxl)
                .frame(maxWidth: DS.Size.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .background(DS.Colors.background)
            .navigationTitle("Home")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingAlerts = true } label: {
                        Image(systemName: "bell")
                            .overlay(alignment: .topTrailing) {
                                if badge > 0 {
                                    Text("\(badge)")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .frame(minWidth: 18, minHeight: 18)
                                        .background(DS.Colors.unsafe, in: Capsule())
                                        .offset(x: 10, y: -8)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    .accessibilityLabel(Text("Alerts"))
                    .accessibilityValue(Text("\(badge) need attention"))
                    .accessibilityIdentifier("dashboard.alerts")
                    Button("Scan Report", systemImage: "doc.viewfinder") { router.showingScanner = true }
                        .accessibilityIdentifier("dashboard.scan")
                    NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .score: TapScoreView(tap: .kitchen)
                case .taps: TapScoresListView()
                case .filters: FiltersView()
                case .findTesting: FindTestingView()
                case .modes: ModesView()
                case .household: HouseholdView()
                case .remediation: RemediationView()
                }
            }
            .navigationDestination(isPresented: Bindable(router).showingHousehold) { HouseholdView() }
            .sheet(isPresented: $showingAlerts) {
                AlertCenterView(alerts: alerts) { action in
                    showingAlerts = false
                    perform(action)
                }
            }
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

    // MARK: Header

    private func header(_ snapshot: WaterSnapshot) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.s) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()).uppercased())
                .font(DS.Typography.eyebrow)
                .tracking(1.2)
                .foregroundStyle(DS.Colors.textSecondary)
            Button { showingSource = true } label: {
                HStack(spacing: DS.Space.s) {
                    Image(systemName: snapshot.source.symbol)
                    Text(sourceLine(snapshot)).lineLimit(1)
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(DS.Typography.subheadline)
                .foregroundStyle(DS.Colors.textPrimary)
                .padding(.horizontal, DS.Space.m)
                .padding(.vertical, DS.Space.s)
                .frame(minHeight: DS.Size.tapTarget)
                .background(DS.Colors.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(DS.Colors.separator))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Shows your water source on a map"))
        }
        .padding(.top, DS.Space.s)
    }

    private func sourceLine(_ snapshot: WaterSnapshot) -> String {
        var parts = [snapshot.source.choiceTitle]
        if let system = settings.waterSourceEstimate?.systemName, snapshot.source.hasUtility { parts.append(system) }
        if let county = settings.county { parts.append(String(localized: "\(county) County")) }
        return parts.joined(separator: " · ")
    }

    private var sourceSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Space.l) {
                if let home = settings.homeLocation {
                    SourceMap(location: home, area: sourceArea)
                        .frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
                    Text(home.address).font(DS.Typography.lightBody).foregroundStyle(DS.Colors.textSecondary)
                }
                Label(settings.waterSource.choiceTitle, systemImage: settings.waterSource.symbol)
                    .font(DS.Typography.lightTitle2)
                if let estimate = settings.waterSourceEstimate, estimate.kind != .unknown {
                    Text(estimate.headline).font(DS.Typography.subheadline).foregroundStyle(DS.Colors.textSecondary)
                }
                Spacer()
            }
            .dsScreen()
            .background(DS.Colors.background)
            .navigationTitle("Your water source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSource = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Nudge

    /// The single most important thing to act on, with one action. Urgent ones are solid red.
    private func nudge(_ alert: AppAlert, more: Int) -> some View {
        let critical = alert.severity == .critical
        let tint = critical ? DS.Colors.unsafe : (alert.severity == .warning ? DS.Colors.fair : DS.Colors.accent)
        return Button {
            if critical { showingAlerts = true } else { perform(alert.action) }
        } label: {
            HStack(spacing: DS.Space.m) {
                Image(systemName: alert.symbol)
                    .font(.title3)
                    .foregroundStyle(critical ? Color.white : tint)
                    .frame(width: 36, height: 36)
                    .background(critical ? Color.white.opacity(0.18) : tint.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.title).font(DS.Typography.headline).lineLimit(2)
                    if more > 0 {
                        Text("+\(more) more").font(DS.Typography.footnote).opacity(0.8)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: DS.Space.s)
                Text(alert.actionTitle)
                    .font(DS.Typography.subheadline.weight(.semibold))
                    .padding(.horizontal, DS.Space.m)
                    .padding(.vertical, DS.Space.s)
                    .background(critical ? Color.white.opacity(0.2) : tint.opacity(0.14), in: Capsule())
            }
            .foregroundStyle(critical ? Color.white : DS.Colors.textPrimary)
            .padding(DS.Space.m)
            .background(critical ? AnyShapeStyle(Color(hex: 0xB3161F)) : AnyShapeStyle(DS.Colors.surface),
                        in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous)
                .strokeBorder(critical ? Color.clear : tint.opacity(0.35)))
        }
        .buttonStyle(DS.PressableCardStyle())
        .accessibilityIdentifier("dashboard.nudge")
        .onAppear { if critical { DS.Haptics.warning() } }
    }

    // MARK: Hero

    private func hero(_ drinking: TapScoreResult, snapshot: WaterSnapshot) -> some View {
        let recommended = WellHealthScore.recommendedTargets(for: snapshot.source, isShower: false)
        return Button { path.append(.score) } label: {
            VStack(spacing: DS.Space.l) {
                LandingScoreRing(score: drinking.score, level: drinking.dsLevel)
                Text(verdict(drinking))
                    .font(DS.Typography.lightTitle2)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 0) {
                    kpi(String(localized: "Drinking"), "\(drinking.score)", level: drinking.dsLevel)
                    Divider().frame(height: 36)
                    kpi(String(localized: "Shower"), snapshot.showers.first.map { "\($0.score)" } ?? "—",
                        level: snapshot.showers.first?.dsLevel)
                    Divider().frame(height: 36)
                    kpi(String(localized: "Tests"), "\(recommended.count - drinking.missingTests.count)/\(recommended.count)",
                        level: nil)
                }
            }
            .padding(.vertical, DS.Space.xl)
            .padding(.horizontal, DS.Space.l)
            .frame(maxWidth: .infinity)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 20, y: 8)
        }
        .buttonStyle(DS.PressableCardStyle())
        .accessibilityIdentifier("dashboard.score")
    }

    private func verdict(_ result: TapScoreResult) -> String {
        if result.items.contains(where: { $0.target.isMicrobial && $0.present == true }) {
            return String(localized: "Don't drink it untreated")
        }
        switch result.band {
        case .good: return String(localized: "Your water looks good")
        case .fair: return String(localized: "Mostly fine, a few to watch")
        case .poor: return String(localized: "Some problems to fix")
        case .unsafe: return String(localized: "Not safe to drink as is")
        }
    }

    private func kpi(_ label: String, _ value: String, level: DS.Level?) -> some View {
        VStack(spacing: DS.Space.xxs) {
            Text(value)
                .font(DS.Typography.lightTitle2.monospacedDigit())
                .foregroundStyle(DS.Colors.textPrimary)
            HStack(spacing: 4) {
                if let level {
                    Image(systemName: level.symbol).foregroundStyle(level.color).accessibilityHidden(true)
                }
                Text(label.uppercased()).tracking(0.8)
            }
            .font(DS.Typography.eyebrow)
            .foregroundStyle(DS.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: At a glance

    private struct GlanceRow: Identifiable {
        let name: String
        let percent: Double
        let level: DS.Level
        var id: String { name }
    }

    /// Every scored reading as a share of its limit, worst first. One chart, many data points.
    @ViewBuilder
    private func atAGlance(_ drinking: TapScoreResult) -> some View {
        let rows: [GlanceRow] = Array(drinking.items.compactMap { item in
            guard let ratio = item.ratio, let level = item.level.dsLevel else { return nil }
            return GlanceRow(name: item.target.name, percent: min(ratio * 100, 150), level: level)
        }.prefix(5))
        if !rows.isEmpty {
            Button { path.append(.score) } label: {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    sectionLabel(String(localized: "At a glance"), detail: String(localized: "% of each limit"))
                    Chart(rows) { row in
                        BarMark(x: .value("% of limit", row.percent), y: .value("Contaminant", row.name), height: 10)
                            .foregroundStyle(row.level.color.gradient)
                            .clipShape(Capsule())
                            .annotation(position: .trailing, spacing: 6) {
                                Text("\(Int(row.percent.rounded()))%")
                                    .font(DS.Typography.caption)
                                    .foregroundStyle(DS.Colors.textSecondary)
                            }
                        RuleMark(x: .value("Limit", 100))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    .chartXScale(domain: 0...160)
                    .chartXAxis {
                        AxisMarks(values: [0, 50, 100, 150]) { value in
                            AxisValueLabel {
                                let v = value.as(Int.self) ?? 0
                                Text(v == 100 ? String(localized: "Limit") : "\(v)%")
                            }
                        }
                    }
                    .frame(height: CGFloat(rows.count) * 38 + 24)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Readings compared with their limits"))
                    .accessibilityValue(Text(rows.map { "\($0.name): \(Int($0.percent.rounded())) percent of the limit, \($0.level.label)" }
                        .joined(separator: ", ")))
                }
                .padding(DS.Space.l)
                .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
            }
            .buttonStyle(DS.PressableCardStyle())
            .accessibilityIdentifier("dashboard.glance")
        }
    }

    // MARK: Empty

    private func emptyHero(_ snapshot: WaterSnapshot) -> some View {
        VStack(spacing: DS.Space.l) {
            Image(systemName: "drop")
                .font(.system(.largeTitle, weight: .ultraLight))
                .imageScale(.large)
                .foregroundStyle(DS.Colors.accent)
                .accessibilityHidden(true)
            Text(snapshot.source.showsCityContent && !snapshot.source.showsWellCare
                 ? String(localized: "Add your water report to see your score")
                 : String(localized: "Test your water to see your score"))
                .font(DS.Typography.lightTitle2)
                .multilineTextAlignment(.center)
                .foregroundStyle(DS.Colors.textPrimary)
            VStack(spacing: DS.Space.m) {
                if snapshot.source.showsCityContent {
                    NavigationLink { UtilityReportView() } label: { Label("Add utility report", systemImage: "building.2") }
                        .buttonStyle(DS.PrimaryButtonStyle())
                }
                if snapshot.source.showsWellCare {
                    Button { router.showingRiskCheck = true } label: { Label("Should I test my well?", systemImage: "checklist") }
                        .buttonStyle(AnyButtonStyle(snapshot.source.showsCityContent ? AnyButtonStyle(DS.SecondaryButtonStyle())
                                                                                    : AnyButtonStyle(DS.PrimaryButtonStyle())))
                }
                Button { router.showingScanner = true } label: { Label("Scan a report", systemImage: "doc.viewfinder") }
                    .buttonStyle(DS.SecondaryButtonStyle())
            }
        }
        .padding(DS.Space.xl)
        .frame(maxWidth: .infinity)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: Tiles

    private func tiles(_ snapshot: WaterSnapshot) -> some View {
        TileGrid(columns: 2, spacing: DS.Space.m) {
            Button { path.append(.filters) } label: {
                tile(String(localized: "Filters"), symbol: "line.3.horizontal.decrease.circle") {
                    if let soonest = snapshot.filtersByDue.first {
                        HStack(spacing: DS.Space.s) {
                            FilterLifeRing(daysLeft: soonest.days, totalDays: soonest.filter.lifeMonths.map { $0 * 30 })
                            Text(soonest.filter.name).font(DS.Typography.footnote).lineLimit(2)
                        }
                    } else {
                        bigValue(String(localized: "None"), caption: String(localized: "Add one"))
                    }
                }
            }
            .buttonStyle(DS.PressableCardStyle())
            .accessibilityIdentifier("dashboard.filters")

            Button { path.append(.modes) } label: {
                tile(String(localized: "Next test"), symbol: "calendar") {
                    if let due = snapshot.nextTest {
                        let days = max(0, Calendar.current.dateComponents([.day], from: snapshot.now, to: due.due).day ?? 0)
                        bigValue(due.isOverdue(at: snapshot.now) ? String(localized: "Now") : String(localized: "\(days)d"),
                                 caption: due.title)
                    } else {
                        bigValue("—", caption: String(localized: "Nothing due"))
                    }
                }
            }
            .buttonStyle(DS.PressableCardStyle())
            .accessibilityIdentifier("dashboard.nextTest")

            Button { path.append(.household) } label: {
                tile(String(localized: "Household"), symbol: "person.2") {
                    if snapshot.members.isEmpty {
                        bigValue("+", caption: String(localized: "Add people"))
                    } else {
                        let flagged = snapshot.exposures.values.filter { !$0.flags.isEmpty }.count
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            HStack(spacing: -DS.Space.s) {
                                ForEach(snapshot.members.prefix(4)) { member in
                                    MemberAvatar(member: member, flagged: !(snapshot.exposures[member.id]?.flags.isEmpty ?? true))
                                }
                            }
                            Text(flagged == 0 ? String(localized: "No flags") : String(localized: "\(flagged) flagged"))
                                .font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
                        }
                    }
                }
            }
            .buttonStyle(DS.PressableCardStyle())
            .accessibilityIdentifier("dashboard.household")

            Button { path.append(.taps) } label: {
                tile(String(localized: "Trend"), symbol: "chart.xyaxis.line") {
                    TrendSparkline(results: results)
                }
            }
            .buttonStyle(DS.PressableCardStyle())
            .accessibilityIdentifier("dashboard.taps")
        }
    }

    private func tile<Content: View>(_ title: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.m) {
            HStack(spacing: DS.Space.xs) {
                Image(systemName: symbol).accessibilityHidden(true)
                Text(title.uppercased()).tracking(0.8)
            }
            .font(DS.Typography.eyebrow)
            .foregroundStyle(DS.Colors.textSecondary)
            content()
            Spacer(minLength: 0)
        }
        .foregroundStyle(DS.Colors.textPrimary)
        .padding(DS.Space.l)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
        .contentShape(Rectangle())
    }

    private func bigValue(_ value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(DS.Typography.lightTitle).foregroundStyle(DS.Colors.textPrimary)
            Text(caption).font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary).lineLimit(2)
        }
    }

    private func sectionLabel(_ title: String, detail: String) -> some View {
        HStack {
            Text(title.uppercased()).tracking(1).font(DS.Typography.eyebrow).foregroundStyle(DS.Colors.textSecondary)
            Spacer()
            Text(detail).font(DS.Typography.caption).foregroundStyle(DS.Colors.textSecondary)
        }
    }

    // MARK: Next step

    private func nextStep(_ snapshot: WaterSnapshot) -> some View {
        Button { path.append(.remediation) } label: {
            HStack(spacing: DS.Space.m) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(.title2, weight: .light))
                    .foregroundStyle(DS.Colors.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT STEP").tracking(1).font(DS.Typography.eyebrow).foregroundStyle(DS.Colors.textSecondary)
                    Text(snapshot.topNextStep).font(DS.Typography.headline).foregroundStyle(DS.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary).accessibilityHidden(true)
            }
            .padding(DS.Space.l)
            .background(DS.Colors.surface, in: RoundedRectangle(cornerRadius: DS.Corner.large, style: .continuous))
        }
        .buttonStyle(DS.PressableCardStyle())
        .accessibilityIdentifier("dashboard.nextStep")
    }
}

// MARK: - Pieces

/// The landing score: a thin ring around a big thin number, with the level as icon + word.
struct LandingScoreRing: View {
    let score: Int
    let level: DS.Level

    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 200
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    var body: some View {
        let size = min(diameter, 280)
        ZStack {
            Circle().stroke(DS.Colors.track, lineWidth: 8)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(AngularGradient(colors: [level.color.opacity(0.5), level.color], center: .center),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: DS.Space.xs) {
                Text("\(score)")
                    .font(DS.Typography.thinNumber(size: min(numberSize, 100)))
                    .foregroundStyle(DS.Colors.textPrimary)
                    .contentTransition(.numericText())
                Label(level.label, systemImage: level.symbol)
                    .font(DS.Typography.subheadline.weight(.medium))
                    .foregroundStyle(level.color)
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
        }
        .frame(width: size, height: size)
        .onAppear {
            let target = Double(min(max(score, 0), 100)) / 100
            if reduceMotion { shown = target } else { withAnimation(DS.Motion.reveal) { shown = target } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Water Health Score \(score) out of 100, \(level.label)"))
    }
}

/// The reading with the most tests over time, as a small line with its limit dashed.
struct TrendSparkline: View {
    let results: [LabResult]

    private struct Point: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var body: some View {
        let candidates = Analyte.allCases.map { analyte in
            (analyte, results.compactMap { r in r.value(for: analyte).map { Point(date: r.date, value: $0) } }
                .sorted { $0.date < $1.date })
        }
        if let best = candidates.max(by: { $0.1.count < $1.1.count }), !best.1.isEmpty {
            let name = best.0.name
            let limit: Double? = if case .maximum(let max) = best.0.info.limit { max } else { nil }
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Chart {
                    ForEach(best.1) { point in
                        LineMark(x: .value("Date", point.date), y: .value(name, point.value))
                            .interpolationMethod(.monotone)
                            .foregroundStyle(DS.Colors.accent)
                        PointMark(x: .value("Date", point.date), y: .value(name, point.value))
                            .symbolSize(20)
                            .foregroundStyle(DS.Colors.accent)
                    }
                    if let limit {
                        RuleMark(y: .value("Limit", limit))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
                Text(name).font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(name) over time"))
            .accessibilityValue(Text(best.1.map { "\($0.date.formatted(date: .abbreviated, time: .omitted)): \(formatNumber($0.value))" }
                .joined(separator: ", ")))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("—").font(DS.Typography.lightTitle)
                Text("Appears after a test").font(DS.Typography.footnote).foregroundStyle(DS.Colors.textSecondary)
            }
        }
    }
}

/// Erases a button style so a ternary can pick one.
struct AnyButtonStyle: ButtonStyle {
    private let make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { make = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}

/// Every alert, most urgent first, each with one action.
struct AlertCenterView: View {
    let alerts: [AppAlert]
    let onAction: (AppAlert.Action) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Space.m) {
                    if alerts.isEmpty {
                        DS.EmptyStateView(systemImage: "bell.slash", message: String(localized: "You're all caught up."),
                                          actionTitle: String(localized: "Done")) { dismiss() }
                    }
                    ForEach(alerts) { alert in
                        let tint = color(alert.severity)
                        VStack(alignment: .leading, spacing: DS.Space.s) {
                            HStack(alignment: .top, spacing: DS.Space.m) {
                                Image(systemName: alert.symbol)
                                    .foregroundStyle(tint)
                                    .frame(width: 32, height: 32)
                                    .background(tint.opacity(0.14), in: Circle())
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label(alert.severity).uppercased()).tracking(0.8)
                                        .font(DS.Typography.eyebrow).foregroundStyle(tint)
                                    Text(alert.title).font(DS.Typography.headline)
                                    Text(alert.detail).font(DS.Typography.subheadline).foregroundStyle(DS.Colors.textSecondary)
                                        .lineLimit(3)
                                }
                            }
                            Button(alert.actionTitle) { onAction(alert.action) }
                                .font(DS.Typography.subheadline.weight(.semibold))
                                .frame(minHeight: DS.Size.tapTarget)
                        }
                        .foregroundStyle(DS.Colors.textPrimary)
                        .dsCard()
                        .accessibilityElement(children: .contain)
                    }
                }
                .dsScreen()
            }
            .background(DS.Colors.background)
            .navigationTitle("Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func color(_ severity: AppAlert.Severity) -> Color {
        switch severity {
        case .critical: DS.Colors.unsafe
        case .warning: DS.Colors.fair
        case .attention: DS.Colors.accent
        case .info: DS.Colors.textSecondary
        }
    }

    private func label(_ severity: AppAlert.Severity) -> String {
        switch severity {
        case .critical: String(localized: "Urgent")
        case .warning: String(localized: "Soon")
        case .attention: String(localized: "To do")
        case .info: String(localized: "Info")
        }
    }
}
