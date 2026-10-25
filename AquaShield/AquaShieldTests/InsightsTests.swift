//
//  InsightsTests.swift
//  AquaShieldTests
//
//  Interpretation layer, Well Health Score, seasonal model, and CSV pipeline.
//

import XCTest
@testable import AquaShield

final class InterpretationTests: XCTestCase {

    func testCatalogCoversRequiredContaminants() {
        let required: [ContaminantID] = [.arsenic, .lead, .nitrate, .nitrite, .uranium, .manganese, .iron, .copper,
                                         .fluoride, .totalColiform, .eColi, .pH, .hardness, .radon]
        for id in required {
            XCTAssertFalse(id.info.name.isEmpty, "\(id) has no info")
            XCTAssertFalse(id.info.plainSummary.isEmpty, "\(id) has no summary")
        }
    }

    func testStatusThresholds() {
        XCTAssertEqual(Interpretation.interpret(.arsenic, value: 4.9).tier, .safe)    // 49%
        XCTAssertEqual(Interpretation.interpret(.arsenic, value: 5).tier, .watch)     // 50%
        XCTAssertEqual(Interpretation.interpret(.arsenic, value: 9.9).tier, .watch)   // 99%
        XCTAssertEqual(Interpretation.interpret(.arsenic, value: 10).tier, .above)    // 100%
        XCTAssertEqual(Interpretation.interpret(.arsenic, value: 10).chipLabel, "Above limit")
        XCTAssertTrue(Interpretation.interpret(.arsenic, value: 10).isHealthExceedance)
    }

    func testNitrateExampleSentence() {
        let i = Interpretation.interpret(.nitrate, value: 6)
        XCTAssertEqual(i.tier, .watch)
        XCTAssertEqual(i.percentOfLimit ?? 0, 60, accuracy: 1e-9)
        XCTAssertEqual(i.sentence, "Your nitrate is 6 mg/L, which is 60% of the safe limit (10 mg/L). This is OK for adults but worth retesting if an infant or someone who is pregnant drinks this water.")
    }

    func testAestheticContaminantsSayNoHealthLimit() {
        let iron = Interpretation.interpret(.iron, value: 400)
        XCTAssertEqual(iron.tier, .nuisance)
        XCTAssertFalse(iron.isHealthExceedance)
        XCTAssertTrue(iron.sentence.contains("no health-based limit"))

        let pH = Interpretation.interpret(.pH, value: 6.0)
        XCTAssertEqual(pH.chipLabel, "Outside range")
        XCTAssertTrue(pH.sentence.contains("corrode"))

        let hardness = Interpretation.interpret(.hardness, value: 150)
        XCTAssertEqual(hardness.tier, .info)
        XCTAssertEqual(hardness.chipLabel, "Hard")
        XCTAssertNil(hardness.percentOfLimit)
    }

    func testManganeseHealthAdvisoryEscalates() {
        XCTAssertFalse(Interpretation.interpret(.manganese, value: 120).isHealthExceedance)
        XCTAssertTrue(Interpretation.interpret(.manganese, value: 300).isHealthExceedance)
    }

    func testBacteria() {
        let absent = Interpretation.interpret(.eColi, present: false)
        XCTAssertEqual(absent.tier, .safe)
        let present = Interpretation.interpret(.eColi, present: true)
        XCTAssertEqual(present.tier, .above)
        XCTAssertTrue(present.isHealthExceedance)
    }

    func testTrendCaption() {
        let d1 = Date(timeIntervalSince1970: 0)
        let d2 = Date(timeIntervalSince1970: 86_400 * 365)
        let caption = ChartCaption.trend(for: .arsenic, points: [(d1, 2), (d2, 12)])
        XCTAssertTrue(caption.contains("went up"), caption)
        XCTAssertTrue(caption.contains("1 of 2 tests crossed the limit"), caption)
    }
}

final class WellHealthScoreTests: XCTestCase {

