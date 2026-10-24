//
//  SourceAndPersistenceTests.swift
//  ClearWellNCUITests
//
//  City users never see "well"; well users never see city-only cards; onboarding shows once and resumes
//  where it left off. All runs use the app's separate UI-test storage.
//

import XCTest

final class SourceAndPersistenceTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    // MARK: Part 2: the confirmed source everywhere

    @MainActor
    func testCityModeShowsNoWellWords() {
        let app = launch(["-uiTestReset", "-uiTestSkipOnboarding", "-uiTestSource", "publicWater", "-uiTestSeedResults"])
        var offending: [String] = []
        visitMainScreens(app) { screen in
            offending += self.wellWords(in: app).map { "\(screen): \($0)" }
        }
        XCTAssertTrue(offending.isEmpty, "Well wording shown to a city user:\n" + offending.joined(separator: "\n"))
    }

    @MainActor
    func testWellModeShowsNoCityCards() {
        let app = launch(["-uiTestReset", "-uiTestSkipOnboarding", "-uiTestSource", "privateWell", "-uiTestSeedResults"])
        let cityOnly = ["My water utility", "Add your utility's water report", "Boil-water advisories",
                        "Your water utility is your first call", "For city water"]
        var found: [String] = []
        visitMainScreens(app) { screen in
            for text in cityOnly where app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists {
                found.append("\(screen): \(text)")
            }
        }
        XCTAssertTrue(found.isEmpty, "City-only content shown to a well user:\n" + found.joined(separator: "\n"))
    }

    // MARK: Part 3: first launch only, and persistence

    @MainActor
    func testCompletedOnboardingNeverShowsAgain() {
        let app = launch(["-uiTestReset"])
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.welcome"].waitForExistence(timeout: 5))
        tap(app.buttons["onboarding.getStarted"])
        tap(app.buttons["onboarding.skipAddress"])
        tap(app.buttons["onboarding.continueWithoutAddress"])
        tap(app.buttons["flow.next"])                                        // estimate
        tap(app.descendants(matching: .any)["onboarding.source.publicWater"])
        tap(app.buttons["flow.next"])                                        // confirm
        tap(app.buttons["onboarding.finish"])                                // household
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 5))

        app.terminate()
        let again = launch([])
        XCTAssertTrue(again.tabBars.buttons["Home"].waitForExistence(timeout: 5), "Dashboard after relaunch")
        XCTAssertFalse(again.descendants(matching: .any)["onboarding.welcome"].exists, "Welcome must not come back")
    }

    @MainActor
    func testQuitMidOnboardingResumesSameStep() {
        let app = launch(["-uiTestReset"])
        tap(app.buttons["onboarding.getStarted"])
        tap(app.buttons["onboarding.skipAddress"])
        tap(app.buttons["onboarding.continueWithoutAddress"])
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.estimate"].waitForExistence(timeout: 5))

        app.terminate()
        let again = launch([])
        XCTAssertTrue(again.descendants(matching: .any)["onboarding.estimate"].waitForExistence(timeout: 5),
                      "Resumes at step 3")
        XCTAssertFalse(again.descendants(matching: .any)["onboarding.welcome"].exists)
    }

    @MainActor
    func testDemoModeDoesNotBringBackOnboarding() {
        let app = launch(["-uiTestReset", "-uiTestSkipOnboarding"])
        tap(app.tabBars.buttons["Home"])
        tap(app.navigationBars.buttons["Settings"])
        let demo = app.switches["Demo Mode"]
        XCTAssertTrue(reveal(app, demo))
        toggle(demo)
        let settingsAgain = app.navigationBars.buttons["Settings"]
        if settingsAgain.waitForExistence(timeout: 3) { settingsAgain.tap() }
        let demoAgain = app.switches["Demo Mode"]
        if reveal(app, demoAgain) { toggle(demoAgain) }

        app.terminate()
        let again = launch([])
        XCTAssertTrue(again.tabBars.buttons["Home"].waitForExistence(timeout: 5))
        XCTAssertFalse(again.descendants(matching: .any)["onboarding.welcome"].exists)
    }

    // MARK: Helpers

    @MainActor
    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        // Always use the separate UI-test storage, even on relaunch.
        app.launchArguments = arguments.isEmpty ? ["-uiTestKeep"] : arguments
        app.launch()
        return app
    }

    /// Visits every main screen and runs `check` at the top and after each of 3 scrolls.
    @MainActor
    private func visitMainScreens(_ app: XCUIApplication, check: (String) -> Void) {
        func visit(_ name: String) {
            check(name)
            for _ in 0..<3 { app.swipeUp(); check(name) }
        }
        tap(app.tabBars.buttons["Home"]); visit("Dashboard")
        tap(app.tabBars.buttons["My Water"]); visit("My Water")
        tap(app.tabBars.buttons["Get Help"]); visit("Get Help")
        tap(app.tabBars.buttons["Learn"]); visit("Learn")
        tap(app.tabBars.buttons["Home"])
        if tapIfExists(app.navigationBars.buttons["Settings"]) { visit("Settings") }
    }

    /// Visible text containing the whole word "well" or "wells" (not "as well", not "wellness").
    @MainActor
    private func wellWords(in app: XCUIApplication) -> [String] {
        let regex = try! NSRegularExpression(pattern: "\\bwells?\\b", options: .caseInsensitive)
        let labels = app.descendants(matching: .staticText).allElementsBoundByIndex.map(\.label)
            + app.buttons.allElementsBoundByIndex.map(\.label)
        return Set(labels).filter { label in
            let cleaned = label.replacingOccurrences(of: "as well", with: "", options: .caseInsensitive)
            return regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)) != nil
        }.sorted()
    }

    @MainActor
    private func toggle(_ toggle: XCUIElement) {
        let inner = toggle.switches.firstMatch
        if inner.exists { inner.tap() } else { toggle.tap() }
    }

    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }

    @MainActor
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 6), "Missing \(element)", file: file, line: line)
        if element.exists { element.tap() }
    }

    @discardableResult @MainActor
    private func tapIfExists(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 4) else { return false }
        element.tap()
        return true
    }
}
