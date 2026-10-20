//
//  SeasonalOutlookView.swift
//  ClearWellNC
//

import Charts
import SwiftData
import SwiftUI

struct SeasonalOutlookView: View {
    /// County to open on (from My Well), if the data has it.
    let initialCounty: String?

    @Query(sort: \LabResult.date) private var results: [LabResult]
    @State private var data = CountyTrendData.loadBundled()
    @State private var county = ""
    @State private var contaminant: ContaminantID = .nitrate

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                if let data, !data.records.isEmpty {
                    if data.isSample { sampleBanner }
                    pickers(data)
                    content(data)
                } else {
                    ContentUnavailableView("Trend data isn't available", systemImage: "chart.xyaxis.line",
                                           description: Text("County trend data was not found in the app."))
                }
                TestingDisclaimer(kind: .forecast)
            }
            .padding(Spacing.l)
            .readableWidth()
        }
        .background(Color.appBackground)
        .navigationTitle("Seasonal outlook")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: chooseDefaults)
        .onChange(of: county) { _, _ in
            if let data, !data.contaminants(in: county).contains(contaminant) {
                contaminant = data.contaminants(in: county).first ?? .nitrate
            }
        }
    }

    // MARK: Pieces

    private var sampleBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Sample data").font(.headline)
                Text("These charts use made-up placeholder numbers for testing the app. They are not real well-test results.")
                    .font(.subheadline)
            }
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Interpretation.Tier.watch.color)
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(Color.statusWatch.opacity(0.5)))
        .accessibilityElement(children: .combine)
    }

    private func pickers(_ data: CountyTrendData) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Picker("County", selection: $county) {
                ForEach(data.counties, id: \.self) { Text(String(localized: "\($0) County")).tag($0) }
            }
            .frame(minHeight: 44)
            Picker("Contaminant", selection: $contaminant) {
                ForEach(data.contaminants(in: county)) { Text($0.info.name).tag($0) }
            }
            .frame(minHeight: 44)
        }
        .pickerStyle(.menu)
        .card()
    }

    @ViewBuilder
    private func content(_ data: CountyTrendData) -> some View {
        if let result = SeasonalForecast.fit(data.series(county: county, contaminant: contaminant)) {
            let insight = SeasonalInsight.make(for: result, contaminant: contaminant, county: county)
            let personal = personalPoints
            let showPersonal = SeasonalForecast.shouldShowPersonalOverlay(pointCount: personal.count)

            VStack(alignment: .leading, spacing: Spacing.m) {
                Text("\(contaminant.info.name), \(county) County")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                SeasonalChart(result: result, limit: contaminant.info.maximumLimit, unit: contaminant.info.unit,
                              personal: showPersonal ? personal : [])
                    .accessibilityElement()
                    .accessibilityLabel(Text("Seasonal trend and forecast chart"))
                    .accessibilityValue(Text(SeasonalInsight.accessibilitySummary(for: result, contaminant: contaminant, county: county)
                                             + " " + (insight.limitText ?? "")))
                legend(showPersonal: showPersonal)
                Text(result.usedPreferredWindow
                     ? String(localized: "Trend: 20-month moving average.")
                     : String(localized: "Trend: \(result.window)-month moving average, using all available data (fewer than 20 months)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ChartCaptionView(text: insight.text)
            }
            .card()

            personalNote(count: personal.count, shown: showPersonal)
        } else {
            Text("Not enough data for \(contaminant.info.name) in \(county) County. The model needs at least \(SeasonalForecast.minimumPoints) months.")
                .card()
        }
    }

    private func legend(showPersonal: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            legendRow(.history, text: String(localized: "Thin gray line: county median from past tests"))
            legendRow(.trend, text: String(localized: "Thick line: moving average (the trend)"))
            legendRow(.forecast, text: String(localized: "Dashed line and shaded band: forecast and its likely range. Predicted — not a test result."))
            legendRow(.limit, text: String(localized: "Red line: the limit"))
            if showPersonal {
                legendRow(.personal, text: String(localized: "Squares: your own test results"))
            }
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
    }

    private func legendRow(_ swatch: LegendSwatch.Kind, text: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.s) {
            LegendSwatch(kind: swatch)
                .padding(.top, Spacing.xs)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func personalNote(count: Int, shown: Bool) -> some View {
        Group {
            if shown {
                Text("Your \(count) \(contaminant.info.name.lowercased()) results are shown as squares. They are not used to fit the forecast.")
            } else {
                Text("Add at least \(SeasonalForecast.minimumPoints) of your own \(contaminant.info.name.lowercased()) results to see them on this chart.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Data

    private var personalPoints: [SeasonalChart.PersonalPoint] {
        guard let analyte = Analyte.allCases.first(where: { $0.contaminant == contaminant }) else { return [] }
        return results.compactMap { r in
            r.value(for: analyte).map { SeasonalChart.PersonalPoint(date: r.date, value: $0) }
        }
    }

    private func chooseDefaults() {
        guard county.isEmpty, let data else { return }
        let counties = data.counties
        county = initialCounty.flatMap { counties.contains($0) ? $0 : nil } ?? counties.first ?? ""
        contaminant = data.contaminants(in: county).first ?? .nitrate
    }
}

struct SeasonalChart: View {
    struct PersonalPoint: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    let result: SeasonalForecast.Result
    let limit: Double?
    let unit: MeasurementUnit
    let personal: [PersonalPoint]

    var body: some View {
        Chart {
            ForEach(result.forecast, id: \.self) { f in
                AreaMark(x: .value("Month", f.date), yStart: .value("Lower", f.lower), yEnd: .value("Upper", f.upper))
                    .foregroundStyle(Color.accentColor.opacity(0.18))
            }
            ForEach(result.history, id: \.self) { p in
                LineMark(x: .value("Month", p.date), y: .value("Median", p.value), series: .value("Series", "History"))
                    .foregroundStyle(Color.gray)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(result.movingAverage, id: \.self) { p in
                LineMark(x: .value("Month", p.date), y: .value("Trend", p.value), series: .value("Series", "Trend"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
            ForEach(result.forecast, id: \.self) { f in
                LineMark(x: .value("Month", f.date), y: .value("Forecast", f.value), series: .value("Series", "Forecast"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            if let limit {
                RuleMark(y: .value("Limit", limit))
                    .foregroundStyle(RiskLevel.high.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Limit \(Interpretation.format(limit, unit: unit))")
                            .font(.caption)
                            .foregroundStyle(RiskLevel.high.color)
                    }
            }
            if let start = result.forecast.first?.date {
                RuleMark(x: .value("Forecast starts", start))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Predicted — not a test result.")
                            .font(.caption.weight(.semibold))
                    }
            }
            ForEach(personal) { p in
                PointMark(x: .value("Month", p.date), y: .value("Your result", p.value))
                    .symbol(BasicChartSymbolShape.square)
                    .foregroundStyle(Color.primary)
            }
        }
        .chartYAxisLabel(unit.label)
        .frame(height: 260)
    }
}

/// Small drawing of each chart mark, so the legend matches what's on the chart.
struct LegendSwatch: View {
    enum Kind { case history, trend, forecast, limit, personal }

    let kind: Kind

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            var line = Path()
            line.move(to: CGPoint(x: 0, y: mid))
            line.addLine(to: CGPoint(x: size.width, y: mid))
            switch kind {
            case .history:
                context.stroke(line, with: .color(.gray), lineWidth: 1.5)
            case .trend:
                context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            case .forecast:
                context.fill(Path(CGRect(x: 0, y: mid - 5, width: size.width, height: 10)),
                             with: .color(.accentColor.opacity(0.18)))
                context.stroke(line, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            case .limit:
                context.stroke(line, with: .color(RiskLevel.high.color), lineWidth: 1.5)
            case .personal:
                context.fill(Path(CGRect(x: size.width / 2 - 4, y: mid - 4, width: 8, height: 8)), with: .color(.primary))
            }
        }
        .frame(width: 24, height: 12)
        .accessibilityHidden(true)
    }
}
