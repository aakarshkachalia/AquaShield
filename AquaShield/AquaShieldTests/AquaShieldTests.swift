//
//  AquaShieldTests.swift
//  AquaShieldTests
//

import CoreLocation
import XCTest
@testable import AquaShield

final class RiskEngineTests: XCTestCase {

    /// Parsing the GeoJSON takes a moment, so share one copy across all tests.
    private static var cached: TractDatabase?

    private func database() throws -> TractDatabase {
        if let db = Self.cached { return db }
        let db = try TractDatabase.load(from: .main)
        Self.cached = db
        return db
    }

    private func report(_ fips: String) throws -> RiskReport {
        let db = try database()
        let tract = try XCTUnwrap(db.tract(fips: fips), "Tract \(fips) missing")
        return RiskEngine.report(for: tract, meta: db.meta)
    }

    // MARK: Loading

    func testLoadsAllTracts() throws {
        let db = try database()
        XCTAssertEqual(db.tracts.count, 2195)
        XCTAssertEqual(db.meta.statewideRate(for: .arsenic), 0.0227, accuracy: 1e-9)
        XCTAssertEqual(db.meta.modelScores.count, 4)
    }

    // MARK: Union County tract

    func testUnionCountyTractLevels() throws {
        let r = try report("37179020502")
        XCTAssertEqual(r.countyName, "Union")
        XCTAssertEqual(r.risk(for: .arsenic)?.level, .high)
        XCTAssertEqual(r.risk(for: .nitrate)?.level, .high)
        XCTAssertEqual(r.risk(for: .manganese)?.level, .typical)
        XCTAssertEqual(r.risk(for: .lead)?.level, .testRegardless)
    }

    func testUnionCountyArsenicText() throws {
        let arsenic = try XCTUnwrap(report("37179020502").risk(for: .arsenic))
        XCTAssertEqual(arsenic.oneInText, "about 1 in 5")
        XCTAssertEqual(arsenic.observedText, "8 of 52 tested wells in your census tract were above the limit.")
        XCTAssertEqual(arsenic.confidence.level, .high)
    }

    func testCardOrderAndTestPlan() throws {
        let r = try report("37179020502")
        // Arsenic (ratio ~8.3) and nitrate (~4.8) are both High; larger ratio first.
        XCTAssertEqual(r.risks.map(\.contaminant), [.arsenic, .nitrate, .manganese, .lead])
        XCTAssertEqual(r.testPlan, [
            "Bacteria (total coliform / E. coli): every year and after any flooding, for every well.",
            "Arsenic: a priority for your area (high risk).",
            "Nitrate: a priority for your area (high risk).",
            "Manganese: include in a standard metals and nitrate panel every 2 years.",
            "Lead: test at least once; it depends on your home's plumbing.",
            "How: contact Union County Environmental Health to order a test through the NC State Laboratory of Public Health, or use a state-certified private lab.",
        ])
    }

    // MARK: Brunswick County tract (no tests)

    func testBrunswickTractHasNoTests() throws {
        let r = try report("37019020201")
        XCTAssertEqual(r.countyName, "Brunswick")
        let arsenic = try XCTUnwrap(r.risk(for: .arsenic))
        XCTAssertEqual(arsenic.tests, 0)
        XCTAssertNil(arsenic.observedText)
        XCTAssertEqual(arsenic.confidence.level, .low)
        XCTAssertEqual(arsenic.confidence.note,
                       "No wells in your census tract have been tested. This is the model's estimate from geology and nearby areas.")
    }

    // MARK: Pure logic

    func testCountyNames() {
        XCTAssertEqual(CountyNames.name(forFIPS: "183"), "Wake")
        XCTAssertEqual(CountyNames.name(forFIPS: "179"), "Union")
        XCTAssertEqual(CountyNames.name(forFIPS: "001"), "Alamance")
        XCTAssertEqual(CountyNames.name(forFIPS: "199"), "Yancey")
        XCTAssertNil(CountyNames.name(forFIPS: "002"))
        XCTAssertNil(CountyNames.name(forFIPS: "201"))
    }

