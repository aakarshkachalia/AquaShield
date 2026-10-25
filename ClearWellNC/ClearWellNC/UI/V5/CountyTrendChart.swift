//
//  CountyTrendChart.swift
//  ClearWellNC
//
//  Water > Trends (Redesign 5a): one contaminant in your county over time — monthly median and the top 10%
//  of wells — against the limit, with your result marked, and three numbers underneath.
//  The bundled county data is sample data and is labeled as such.
//

import Charts
import SwiftUI

struct CountyTrendChart: View {
    let contaminant: ContaminantID
    let county: String
    /// Your latest value, in the contaminant's stored unit.
    let yours: Double

    @State private var trends = CountyTrendData.loadBundled()
    @State private var countyData = CountyWellData.loadBundled()

    private struct Point: Identifiable {
        let date: Date
        let median: Double
        let p90: Double
        var id: Date { date }
    }

    private var points: [Point] {
        let calendar = Calendar(identifier: .gregorian)
        return (trends?.records ?? [])
            .filter { $0.county == county && $0.contaminant == contaminant }
            .compactMap { r in
                calendar.date(from: DateComponents(year: r.year, month: r.month, day: 15)).map { Point(date: $0, median: r.median, p90: r.p90) }
            }
            .sorted { $0.date < $1.date }
    }

    private var limit: Double? {
        if case .maximum(let max) = contaminant.info.limit { max } else { nil }
    }

    var body: some View {
        let points = points
        let info = contaminant.info
        if points.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(info.name), \(county) County").font(M.Font.section)
                    Spacer()
                    if trends?.isSample == true { SampleDataTag() }
                }
                Text("Monthly median and top 10% of wells, \(info.unit.label)")
                    .font(M.Font.small).foregroundStyle(M.Colors.muted).padding(.top, 3).padding(.bottom, 14)
                Chart {
                    ForEach(points) { p in
                        AreaMark(x: .value("Month", p.date), yStart: .value("Median", p.median), yEnd: .value("Top 10%", p.p90))
                            .foregroundStyle(M.Colors.line.opacity(0.5))
                        LineMark(x: .value("Month", p.date), y: .value("Top 10%", p.p90), series: .value("Series", "p90"))
                            .foregroundStyle(M.Colors.muted)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        LineMark(x: .value("Month", p.date), y: .value("Median", p.median), series: .value("Series", "median"))
                            .foregroundStyle(M.Colors.ink)
                            .lineStyle(StrokeStyle(lineWidth: 1.25))
                    }
                    if let limit {
                        RuleMark(y: .value("Limit", limit))
                            .foregroundStyle(M.Colors.over)
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .annotation(position: .top, alignment: .leading) {
                                Text("Limit \(formatNumber(limit))").font(M.Font.tiny).foregroundStyle(M.Colors.overText)
                            }
                    }
                    if let last = points.last {
                        PointMark(x: .value("Month", last.date), y: .value("You", yours))
                            .foregroundStyle(M.Colors.over)
                            .symbolSize(50)
                            .annotation(position: .leading) {
                                Text("You · \(formatNumber(yours))").font(M.Font.label).foregroundStyle(M.Colors.overText)
                            }
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .year)) { _ in AxisValueLabel(format: .dateTime.year()) } }
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(info.name) in \(county) County over time"))
                .accessibilityValue(Text("Latest county median \(formatNumber(points.last?.median ?? 0)) \(info.unit.label). Yours \(formatNumber(yours))."))

                let median = points.last?.median ?? 0
                let share = countyData?.reportable(for: county).first { $0.contaminantID == contaminant }?.pctAboveStandard
                HStack(spacing: 0) {
                    stat(formatNumber(median), String(localized: "County median"))
                    Rectangle().fill(M.Colors.line).frame(width: 1)
                    stat(share.map { "\(formatNumber($0))%" } ?? "—", String(localized: "Wells over limit"))
                    Rectangle().fill(M.Colors.line).frame(width: 1)
                    stat(median > 0 ? M.times(yours / median) : "—", String(localized: "You vs median"))
                }
                .fixedSize(horizontal: false, vertical: true)
                .overlay(alignment: .top) { M.Rule() }
                .padding(.top, 20)
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(M.Font.bigNumber)
            Text(label).font(M.Font.tiny).foregroundStyle(M.Colors.muted)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
