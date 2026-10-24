//
//  WaterSourceModeTests.swift
//  ClearWellNCTests
//
//  Water source answers: what each one shows, storage compatibility, and utility report findings.
//

import XCTest
@testable import ClearWellNC

final class WaterSourceModeTests: XCTestCase {

    func testWellUsersNeverSeeCityTopics() {
        let topics = WaterSource.privateWell.topics
        XCTAssertTrue(topics.isSuperset(of: WaterTopic.well))
        XCTAssertTrue(topics.isDisjoint(with: WaterTopic.city))
        XCTAssertTrue(topics.isSuperset(of: WaterTopic.shared))
    }

    func testCityUsersNeverSeeWellTopics() {
        let topics = WaterSource.publicWater.topics
        XCTAssertTrue(topics.isSuperset(of: WaterTopic.city))
        XCTAssertTrue(topics.isDisjoint(with: WaterTopic.well))
        XCTAssertTrue(topics.isSuperset(of: WaterTopic.shared))
        XCTAssertFalse(WaterSource.publicWater.showsWellCare)
    }

    func testBothAndNotSureSeeEverything() {
        for source in [WaterSource.both, .notSure] {
            XCTAssertEqual(source.topics, Set(WaterTopic.allCases), "\(source)")
        }
        XCTAssertTrue(WaterSource.both.hasWell)
        XCTAssertTrue(WaterSource.both.hasUtility)
        XCTAssertFalse(WaterSource.notSure.hasWell)
        XCTAssertFalse(WaterSource.notSure.hasUtility)
    }

    func testLearnAlwaysAvailable() {
        for source in WaterSource.allCases {
            XCTAssertTrue(source.topics.contains(.learn))
        }
    }

    func testKeyContaminantsMatchSource() {
        XCTAssertTrue(WaterSource.privateWell.keyContaminants.contains(.nitrate))
        XCTAssertFalse(WaterSource.privateWell.keyContaminants.contains(.copper))
        XCTAssertTrue(WaterSource.publicWater.keyContaminants.contains(.lead))
        XCTAssertFalse(WaterSource.publicWater.keyContaminants.contains(.radon))
        let both = WaterSource.both.keyContaminants
        XCTAssertEqual(both.count, Set(both).count, "No duplicates")
    }

    /// Raw values are stored in UserDefaults; changing them would lose users' answers.
    func testStoredRawValuesAreStable() {
        XCTAssertEqual(WaterSource.privateWell.rawValue, "privateWell")
        XCTAssertEqual(WaterSource.publicWater.rawValue, "publicWater")
        XCTAssertEqual(WaterSource.notSure.rawValue, "notSure")
        XCTAssertEqual(WaterSource(storedValue: "privateWell"), .privateWell)
        XCTAssertEqual(WaterSource(storedValue: "somethingOld"), .notSure)
        XCTAssertEqual(WaterSource(storedValue: nil), .notSure)
    }

    @MainActor
    func testSettingsKeepWaterSourceAndUtilityReportPerScope() {
        let suite = "WaterSourceModeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(defaults: defaults)
        settings.waterSource = .publicWater
        var report = UtilityReport()
        report.utilityName = "Sample Utility"
        report.leadP90PPB = 4
        settings.utilityReport = report

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.waterSource, .publicWater)
        XCTAssertEqual(reloaded.utilityReport, report)

        // Demo Mode never sees or overwrites the real answers.
        reloaded.demoEnabled = true
        XCTAssertNotEqual(reloaded.utilityReport, report)
        reloaded.demoEnabled = false
        XCTAssertEqual(reloaded.utilityReport, report)
    }

    func testUtilityFindingsSortedAndFlagged() {
        var report = UtilityReport()
        report.leadP90PPB = 5          // 33% of 15
        report.tthmPPB = 85            // over 80
        report.pfoaPPT = 2             // 50% of 4
        let findings = UtilityReportRules.findings(for: report)
        XCTAssertEqual(findings.map(\.kind), [.tthm, .pfoa, .lead])
        XCTAssertTrue(findings[0].isAbove)
        XCTAssertFalse(findings[2].isAbove)
        XCTAssertTrue(findings.allSatisfy { $0.limit.source.needsVerification })
    }

    func testTapLeadTestRecommendedForOlderHomes() {
        XCTAssertTrue(UtilityReportRules.shouldTestTapForLead(report: UtilityReport(), homeBuiltBefore1986: true))
        XCTAssertTrue(UtilityReportRules.shouldTestTapForLead(report: UtilityReport(), homeBuiltBefore1986: nil))
        XCTAssertFalse(UtilityReportRules.shouldTestTapForLead(report: UtilityReport(), homeBuiltBefore1986: false))
    }
}