    /// A complete set of key tests, all comfortably under their limits.
    private func allSafe() -> WellHealthScore.Input {
        var input = WellHealthScore.Input()
        input.values = [.arsenic: 1, .lead: 1, .nitrate: 1, .manganese: 5, .pH: 7.2]
        input.presence = [.totalColiform: false, .eColi: false]
        return input
    }

    func testAllSafeScoresGood() {
        let result = WellHealthScore.compute(allSafe())
        XCTAssertTrue(result.isComplete)
        XCTAssertEqual(result.keyTestsOnFile, result.keyTestsTotal)
        XCTAssertGreaterThanOrEqual(result.score ?? 0, 80)
        XCTAssertEqual(result.band, .good)
        XCTAssertFalse(result.healthLimitExceeded)
    }

    func testOneExceedanceCapsAt40() {
        var input = allSafe()
        input.values[.arsenic] = 12
        let result = WellHealthScore.compute(input)
        XCTAssertTrue(result.healthLimitExceeded)
        XCTAssertLessThanOrEqual(result.score ?? 100, 40)
        XCTAssertEqual(result.band, .unsafe)
        XCTAssertEqual(result.topFactors.first?.id, .arsenic)
    }

    func testEColiCapsAt10() {
        var input = allSafe()
        input.presence[.eColi] = true
        let result = WellHealthScore.compute(input)
        XCTAssertTrue(result.eColiPositive)
        XCTAssertLessThanOrEqual(result.score ?? 100, 10)
        XCTAssertEqual(result.band, .unsafe)
        XCTAssertEqual(result.factors.first?.id, .eColi)
    }

    func testPartialDataIsIncompleteNotSafe() {
        var input = WellHealthScore.Input()
        input.values = [.arsenic: 2]
        let result = WellHealthScore.compute(input)
        XCTAssertNil(result.score, "Missing tests must not be scored as safe")
        XCTAssertNil(result.band)
        XCTAssertEqual(result.keyTestsOnFile, 1)
        XCTAssertEqual(result.keyTestsTotal, WellHealthScore.KeyTest.allCases.count)
        XCTAssertFalse(result.isComplete)
    }

    func testPartialDataWithExceedanceStillShowsCappedScore() {
        var input = WellHealthScore.Input()
        input.values = [.nitrate: 15]
        let result = WellHealthScore.compute(input)
        XCTAssertNotNil(result.score)
        XCTAssertLessThanOrEqual(result.score ?? 100, 40)
        XCTAssertFalse(result.isComplete)
    }

    func testScoreNeverLooksGoodWithHealthExceedance() {
        for id in ContaminantID.allCases {
            guard id.info.limitType == .health, let limit = id.info.maximumLimit else { continue }
            var input = allSafe()
            input.values[id] = limit
            let result = WellHealthScore.compute(input)
            XCTAssertEqual(result.band, .unsafe, "\(id) at its limit should be Unsafe")
        }
    }

    func testAestheticSubtractsLessThanHealth() {
        XCTAssertLessThan(WellHealthScore.penalty(for: .iron, value: 10_000),
                          WellHealthScore.penalty(for: .arsenic, value: 9.9))
    }
}

final class SeasonalForecastTests: XCTestCase {

