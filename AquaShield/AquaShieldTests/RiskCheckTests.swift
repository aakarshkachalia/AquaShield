//
//  RiskCheckTests.swift
//  AquaShieldTests
//

import XCTest
@testable import AquaShield

final class RiskCheckTests: XCTestCase {

    private func data(_ records: [CountyWellRecord]) -> CountyWellData {
        CountyWellData(sample: true, source: "test", records: records)
    }

    private func record(_ county: String, _ contaminant: String, pct: Double, n: Int) -> CountyWellRecord {
        CountyWellRecord(county: county, contaminant: contaminant, pctAboveStandard: pct, meanConcentration: 1,
                         unit: "ppb", nWells: n, sample: true)
    }

    private func recommend(_ answers: RiskCheckAnswers, data: CountyWellData? = nil,
                           pfas: Set<String> = []) -> RiskCheckResult {
        RiskCheckEngine.recommend(answers: answers, countyData: data, trends: nil, pfasCounties: pfas)
    }

    func testAlwaysRecommendsBacteriaNitrateArsenic() {
        let ids = recommend(RiskCheckAnswers()).tests.map(\.id)
        XCTAssertEqual(Array(ids.prefix(3)), [.bacteria, .nitrate, .arsenic])
    }

    func testInfantMakesNitrateReasonSpecific() throws {
        var answers = RiskCheckAnswers()
        answers.pregnantOrInfant = true
        let nitrate = try XCTUnwrap(recommend(answers).tests.first { $0.id == .nitrate })
        XCTAssertEqual(nitrate.reason, "An infant or pregnant person lives in your home, and nitrate is most dangerous for babies under 6 months.")
        XCTAssertTrue(recommend(answers).tests.contains { $0.id == .lead })
    }

    func testFloodingLeadsWithBacteria() throws {
        var answers = RiskCheckAnswers()
        answers.flooding = true
        let bacteria = try XCTUnwrap(recommend(answers).tests.first { $0.id == .bacteria })
        XCTAssertTrue(bacteria.reason.contains("Floodwater"))
    }

    func testNeverTestedAddsFullPanel() {
        var answers = RiskCheckAnswers()
        answers.lastTest = .never
        let ids = Set(recommend(answers).tests.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: [.lead, .manganese, .pH]))
    }

    func testChangesAddStainingTests() {
        var answers = RiskCheckAnswers()
        answers.noticedChanges = true
        let ids = Set(recommend(answers).tests.map(\.id))
        XCTAssertTrue(ids.isSuperset(of: [.iron, .manganese, .pH, .hardness]))
    }

    func testCountyDataAddsTestsAndFacts() throws {
        var answers = RiskCheckAnswers()
        answers.county = "Union"
        let result = recommend(answers, data: data([record("Union", "uranium", pct: 8, n: 40),
                                                    record("Union", "arsenic", pct: 19.5, n: 5154)]))
        XCTAssertTrue(result.tests.contains { $0.id == .uranium })
        let arsenic = try XCTUnwrap(result.tests.first { $0.id == .arsenic })
        XCTAssertEqual(arsenic.reason, "In Union County, 19.5% of tested wells were above the arsenic standard.")
        XCTAssertEqual(result.countyFacts.first?.contaminant, .arsenic)
        XCTAssertTrue(result.isSampleData)
    }

    func testStatsFromFewerThanTenWellsAreHidden() {
        var answers = RiskCheckAnswers()
        answers.county = "Hyde"
        let result = recommend(answers, data: data([record("Hyde", "radon", pct: 20, n: 9)]))
        XCTAssertTrue(result.countyFacts.isEmpty)
        XCTAssertFalse(result.tests.contains { $0.id == .radon })
    }

    func testPFASCountiesGetPFASTest() {
        var answers = RiskCheckAnswers()
        answers.county = "Bladen"
        XCTAssertTrue(recommend(answers, pfas: ["Bladen"]).tests.contains { $0.id == .pfas })
    }

    func testNeverCallsAWellSafe() {
        var answers = RiskCheckAnswers()
        answers.county = "Wake"
        answers.wellAge = .after2008
        answers.pregnantOrInfant = false
        answers.flooding = false
        answers.nearbySources = false
        answers.lastTest = .oneToThreeYears
        answers.noticedChanges = false
        let result = recommend(answers, data: data([record("Wake", "arsenic", pct: 0, n: 500)]))
        let text = (result.tests.flatMap(\.reasons) + result.countyFacts.map(\.text) + [result.bestTimeToTest])
            .joined(separator: " ").lowercased()
        XCTAssertFalse(text.contains("safe"), text)
        XCTAssertFalse(result.tests.isEmpty, "Even the lowest-risk answers still recommend testing")
        XCTAssertEqual(RiskCheckResult.disclaimer, "Only a lab test can tell you what's in your water.")
    }

    func testBundledCountyDataCoversAll100Counties() throws {
        let data = try XCTUnwrap(CountyWellData.loadBundled(from: .main))
        XCTAssertTrue(data.sample)
        XCTAssertEqual(Set(data.records.map(\.county)), Set(CountyNames.all))
        XCTAssertTrue(data.records.allSatisfy(\.sample))
        XCTAssertTrue(data.records.allSatisfy { $0.contaminantID != nil })
    }

    func testBestTimeComesFromSeasonalModel() throws {
        let trends = try XCTUnwrap(CountyTrendData.loadBundled(from: .main))
        XCTAssertTrue(RiskCheckEngine.bestTime(county: "Johnston", trends: trends).contains("Johnston County"))
        XCTAssertTrue(RiskCheckEngine.bestTime(county: "Hyde", trends: trends).hasPrefix("Any time of year"))
    }
}
