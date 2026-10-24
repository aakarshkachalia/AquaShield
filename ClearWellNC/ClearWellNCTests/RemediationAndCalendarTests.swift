//
//  RemediationAndCalendarTests.swift
//  ClearWellNCTests
//
//  Remediation plan, testing calendar, network opt-in migration, and stored formats for taps and filters.
//

import XCTest
@testable import ClearWellNC

final class RemediationAndCalendarTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let source = SourceRef("Test")

    private func product(_ id: String, _ type: FilterType, _ claims: [(ClaimTarget, CertificationStandard, Double)],
                         annual: Double? = nil) -> FilterProduct {
        FilterProduct(id: id, brand: "Sample", model: id, type: type,
                      claims: claims.map { CertificationClaim(standard: $0.1, certifier: .nsf, target: $0.0,
                                                              reductionPercent: 99, influentChallengeConcentration: $0.2,
                                                              source: source) },
                      annualCostUSD: annual, source: source)
    }

    private func kitchen(_ readings: [Reading?]) -> TapScoreResult {
        WellHealthScore.tapScore(tap: .kitchen, source: .privateWell, readings: readings.compactMap { $0 }, filters: [], now: now)
    }

    func testOnlyProductsCoveringDriversAtMeasuredLevels() {
        let drinking = kitchen([.amount(.arsenic, 20), .amount(.nitrate, 1)])
        let products = [
            product("ro", .reverseOsmosis, [(.arsenic, .nsf58, 300)], annual: 120),
            product("lowChallenge", .underSinkCarbon, [(.arsenic, .nsf53, 10)], annual: 50),   // tested below 20
            product("leadOnly", .pitcher, [(.lead, .nsf53, 150)], annual: 30),
            product("uncertified", .pitcher, [], annual: 10),
        ]
        let plan = Remediation.plan(source: .privateWell, drinking: drinking, showers: [], home: HomeProfile(),
                                    members: [], products: products, now: now)
        XCTAssertEqual(plan.drivers, [.arsenic])
        XCTAssertEqual(plan.allMatches.map(\.id), ["ro"])
        XCTAssertEqual(plan.affordablePick?.id, "ro")
        XCTAssertTrue(plan.fixes.contains { $0.kind == .retest })
    }

    func testSortedByCoverageThenCost() {
        let drinking = kitchen([.amount(.arsenic, 20), .amount(.lead, 20)])
        let products = [
            product("cheapPartial", .underSinkCarbon, [(.lead, .nsf53, 150)], annual: 20),
            product("fullExpensive", .reverseOsmosis, [(.lead, .nsf58, 150), (.arsenic, .nsf58, 300)], annual: 200),
            product("fullCheap", .reverseOsmosis, [(.lead, .nsf58, 150), (.arsenic, .nsf58, 300)], annual: 100),
        ]
        let plan = Remediation.plan(source: .privateWell, drinking: drinking, showers: [], home: HomeProfile(),
                                    members: [], products: products, now: now)
        XCTAssertEqual(plan.productsByType.first { $0.type == .reverseOsmosis }?.matches.map(\.id), ["fullCheap", "fullExpensive"])
        // The affordable pick is the cheapest certified option, even if it only covers part.
        XCTAssertEqual(plan.affordablePick?.id, "cheapPartial")
    }

    func testGermsInWellGiveNonProductFixesFirst() {
        let drinking = kitchen([.presence(.bacteria, present: true)])
        let plan = Remediation.plan(source: .privateWell, drinking: drinking, showers: [], home: HomeProfile(),
                                    members: [], products: [], now: now)
        let kinds = plan.fixes.map(\.kind)
        XCTAssertEqual(kinds.first, .bottledWater)
        XCTAssertTrue(kinds.contains(.shockChlorinate))
        XCTAssertTrue(kinds.contains(.checkWellCap))
        XCTAssertEqual(kinds.last, .retest)
    }

    func testCityLeadGetsFlushAndServiceLineFixes() {
        let drinking = WellHealthScore.tapScore(tap: .kitchen, source: .publicWater, readings: [.amount(.lead, 12)!],
                                                filters: [], now: now)
        let plan = Remediation.plan(source: .publicWater, drinking: drinking, showers: [], home: HomeProfile(),
                                    members: [], products: [], now: now)
        let kinds = plan.fixes.map(\.kind)
        XCTAssertTrue(kinds.contains(.flushTaps))
        XCTAssertTrue(kinds.contains(.coldWaterOnly))
        XCTAssertTrue(kinds.contains(.askUtilityLeadLine))
        XCTAssertFalse(kinds.contains(.shockChlorinate))
    }

    func testVolatileContaminantsExplainWholeHouse() {
        let shower = WellHealthScore.tapScore(tap: TapLocation(kind: .shower), source: .privateWell,
                                              readings: [.amount(.tthm, 90)!], filters: [], now: now)
        let plan = Remediation.plan(source: .privateWell, drinking: kitchen([.amount(.tthm, 90)]), showers: [shower],
                                    home: HomeProfile(), members: [], products: [], now: now)
        XCTAssertNotNil(plan.volatileNote)
        XCTAssertTrue(plan.volatileNote!.contains("whole-house"))
    }

    func testSkinCareNeverSuggestsHarshHomeRemedies() {
        var member = HouseholdMember()
        member.eczema = true
        let advice = Remediation.skinCare(drinking: nil, showers: [], members: [member], source: .publicWater)
        XCTAssertNotNil(advice)
        let all = (advice!.tips).joined(separator: " ").lowercased()
        XCTAssertFalse(all.contains("lemon"))
        XCTAssertFalse(all.contains("essential oil"))
        XCTAssertTrue(advice!.avoid.joined().lowercased().contains("lemon"))
        XCTAssertNil(advice!.redFlag)
    }

    // MARK: Calendar

    func testWellCalendarYearlyAndPanel() {
        let calendar = Calendar(identifier: .gregorian)
        let lastYear = calendar.date(byAdding: .month, value: -11, to: now)!
        var history = WellTestingCalendar.History()
        history.bacteria = [lastYear]
        history.nitrate = [lastYear]
        history.any = [lastYear]
        let due = WellTestingCalendar.schedule(history: history, source: .privateWell, events: [], now: now, calendar: calendar)
        let yearly = due.first { $0.kind == .bacteriaNitrate }!
        XCTAssertFalse(yearly.isOverdue(at: now))
        XCTAssertTrue(due.first { $0.kind == .fullPanel }!.isOverdue(at: now), "No full panel on file → due now")
    }

    func testCityGetsNoWellCalendar() {
        let due = WellTestingCalendar.schedule(history: .init(), source: .publicWater, events: [], now: now)
        XCTAssertTrue(due.isEmpty)
    }

    func testEventAfterLastTestPromptsRetest() {
        var history = WellTestingCalendar.History()
        history.any = [now.addingTimeInterval(-30 * 86_400)]
        let flood = RetestEvent(kind: .flood, date: now.addingTimeInterval(-86_400))
        let due = WellTestingCalendar.schedule(history: history, source: .privateWell, events: [flood], now: now)
        XCTAssertTrue(due.contains { $0.kind == .afterEvent && $0.isOverdue(at: now) })
        // An event before the last test doesn't.
        let old = RetestEvent(kind: .repair, date: now.addingTimeInterval(-60 * 86_400))
        XCTAssertFalse(WellTestingCalendar.schedule(history: history, source: .privateWell, events: [old], now: now)
            .contains { $0.kind == .afterEvent })
    }

    // MARK: Storage

    func testTapLocationRawValues() {
        XCTAssertEqual(TapLocation(kind: .shower, index: 2).rawValue, "shower.2")
        XCTAssertEqual(TapLocation(rawValue: "shower.2"), TapLocation(kind: .shower, index: 2))
        XCTAssertEqual(TapLocation(rawValue: "kitchen"), .kitchen)
        XCTAssertNil(TapLocation(rawValue: "garage"))
    }

    @MainActor
    func testExistingFiltersMigrateToTheirUsualPlace() {
        // Records saved before locations existed have an empty locationRaw.
        let pitcher = TreatmentSystem(kind: .pitcherFilter, lastServiced: now, intervalMonths: 2)
        XCTAssertEqual(pitcher.location, .kitchen)
        let softener = TreatmentSystem(kind: .softenerSalt, lastServiced: now, intervalMonths: 1)
        XCTAssertEqual(softener.location, .wholeHouse)
        XCTAssertEqual(pitcher.installed(product: nil).product, nil)
        XCTAssertEqual(FilterRules.effect(of: pitcher.installed(product: nil), on: .lead, influent: 10, at: now).flag,
                       .uncertified)
    }

    @MainActor
    func testNetworkOptInMigration() {
        let suite = "OptIns.\(UUID().uuidString)"
        let existing = UserDefaults(suiteName: suite)!
        defer { existing.removePersistentDomain(forName: suite) }
        existing.set(true, forKey: StorageKey.hasOnboarded)
        AppSettings.migrateNetworkOptIns(existing)
        XCTAssertEqual(AppSettings(defaults: existing).networkOptIns, Set(NetworkFeature.allCases),
                       "People already using alerts keep them after the update")

        let suite2 = "OptIns.\(UUID().uuidString)"
        let fresh = UserDefaults(suiteName: suite2)!
        defer { fresh.removePersistentDomain(forName: suite2) }
        AppSettings.migrateNetworkOptIns(fresh)
        fresh.set(true, forKey: StorageKey.hasOnboarded)   // finishes onboarding later
        XCTAssertTrue(AppSettings(defaults: fresh).networkOptIns.isEmpty, "New installs start opted out")
    }

    func testCoarseLocation() {
        XCTAssertEqual(NetworkFeature.coarse(35.779_59), 35.78)
        XCTAssertEqual(NetworkFeature.coarse(-78.638_17), -78.64)
    }

    func testSampleCatalogIsAllFlaggedSamples() throws {
        let url = try XCTUnwrap(Bundle(for: AppSettingsBundleToken.self).url(forResource: "SampleFilterProducts", withExtension: "json")
            ?? Bundle.main.url(forResource: "SampleFilterProducts", withExtension: "json"))
        let catalog = try JSONDecoder().decode(FilterCatalog.self, from: Data(contentsOf: url))
        XCTAssertFalse(catalog.products.isEmpty)
        for product in catalog.products {
            XCTAssertEqual(product.brand, "Sample")
            XCTAssertTrue(product.needsVerification)
        }
    }
}

/// Lets the test find the app bundle.
private final class AppSettingsBundleToken {}
