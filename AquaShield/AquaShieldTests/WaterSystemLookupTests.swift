//
//  WaterSystemLookupTests.swift
//  AquaShieldTests
//
//  Point-in-polygon lookup against EPA water system boundaries, every estimate branch, and the onboarding
//  flag's persistence rules.
//

import XCTest
@testable import AquaShield

final class WaterSystemLookupTests: XCTestCase {
    override func tearDown() {
        Wording.source = .notSure
    }


    /// Test fixture only (not real boundaries): a square system with a hole, and a two-part modeled system.
    private let fixture = """
    {"type":"FeatureCollection","features":[
     {"type":"Feature","properties":{"pwsid":"TEST1","name":"SAMPLE CITY","population":5000,"sourced":true},
      "geometry":{"type":"Polygon","coordinates":[[[0,0],[10,0],[10,10],[0,10],[0,0]],[[4,4],[6,4],[6,6],[4,6],[4,4]]]}},
     {"type":"Feature","properties":{"pwsid":"TEST2","name":"SAMPLE MODELED","population":200,"sourced":false},
      "geometry":{"type":"MultiPolygon","coordinates":[[[[20,0],[22,0],[22,2],[20,2],[20,0]]],[[[30,0],[32,0],[32,2],[30,2],[30,0]]]]}},
     {"type":"Feature","properties":{"pwsid":"TEST3","name":"SAMPLE OVERLAP","population":90000,"sourced":false},
      "geometry":{"type":"Polygon","coordinates":[[[8,8],[12,8],[12,12],[8,12],[8,8]]]}}
    ]}
    """

    private func index() throws -> WaterSystemIndex {
        try WaterSystemIndex.parse(Data(fixture.utf8))
    }

    func testPointInPolygonWithHoleAndMultiPolygon() throws {
        let index = try index()
        XCTAssertEqual(index.areas.count, 3)
        XCTAssertEqual(index.systems(containingLatitude: 2, longitude: 2).map(\.pwsid), ["TEST1"])
        XCTAssertTrue(index.systems(containingLatitude: 5, longitude: 5).isEmpty, "Inside the hole")
        XCTAssertEqual(index.systems(containingLatitude: 1, longitude: 31).map(\.pwsid), ["TEST2"], "Second part")
        XCTAssertTrue(index.systems(containingLatitude: 1, longitude: 25).isEmpty, "Between parts")
        XCTAssertTrue(index.systems(containingLatitude: -1, longitude: 2).isEmpty)
    }

    func testSourcedBoundaryWinsOverModeledOverlap() throws {
        // (9, 9) is inside both TEST1 (sourced) and TEST3 (modeled, larger population).
        XCTAssertEqual(try index().systems(containingLatitude: 9, longitude: 9).map(\.pwsid), ["TEST1", "TEST3"])
    }

    func testEveryConfidenceBranch() throws {
        let index = try index()
        let city = WaterSourceEstimate.estimate(latitude: 2, longitude: 2, index: index)
        XCTAssertEqual(city.kind, .likelyCity)
        XCTAssertEqual(city.confidence, .high)
        XCTAssertEqual(city.suggestedSource, .publicWater)
        XCTAssertTrue(city.headline.contains("Sample City"))

        let modeled = WaterSourceEstimate.estimate(latitude: 1, longitude: 21, index: index)
        XCTAssertEqual(modeled.kind, .probablyCity)
        XCTAssertEqual(modeled.confidence, .medium)

        let well = WaterSourceEstimate.estimate(latitude: 50, longitude: 50, index: index, tractWellsTested: 40)
        XCTAssertEqual(well.kind, .likelyWell)
        XCTAssertEqual(well.confidence, .medium)
        XCTAssertEqual(well.suggestedSource, .privateWell)
        XCTAssertEqual(well.tractWellsTested, 40)

        XCTAssertEqual(WaterSourceEstimate.estimate(latitude: nil, longitude: nil, index: index).kind, .unknown)
        XCTAssertEqual(WaterSourceEstimate.estimate(latitude: 2, longitude: 2, index: nil).kind, .unknown)
        XCTAssertEqual(WaterSourceEstimate(kind: .unknown).confidence, .none)
        XCTAssertNil(WaterSourceEstimate(kind: .unknown).suggestedSource)
    }

    // MARK: Real bundled EPA data

    private func bundled() throws -> WaterSystemIndex {
        try XCTUnwrap(WaterSystemIndex.bundled, "nc_water_systems.geojson should be bundled")
    }

    func testCaryTownHallIsCityWaterFromCary() throws {
        // Cary Town Hall, 316 N Academy St, Cary NC.
        let estimate = WaterSourceEstimate.estimate(latitude: 35.7880, longitude: -78.7811, index: try bundled())
        XCTAssertEqual(estimate.kind, .likelyCity)
        XCTAssertEqual(estimate.pwsid, "NC0392020")
        XCTAssertEqual(estimate.systemName?.uppercased(), "CARY, TOWN OF")
    }

    func testModeledBoundaryIsProbablyCity() throws {
        let estimate = WaterSourceEstimate.estimate(latitude: 35.13566, longitude: -83.09114, index: try bundled())
        XCTAssertEqual(estimate.kind, .probablyCity)
        XCTAssertEqual(estimate.pwsid, "NC0150178")
    }

    func testRuralPointIsLikelyWell() throws {
        XCTAssertEqual(WaterSourceEstimate.estimate(latitude: 35.60, longitude: -79.35, index: try bundled()).kind, .likelyWell)
        XCTAssertEqual(WaterSourceEstimate.estimate(latitude: 36.45, longitude: -81.05, index: try bundled()).kind, .likelyWell)
    }

    func testBundledDataHasSourceMetadata() throws {
        let info = try XCTUnwrap(WaterSystemIndex.info)
        XCTAssertTrue(info.sourceURL.contains("epa.gov"))
        XCTAssertGreaterThan(info.systems, 1000)
        XCTAssertEqual(try bundled().areas.count, info.systems)
    }

    // MARK: Onboarding flag

    @MainActor
    func testOnboardingFlagRules() {
        let suite = "Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedOnboarding)

        // The old AppStorage flag carries over once.
        defaults.set(true, forKey: StorageKey.hasOnboarded)
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.hasCompletedOnboarding)

        // Demo Mode never changes it.
        settings.demoEnabled = true
        XCTAssertTrue(settings.hasCompletedOnboarding)
        settings.demoEnabled = false
        XCTAssertTrue(AppSettings(defaults: defaults).hasCompletedOnboarding)

        // Only Reset app clears it, and it stays cleared after relaunch.
        settings.resetRealData()
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }

    @MainActor
    func testAddressAndEstimatePersist() {
        let suite = "Address.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AppSettings(defaults: defaults)
        let home = HomeLocation(address: "316 N Academy St, Cary", latitude: 35.788, longitude: -78.7811, county: "Wake")
        settings.homeLocation = home
        settings.waterSourceEstimate = WaterSourceEstimate(kind: .likelyCity, systemName: "Cary, Town Of")
        settings.waterSource = .publicWater
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.homeLocation, home)
        XCTAssertEqual(reloaded.waterSourceEstimate?.kind, .likelyCity)
        XCTAssertEqual(reloaded.waterSource, .publicWater, "The confirmed answer is what's stored as the source")
    }
}
