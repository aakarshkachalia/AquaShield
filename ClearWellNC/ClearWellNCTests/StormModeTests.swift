//
//  StormModeTests.swift
//  ClearWellNCTests
//

import XCTest
@testable import ClearWellNC

final class StormModeTests: XCTestCase {

    func testFiveStepsInOrder() {
        XCTAssertEqual(StormChecklist.steps.map(\.id), [1, 2, 3, 4, 5])
        XCTAssertTrue(StormChecklist.steps[0].title.contains("Don't drink"))
        XCTAssertTrue(StormChecklist.steps[4].title.contains("1–2 weeks"))
    }

    func testProgress() {
        XCTAssertEqual(StormChecklist.progress([]), 0)
        XCTAssertEqual(StormChecklist.progress([1, 2]), 0.4, accuracy: 1e-9)
        XCTAssertEqual(StormChecklist.progress([1, 2, 3, 4, 5, 99]), 1, accuracy: 1e-9)
    }

    @MainActor
    func testChecklistIsSavedAndKeptSeparateInDemoMode() {
        let defaults = UserDefaults(suiteName: "StormModeTests")!
        defaults.removePersistentDomain(forName: "StormModeTests")
        let settings = AppSettings(defaults: defaults)
        settings.stormChecked = [1, 3]
        XCTAssertEqual(AppSettings(defaults: defaults).stormChecked, [1, 3], "Checklist persists")

        settings.demoEnabled = true
        XCTAssertTrue(settings.stormChecked.isEmpty, "Demo Mode starts with its own checklist")
        settings.stormChecked = [5]
        settings.demoEnabled = false
        XCTAssertEqual(settings.stormChecked, [1, 3], "Real answers come back after Demo Mode")
        defaults.removePersistentDomain(forName: "StormModeTests")
    }
}
