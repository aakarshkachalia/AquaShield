//
//  ContaminantDetailView.swift
//  ClearWellNC
//
//  One contaminant (Redesign 5b): a half-dial with your reading, three numbers, you vs. your county, who in
//  the household it matters most for, how much it costs your score, then fixes, meaning and trend.
//

import SwiftData
import SwiftUI

struct ContaminantDetailView: View {
    let id: ContaminantID

    @Environment(AppRouter.self) private var router
    @Environment(AppSettings.self) private var settings
    @Query(sort: \LabResult.date, order: .reverse) private var results: [LabResult]
    @Query(sort: \TreatmentSystem.addedAt) private var systems: [TreatmentSystem]
    @State private var countyData = CountyWellData.loadBundled()

    private var analyte: Analyte? { Analyte.allCases.first { $0.contaminant == id } }

    /// Latest reading of this contaminant across all reports.
    private var latest: (interpretation: Interpretation, value: Double?, date: Date)? {
        for result in results {
            if let analyte, let value = result.value(for: analyte) {
                if let limit = result.nonDetects[analyte] {
                    return (Interpretation.interpretNonDetect(id, detectionLimit: limit), nil, result.date)
                }
                return (Interpretation.interpret(id, value: value), value, result.date)
            }
            if id == .totalColiform, let c = result.totalColiform { return (.interpret(id, present: c == .present), nil, result.date) }
            if id == .eColi, let e = result.eColi { return (.interpret(id, present: e == .present), nil, result.date) }
        }
        return nil
    }

    private var limit: Double? {
        if case .maximum(let max) = id.info.limit { max } else { nil }
    }

    private var countyRecord: CountyWellRecord? {
        guard let county = settings.county else { return nil }
        return countyData?.reportable(for: county).first { $0.contaminantID == id }
    }

