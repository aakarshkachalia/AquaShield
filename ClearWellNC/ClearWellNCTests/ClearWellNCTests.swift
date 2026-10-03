//
//  ClearWellNCTests.swift
//  ClearWellNCTests
//

import CoreLocation
import XCTest
@testable import ClearWellNC

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

    func testPointInPolygonWithHole() {
        let square = [(0.0, 0.0), (10, 0), (10, 10), (0, 10), (0, 0)].map { GeoPoint(lon: $0.0, lat: $0.1) }
        let hole = [(4.0, 4.0), (6, 4), (6, 6), (4, 6), (4, 4)].map { GeoPoint(lon: $0.0, lat: $0.1) }
        let poly = GeoPolygon(rings: [square, hole])
        XCTAssertTrue(poly.contains(GeoPoint(lon: 2, lat: 2)))
        XCTAssertFalse(poly.contains(GeoPoint(lon: 5, lat: 5)))
        XCTAssertFalse(poly.contains(GeoPoint(lon: 11, lat: 5)))
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
