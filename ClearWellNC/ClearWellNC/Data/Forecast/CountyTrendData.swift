//
//  CountyTrendData.swift
//  ClearWellNC
//
//  Loads bundled county-level monthly well-test aggregates for the seasonal model.
//
//  File: county_trends.csv in the app bundle. Format (header required, # lines are comments):
//      county,contaminant,month,year,median,p90,n
//      Johnston,nitrate,4,2023,3.1,7.9,42
//  - county: county name as in CountyNames ("New Hanover"), without "County"
//  - contaminant: a ContaminantID raw value ("nitrate", "arsenic", "manganese", …)
//  - median/p90: in the app's units for that contaminant (ppb for arsenic/lead/manganese/iron/uranium,
//    mg/L for nitrate/nitrite/copper/fluoride, pCi/L for radon)
//  A line "# sample: true" marks the file as placeholder data; the UI then shows a SAMPLE DATA banner.
//

import Foundation

nonisolated struct CountyTrendRecord: Sendable, Hashable {
    let county: String
    let contaminant: ContaminantID
    let month: Int
    let year: Int
    let median: Double
    let p90: Double
    let n: Int
}

nonisolated struct CountyTrendData: Sendable {
    let records: [CountyTrendRecord]
    /// True when the file declares itself placeholder data.
    let isSample: Bool

    static let resourceName = "county_trends"

    var counties: [String] {
        Array(Set(records.map(\.county))).sorted()
    }

    func contaminants(in county: String) -> [ContaminantID] {
        let present = Set(records.filter { $0.county == county }.map(\.contaminant))
        return ContaminantID.allCases.filter(present.contains)
    }

    /// Monthly medians for one county and contaminant, as model input.
    func series(county: String, contaminant: ContaminantID) -> [SeasonalForecast.Point] {
        records
            .filter { $0.county == county && $0.contaminant == contaminant }
            .map { SeasonalForecast.Point(year: $0.year, month: $0.month, value: $0.median) }
    }

    static func loadBundled(from bundle: Bundle = .main) -> CountyTrendData? {
        guard let url = bundle.url(forResource: resourceName, withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parse(text)
    }

    /// Lenient parser: skips comments, blank lines and malformed rows.
    static func parse(_ text: String) -> CountyTrendData {
        var records: [CountyTrendRecord] = []
        var isSample = false
        var sawHeader = false
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#") {
                if line.lowercased().replacingOccurrences(of: " ", with: "").contains("sample:true") { isSample = true }
                continue
            }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if !sawHeader, fields.first?.lowercased() == "county" {
                sawHeader = true
                continue
            }
            guard fields.count >= 7,
                  let contaminant = ContaminantID(rawValue: fields[1].lowercased()),
                  let month = Int(fields[2]), (1...12).contains(month),
                  let year = Int(fields[3]),
                  let median = Double(fields[4]),
                  let p90 = Double(fields[5]),
                  let n = Int(fields[6])
            else { continue }
            records.append(CountyTrendRecord(county: fields[0], contaminant: contaminant, month: month,
                                             year: year, median: median, p90: p90, n: n))
        }
        return CountyTrendData(records: records, isSample: isSample)
    }
}