    var body: some View {
        let info = id.info
        let latest = latest
        let snapshot = WaterSnapshot.make(results: results, systems: systems, settings: settings)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let latest {
                    if let value = latest.value, let limit {
                        HalfDial(value: value, limit: limit, unit: info.unit.label)
                            .padding(.top, 8)
                        numbers(value: value, limit: limit, unit: info.unit.label)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(latest.interpretation.readingText).font(M.Font.thin(44))
                            Text(latest.interpretation.chipLabel).font(M.Font.label)
                                .foregroundStyle(latest.interpretation.tier == .above ? M.Colors.overText : M.Colors.muted)
                        }
                        .padding(.horizontal, 20).padding(.top, 12)
                    }
                    Text("Tested \(latest.date.formatted(date: .long, time: .omitted))")
                        .font(M.Font.tiny).foregroundStyle(M.Colors.muted)
                        .padding(.horizontal, 20).padding(.top, 10)

                    if let value = latest.value, let limit, let record = countyRecord {
                        versusCounty(value: value, limit: limit, record: record)
                            .padding(.horizontal, 20).padding(.top, 24)
                    }
                    exposed(snapshot)
                        .padding(.horizontal, 20).padding(.top, 24)
                    impact(snapshot)
                        .padding(.horizontal, 20).padding(.top, 24)

                    NavigationLink { RemediationView() } label: {
                        HStack { Text("See fixes"); Spacer(); Text("→") }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(M.InkButtonStyle())
                    .padding(.horizontal, 20).padding(.top, 24)

                    VStack(alignment: .leading, spacing: 10) {
                        M.SectionHeader(title: String(localized: "What it means"))
                        Text(info.plainSummary).font(M.Font.row).fixedSize(horizontal: false, vertical: true)
                        if !info.sensitiveGroups.isEmpty {
                            Text("Most at risk: \(info.sensitiveGroups.map(\.label).formatted(.list(type: .and)))")
                                .font(M.Font.small).foregroundStyle(M.Colors.muted)
                        }
                        if latest.interpretation.isHealthExceedance {
                            Button("Get help paying for a fix →") { router.openHelp(.contaminant(id)) }
                                .buttonStyle(M.OutlineButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 28)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("No results for this yet.").font(.system(.title3, weight: .light))
                        Button("Find testing →") { router.openHelp(.testing) }.buttonStyle(M.InkButtonStyle())
                    }
                    .padding(20)
                }

                if let analyte, results.contains(where: { $0.value(for: analyte) != nil }) {
                    TrendChart(analyte: analyte, results: results).padding(.horizontal, 16).padding(.top, 24)
                }
                if let article = LearnLibrary.article(for: id) {
                    NavigationLink { LearnArticleView(article: article) } label: {
                        HStack {
                            Image(systemName: "book").font(.system(.body, weight: .light))
                            Text("Learn about \(article.title.inSentence)").font(M.Font.section)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(.footnote, weight: .light))
                        }
                        .frame(minHeight: 52)
                        .overlay(alignment: .top) { M.Rule() }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.top, 24)
                }
                M.Footer(sample: countyRecord?.sample == true).padding(.horizontal, 20)
            }
            .frame(maxWidth: DS.Size.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .modernistScreen()
        .navigationTitle(info.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Pieces

    private func numbers(value: Double, limit: Double, unit: String) -> some View {
        let ratio = value / limit
        return HStack(spacing: 0) {
            cell(M.times(ratio), String(localized: "of limit"), color: M.Zone(ratio: ratio).textColor)
            Rectangle().fill(M.Colors.line).frame(width: 1)
            cell(formatNumber(limit), String(localized: "Limit, \(unit)"), color: M.Colors.ink)
            Rectangle().fill(M.Colors.line).frame(width: 1)
            cell(countyRecord.map { "\(formatNumber($0.pctAboveStandard))%" } ?? "—",
                 String(localized: "County wells over"), color: M.Colors.ink)
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .top) { M.Rule() }
        .overlay(alignment: .bottom) { M.Rule() }
    }

    private func cell(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(M.Font.number).foregroundStyle(color)
            Text(label).font(M.Font.tiny).foregroundStyle(M.Colors.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func versusCounty(value: Double, limit: Double, record: CountyWellRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            M.SectionHeader(title: String(localized: "You vs. \(record.nWells) \(record.county) County wells"),
                            note: record.sample ? String(localized: "sample data") : nil)
            HStack(spacing: 10) {
                Text("× of limit").font(M.Font.tiny).foregroundStyle(M.Colors.muted).frame(width: 64, alignment: .leading)
                M.LimitTrack(ratio: value / limit, countyRatio: record.meanConcentration / limit)
            }
            HStack(spacing: 14) {
                HStack(spacing: 5) { M.Dot(color: M.Zone(ratio: value / limit).color); Text("You · \(formatNumber(value))") }
                HStack(spacing: 5) { Rectangle().fill(M.Colors.ink).frame(width: 1, height: 9)
                    Text("County average · \(formatNumber(record.meanConcentration))") }
            }
            .font(M.Font.tiny)
            .foregroundStyle(M.Colors.muted)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func exposed(_ snapshot: WaterSnapshot) -> some View {
        let target = ClaimTarget(contaminant: id)
        let members = snapshot.members
        VStack(alignment: .leading, spacing: 8) {
            M.SectionHeader(title: String(localized: "Who's most exposed"), note: String(localized: "daily amount from drinking"))
            if members.isEmpty {
                NavigationLink { HouseholdView() } label: {
                    HStack { Text("Add the people who drink this water"); Spacer(); Text("→") }
                        .font(M.Font.row).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ForEach(members) { member in
                    let exposure = snapshot.exposures[member.id]
                    let flag = exposure?.flags.first { $0.target == target }
                    let dose = target.flatMap { exposure?.dosePerKg[$0] }
                    HStack(spacing: 10) {
                        MemberAvatar(member: member, flagged: flag != nil).scaleEffect(0.6).frame(width: 26, height: 26)
                        Text(member.displayName).font(M.Font.row)
                        Spacer()
                        if let dose, let target {
                            Text("\(formatNumber(dose)) \(ReadingUnit.canonical(for: target).doseLabel)")
                                .font(M.Font.value).foregroundStyle(flag != nil ? M.Colors.overText : M.Colors.muted)
                        } else if flag != nil {
                            Text("More sensitive").font(M.Font.value).foregroundStyle(M.Colors.overText)
                        } else {
                            Text("Add weight").font(M.Font.small).foregroundStyle(M.Colors.muted)
                        }
                    }
                    .frame(minHeight: 36)
                    .overlay(alignment: .bottom) { M.Rule(color: M.Colors.hairline) }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func impact(_ snapshot: WaterSnapshot) -> some View {
        let items = (snapshot.drinking?.items ?? []).filter { $0.penalty > 0.5 }.sorted { $0.penalty > $1.penalty }.prefix(3)
        if !items.isEmpty {
            let top = max(items.first?.penalty ?? 1, 1)
            VStack(alignment: .leading, spacing: 10) {
                M.SectionHeader(title: String(localized: "Score impact"), note: String(localized: "points off"))
                ForEach(Array(items)) { item in
                    let mine = item.target == ClaimTarget(contaminant: id)
                    HStack(spacing: 8) {
                        Text(item.target.name).font(mine ? M.Font.section : M.Font.row).frame(width: 84, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(M.Colors.hairline).frame(height: 2)
                                Rectangle().fill(mine ? M.Colors.over : M.Colors.ink).frame(width: geo.size.width * item.penalty / top, height: 2)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 12)
                        Text("−\(Int(item.penalty.rounded()))").font(M.Font.value).frame(width: 34, alignment: .trailing)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(item.target.name): \(Int(item.penalty.rounded())) points off the score"))
                }
            }
        }
    }
}

/// Half-dial from 0 to 2.5× the limit: zone-colored ticks lit up to your value, a needle, the limit tick.
struct HalfDial: View {
    let value: Double
    let limit: Double
    let unit: String

    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 44
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0

    private var maxValue: Double { limit * 2.5 }
    private let center = CGPoint(x: 150, y: 160)

    private func point(_ degrees: Double, _ radius: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: center.x + radius * sin(r), y: center.y - radius * cos(r))
    }

    private func angle(_ v: Double) -> Double { -90 + min(v, maxValue) / maxValue * 180 }

    var body: some View {
        let ratio = value / limit
        ZStack {
            Canvas { context, _ in
                for k in 0...50 {
                    let v = Double(k) / 50 * maxValue
                    let long = k % 10 == 0
                    var path = Path()
                    path.move(to: point(angle(v), 128))
                    path.addLine(to: point(angle(v), long ? 112 : 119))
                    let lit = v <= shown
                    context.stroke(path, with: .color(M.Zone(ratio: v / limit).color.opacity(lit ? 1 : 0.28)),
                                   lineWidth: long ? 1.6 : 1)
                }
                var tick = Path()
                tick.move(to: point(angle(limit), 134)); tick.addLine(to: point(angle(limit), 104))
                context.stroke(tick, with: .color(M.Colors.ink), lineWidth: 1.5)
                var needle = Path()
                needle.move(to: center); needle.addLine(to: point(angle(shown), 104))
                context.stroke(needle, with: .color(M.Colors.ink), lineWidth: 1.25)
                context.fill(Path(ellipseIn: CGRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8)), with: .color(M.Colors.ink))
            }
            ForEach([0, limit, limit * 2, maxValue], id: \.self) { v in
                let p = point(angle(v), 146)
                Text(v == maxValue ? "\(formatNumber(v)) \(unit)" : formatNumber(v))
                    .font(M.Font.tiny).foregroundStyle(v == limit ? M.Colors.ink : M.Colors.muted).fixedSize()
                    .position(x: p.x, y: p.y - 2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(formatNumber(value)).font(M.Font.thin(min(numberSize, 64))).foregroundStyle(M.Zone(ratio: ratio).textColor)
                Text(unit).font(M.Font.row).foregroundStyle(M.Colors.muted)
            }
            .position(x: 150, y: 196)
        }
        .frame(width: 300, height: 226)
        .frame(maxWidth: .infinity)
        .onAppear {
            if reduceMotion { shown = value } else { withAnimation(.spring(duration: 1.4, bounce: 0.05)) { shown = value } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(formatNumber(value)) \(unit), limit \(formatNumber(limit))"))
        .accessibilityValue(Text("\(M.times(ratio)) the limit, \(M.Zone(ratio: ratio).label)"))
    }
}