    func testOneIn() {
        XCTAssertEqual(RiskEngine.oneIn(0.004), "fewer than 1 in 200")
        XCTAssertEqual(RiskEngine.oneIn(0.005), "about 1 in 200")
        XCTAssertEqual(RiskEngine.oneIn(0.9), "about 1 in 2")
        XCTAssertEqual(RiskEngine.oneIn(0.0227), "about 1 in 44")
    }

    func testLevelThresholds() {
        XCTAssertEqual(RiskLevel.level(for: .arsenic, ratio: 3), .high)
        XCTAssertEqual(RiskLevel.level(for: .arsenic, ratio: 2.99), .elevated)
        XCTAssertEqual(RiskLevel.level(for: .arsenic, ratio: 1.5), .elevated)
        XCTAssertEqual(RiskLevel.level(for: .arsenic, ratio: 0.75), .typical)
        XCTAssertEqual(RiskLevel.level(for: .arsenic, ratio: 0.74), .lowerThanTypical)
        XCTAssertEqual(RiskLevel.level(for: .lead, ratio: 10), .testRegardless)
    }

    func testConfidenceBands() {
        XCTAssertEqual(Confidence(tests: 30).level, .high)
        XCTAssertEqual(Confidence(tests: 29).level, .medium)
        XCTAssertEqual(Confidence(tests: 10).level, .medium)
        XCTAssertEqual(Confidence(tests: 9).level, .low)
        XCTAssertTrue(Confidence(tests: 3).note.contains("mostly the model's estimate"))
    }

    func testPluralization() {
        XCTAssertEqual(Confidence(tests: 1).note,
                       "Only 1 tested well in your census tract, so this is mostly the model's estimate.")
        XCTAssertEqual(Confidence(tests: 3).note,
                       "Only 3 tested wells in your census tract, so this is mostly the model's estimate.")
        let one = ContaminantRisk(contaminant: .arsenic, data: ContaminantData(estimate: 0.1, tests: 1, aboveLimit: 0),
                                  statewide: 0.0227)
        XCTAssertEqual(one.observedText, "0 of 1 tested well in your census tract was above the limit.")
    }