    /// Deterministic noise in [-amplitude, amplitude].
    private struct LCG {
        var state: UInt64
        mutating func next(amplitude: Double) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(state >> 11) / Double(1 << 53)
            return (unit * 2 - 1) * amplitude
        }
    }

    /// 10 + 3·sin(2π(m−1)/12) + slope·i + noise, starting January 2021.
    private func series(months: Int, slope: Double = 0, noise: Double = 0.3) -> [SeasonalForecast.Point] {
        var rng = LCG(state: 42)
        let start = 2021 * 12
        return (0..<months).map { i in
            let index = start + i
            let month = index % 12 + 1
            let value = 10 + 3 * sin(2 * .pi * Double(month - 1) / 12) + slope * Double(i) + rng.next(amplitude: noise)
            return SeasonalForecast.Point(index: index, value: value)
        }
    }

    func testRecoversSeasonality() throws {
        let result = try XCTUnwrap(SeasonalForecast.fit(series(months: 48)))
        for m in 1...12 {
            let truth = 3 * sin(2 * .pi * Double(m - 1) / 12)
            XCTAssertEqual(result.seasonal[m - 1], truth, accuracy: 0.5, "month \(m)")
        }
        XCTAssertEqual(result.peakMonth, 4)      // sine peaks at (m-1) = 3 → April
        XCTAssertEqual(result.troughMonth, 10)   // October
        XCTAssertEqual(result.window, 20)
        XCTAssertTrue(result.usedPreferredWindow)
        XCTAssertEqual(abs(result.slope), 0, accuracy: 0.05)
    }

    func testForecastFollowsSeasonAndBandContainsIt() throws {
        let result = try XCTUnwrap(SeasonalForecast.fit(series(months: 48)))
        XCTAssertEqual(result.forecast.count, 12)
        let april = try XCTUnwrap(result.forecast.first { $0.point.month == 4 })
        let october = try XCTUnwrap(result.forecast.first { $0.point.month == 10 })
        XCTAssertEqual(april.value - october.value, 6, accuracy: 1.0)
        for f in result.forecast {
            XCTAssertLessThanOrEqual(f.lower, f.value)
            XCTAssertGreaterThanOrEqual(f.upper, f.value)
        }
        XCTAssertEqual(april.upper - april.value, 1.5 * result.residualSD, accuracy: 1e-9)
    }

    func testRecoversLinearTrend() throws {
        let result = try XCTUnwrap(SeasonalForecast.fit(series(months: 48, slope: 0.1, noise: 0.1)))
        XCTAssertEqual(result.slope, 0.1, accuracy: 0.03)
    }

    func testShortSeriesUsesLargestWindowAndIsLabeled() throws {
        let result = try XCTUnwrap(SeasonalForecast.fit(series(months: 12)))
        XCTAssertEqual(result.window, 12)
        XCTAssertFalse(result.usedPreferredWindow)
    }

    func testNeverFitsFewerThanThreePoints() {
        XCTAssertNil(SeasonalForecast.fit(series(months: 2)))
        XCTAssertNotNil(SeasonalForecast.fit(series(months: 3)))
        XCTAssertFalse(SeasonalForecast.shouldShowPersonalOverlay(pointCount: 2))
        XCTAssertTrue(SeasonalForecast.shouldShowPersonalOverlay(pointCount: 3))
    }

    func testInsightNamesPeakAndFlagsLimit() throws {
        // Nitrate-like series peaking in April, high enough that the upper band reaches 10 mg/L.
        let points = series(months: 48).map { SeasonalForecast.Point(index: $0.index, value: $0.value - 3) }
        let result = try XCTUnwrap(SeasonalForecast.fit(points))
        let insight = SeasonalInsight.make(for: result, contaminant: .nitrate, county: "Johnston")
        XCTAssertTrue(insight.text.contains("April"), insight.text)
        XCTAssertTrue(insight.text.contains("Johnston County"), insight.text)
        XCTAssertFalse(insight.limitRiskMonths.isEmpty)
    }

    func testCSVParsing() {
        let csv = """
        # sample: true
        county,contaminant,month,year,median,p90,n
        Johnston,nitrate,4,2023,3.1,7.9,42
        Johnston,nitrate,13,2023,3.1,7.9,42
        Johnston,unobtainium,4,2023,3.1,7.9,42
        bad,row
        Wake,manganese,1,2024,55,120,10
        """
        let data = CountyTrendData.parse(csv)
        XCTAssertTrue(data.isSample)
        XCTAssertEqual(data.records.count, 2)
        XCTAssertEqual(data.counties, ["Johnston", "Wake"])
        XCTAssertEqual(data.contaminants(in: "Wake"), [.manganese])
    }

    func testBundledSampleLoads() throws {
        let data = try XCTUnwrap(CountyTrendData.loadBundled(from: .main))
        XCTAssertTrue(data.isSample)
        XCTAssertNotNil(SeasonalForecast.fit(data.series(county: "Johnston", contaminant: .nitrate)))
    }
}
