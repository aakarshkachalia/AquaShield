//
//  AlertCenterTests.swift
//  ClearWellNCTests
//
//  Alerts are ordered by urgency, nudge only when useful, and the bell counts only actionable ones.
//

import XCTest
@testable import ClearWellNC

final class AlertCenterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOrderedBySeverity() {
        var input = AlertCenter.Inputs()
        input.now = now
        input.modes = [.boilWater]
        input.filters = [("Pitcher", 5), ("Shower", -2), ("Fridge", 90)]
        input.weatherEvents = ["Flood Warning"]
        input.safety = [SafetyAlert(kind: .bacteriaBoil, memberIDs: [], title: "Boil water", message: "Germs")]
        let alerts = AlertCenter.alerts(input)
        XCTAssertEqual(alerts.first?.severity, .critical)
        XCTAssertEqual(alerts.last?.severity, .info)
        XCTAssertEqual(alerts.map(\.severity), alerts.map(\.severity).sorted(by: >))
        XCTAssertFalse(alerts.contains { $0.title.contains("Fridge") }, "Not due soon")
        XCTAssertTrue(alerts.contains { $0.id == "filter.Shower" && $0.severity == .warning }, "Overdue")
        XCTAssertTrue(alerts.contains { $0.id == "filter.Pitcher" && $0.severity == .attention }, "Due soon")
        XCTAssertEqual(AlertCenter.badgeCount(alerts), alerts.count - 1, "Modes don't count toward the bell")
    }

    func testMissingTestsOnlyNudgeAfterAResult() {
        var input = AlertCenter.Inputs()
        input.missingTests = [.arsenic, .uranium]
        XCTAssertTrue(AlertCenter.alerts(input).isEmpty)
        input.hasReadings = true
        let alert = AlertCenter.alerts(input).first
        XCTAssertEqual(alert?.action, .findTesting)
        XCTAssertTrue(alert?.title.contains("arsenic") ?? false)
    }

    func testOverdueTestIsWarning() {
        var input = AlertCenter.Inputs()
        input.now = now
        input.tests = [TestDue(kind: .bacteriaNitrate, due: now.addingTimeInterval(-86_400), title: "Bacteria and nitrate test", detail: "")]
        XCTAssertEqual(AlertCenter.alerts(input).first?.severity, .warning)
        input.tests = [TestDue(kind: .fullPanel, due: now.addingTimeInterval(200 * 86_400), title: "Full panel", detail: "")]
        XCTAssertTrue(AlertCenter.alerts(input).isEmpty, "Far-off tests don't nag")
    }

    func testNothingToDoMeansEmptyBell() {
        XCTAssertEqual(AlertCenter.badgeCount(AlertCenter.alerts(.init())), 0)
    }
}