    func testMetaDecodesWithAndWithoutRange() throws {
        func decode(_ extra: String) throws -> ModelScore {
            let json = """
            {"contaminant": "arsenic", "county_average": 0.3613, "neighbors_only": 0.6717,
             "MODEL_unseen_tract": 0.7016, "model_unseen_county": 0.362\(extra)}
            """
            return try JSONDecoder().decode(ModelScore.self, from: Data(json.utf8))
        }
        let ranged = try decode(#", "unseen_county_min": 0.328, "unseen_county_max": 0.415"#)
        XCTAssertEqual(ranged.unseenCountyMin, 0.328)
        XCTAssertEqual(ranged.unseenCountyMax, 0.415)
        XCTAssertNil(try decode("").unseenCountyMin)
    }

    func testPointInPolygonWithHole() {
        let square = [(0.0, 0.0), (10, 0), (10, 10), (0, 10), (0, 0)].map { GeoPoint(lon: $0.0, lat: $0.1) }
        let hole = [(4.0, 4.0), (6, 4), (6, 6), (4, 6), (4, 4)].map { GeoPoint(lon: $0.0, lat: $0.1) }
        let poly = GeoPolygon(rings: [square, hole])
        XCTAssertTrue(poly.contains(GeoPoint(lon: 2, lat: 2)))
        XCTAssertFalse(poly.contains(GeoPoint(lon: 5, lat: 5)))
        XCTAssertFalse(poly.contains(GeoPoint(lon: 11, lat: 5)))
    }

    // MARK: Well Record

    func testUnitConversion() {
        XCTAssertEqual(ConcentrationUnit.convert(0.012, from: .mgL, to: .ppb), 12, accuracy: 1e-9)
        XCTAssertEqual(ConcentrationUnit.convert(5000, from: .ppb, to: .mgL), 5, accuracy: 1e-9)
    }

    func testLabLimits() {
        // New rule from the interpretation layer: >= 100% of a limit is "Above limit".
        XCTAssertEqual(Analyte.arsenic.evaluate(4).kind, .pass)
        XCTAssertEqual(Analyte.arsenic.evaluate(10).kind, .above)
        XCTAssertEqual(Analyte.lead.evaluate(16).kind, .above)
        XCTAssertEqual(Analyte.manganese.evaluate(60).kind, .notice)    // above aesthetic guideline only
        XCTAssertEqual(Analyte.manganese.evaluate(301).kind, .above)    // above health advisory
        XCTAssertEqual(Analyte.nitrate.evaluate(11).kind, .above)
        XCTAssertEqual(Analyte.iron.evaluate(400).kind, .notice)
        XCTAssertTrue(Analyte.pH.evaluate(7).isPass)
        XCTAssertEqual(Analyte.pH.evaluate(6.4).kind, .notice)
        XCTAssertEqual(Analyte.evaluate(bacteria: .present).kind, .above)
    }

    // MARK: Reminders

    func testFireDate() {
        let cal = Calendar.current
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
        let future = cal.date(from: DateComponents(year: 2026, month: 12, day: 1))!
        XCTAssertEqual(ReminderPlanner.fireDate(due: future, now: now),
                       cal.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 9)))
        let past = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        XCTAssertEqual(ReminderPlanner.fireDate(due: past, now: now),
                       cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 9)))
    }

    // MARK: Weather alerts

    func testWellRelevantAlerts() {
        for event in ["Flood Watch", "Flood Warning", "Flash Flood Warning", "Coastal Flood Watch",
                      "Hurricane Warning", "Hurricane Watch", "Tropical Storm Warning"] {
            XCTAssertTrue(WeatherAlert.isWellRelevant(event: event), event)
        }
        for event in ["Flood Advisory", "Heat Advisory", "Winter Storm Warning", "Tornado Watch"] {
            XCTAssertFalse(WeatherAlert.isWellRelevant(event: event), event)
        }
    }

    func testParseNWSAlerts() throws {
        let json = """
        {"type": "FeatureCollection", "features": [
          {"id": "https://api.weather.gov/alerts/abc", "properties": {
            "id": "urn:oid:abc", "event": "Flood Warning", "headline": "Flood Warning issued",
            "areaDesc": "Union", "ends": "2026-10-11T18:00:00-04:00", "expires": null}}
        ]}
        """
        let alerts = try NWSClient.parse(Data(json.utf8))
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts.first?.id, "urn:oid:abc")
        XCTAssertTrue(alerts.first?.isWellRelevant ?? false)
        XCTAssertNotNil(alerts.first?.ends)
    }

    // MARK: How it works

    func testStressTestText() throws {
        let json = """
        {"contaminant": "arsenic", "county_average": 0.3613, "neighbors_only": 0.6717,
         "MODEL_unseen_tract": 0.7016, "model_unseen_county": 0.3619,
         "unseen_county_min": 0.3276, "unseen_county_max": 0.4153}
        """
        let score = try JSONDecoder().decode(ModelScore.self, from: Data(json.utf8))
        XCTAssertEqual(score.stressTestText, "36.2% (32.8–41.5%)")
    }

    // MARK: Location lookup

    func testMonroeIsInUnionCounty() throws {
        let tract = try XCTUnwrap(try database().tract(containing: CLLocationCoordinate2D(latitude: 34.9716, longitude: -80.5510)))
        XCTAssertEqual(tract.countyFIPS, "179")
        XCTAssertEqual(tract.countyName, "Union")
    }

    func testNorfolkVirginiaIsOutsideNC() throws {
        XCTAssertNil(try database().tract(containing: CLLocationCoordinate2D(latitude: 36.85, longitude: -76.29)))
    }
}
