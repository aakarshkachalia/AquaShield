//
//  ScreenshotTests.swift
//  ClearWellNCUITests
//
//  Captures every main screen in light and dark mode for review. Screenshots are attached to the test
//  result, and on the simulator also written as PNGs to SCREENSHOT_DIR (default /tmp/ClearWellScreenshots).
//  Run:
//    TEST_RUNNER_SCREENSHOT_DIR=~/clearwell/Screenshots xcodebuild test -scheme ClearWellNC \
//      -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:ClearWellNCUITests/ScreenshotTests
//

import XCTest

final class ScreenshotTests: XCTestCase {
    private var appearance = "light"
    private var mode = "well"
    private var index = 0

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    @MainActor func testScreenshotsWellLight() { capture("light", mode: "well") }
    @MainActor func testScreenshotsWellDark() { capture("dark", mode: "well") }
    @MainActor func testScreenshotsCityLight() { capture("light", mode: "city") }
    @MainActor func testScreenshotsCityDark() { capture("dark", mode: "city") }

    // MARK: Walkthrough

    @MainActor
    private func capture(_ appearance: String, mode: String) {
        self.appearance = appearance
        self.mode = mode
        index = 0

        // Onboarding, from a clean install (city mode only: it's the same for both).
        if mode == "city" {
            let fresh = XCUIApplication()
            fresh.launchArguments = ["-uiTestReset", "-uiTestAppearance", appearance]
            fresh.launch()
            snap(fresh, "onboarding-welcome")
            if tapIfExists(fresh.buttons["onboarding.getStarted"]) { snap(fresh, "onboarding-address") }
            tapIfExists(fresh.buttons["onboarding.skipAddress"])
            if tapIfExists(fresh.buttons["onboarding.continueWithoutAddress"]) { snap(fresh, "onboarding-estimate") }
            if tapIfExists(fresh.buttons["flow.next"]) { snap(fresh, "onboarding-confirm") }
            tapIfExists(fresh.descendants(matching: .any)["onboarding.source.publicWater"])
            if tapIfExists(fresh.buttons["flow.next"]) { snap(fresh, "onboarding-household") }
            fresh.terminate()
        }

        // City: a sample city result. Well: Demo Mode's arsenic persona.
        let app = XCUIApplication()
        app.launchArguments = mode == "city"
            ? ["-uiTestReset", "-uiTestSkipOnboarding", "-uiTestSource", "publicWater", "-uiTestSeedResults",
               "-uiTestAppearance", appearance]
            : ["-uiTestReset", "-uiTestSkipOnboarding", "-uiTestDemo", "arsenicProblem", "-uiTestAppearance", appearance]
        app.launch()

        tab(app, "Home")
        snap(app, "dashboard")
        scroll(app); snap(app, "dashboard-lower")
        open(app, element(app, "dashboard.score"), "tap-score-kitchen")
        open(app, element(app, "dashboard.nextStep"), "what-to-do")
        let household = element(app, "dashboard.household")
        open(app, household, "household")

        tab(app, "My Water")
        snap(app, "my-water-latest")
        let segments = app.segmentedControls.firstMatch
        if segments.waitForExistence(timeout: 3) {
            segments.buttons.element(boundBy: 1).tap(); snap(app, "my-water-history")
            segments.buttons.element(boundBy: 2).tap(); snap(app, "my-water-trends")
            segments.buttons.element(boundBy: 0).tap()
        }
        open(app, labeled(app, "Filters"), "filters")
        open(app, labeled(app, "Testing and modes"), "testing-and-modes")
        open(app, labeled(app, "Share a report"), "share-report")
        open(app, labeled(app, "My water utility"), "utility-report")

        tab(app, "Get Help")
        snap(app, "get-help")
        open(app, element(app, "getHelp.findTesting"), "find-testing")
        if tapIfExists(app.buttons["getHelp.riskCheck"]) {
            snap(app, "risk-check-question")
            tapIfExists(app.buttons["flow.close"])
        }

        tab(app, "Learn")
        snap(app, "learn")

        tab(app, "Home")
        if tapIfExists(app.navigationBars.buttons["Settings"]) {
            snap(app, "settings")
            open(app, labeled(app, "Privacy & Sources"), "privacy-and-sources")
            back(app)
        }
    }

    // MARK: Helpers

    @MainActor
    private func snap(_ app: XCUIApplication, _ name: String) {
        index += 1
        let file = String(format: "%02d-%@-%@-%@", index, name, mode, appearance)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = file
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? "/tmp/ClearWellScreenshots"
        let folder = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            .appendingPathComponent(mode).appendingPathComponent(appearance)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? screenshot.pngRepresentation.write(to: folder.appendingPathComponent(file + ".png"))
    }

    @MainActor
    private func tab(_ app: XCUIApplication, _ name: String) {
        tapIfExists(app.tabBars.buttons[name])
    }

    /// Opens a screen, snaps it, and comes back.
    @MainActor
    private func open(_ app: XCUIApplication, _ element: XCUIElement, _ name: String) {
        guard reveal(app, element) else { return }
        element.tap()
        snap(app, name)
        back(app)
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons["BackButton"]
        if back.waitForExistence(timeout: 2) { back.tap() }
    }

    @MainActor
    private func labeled(_ app: XCUIApplication, _ prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] %@", prefix)).firstMatch
    }

    @MainActor
    private func scroll(_ app: XCUIApplication) {
        app.swipeUp()
    }

    /// Any element with this identifier (SwiftUI links don't always report as buttons).
    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Scrolls to the top, then down until the element is on screen.
    @MainActor
    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) -> Bool {
        for _ in 0..<4 { app.swipeDown() }
        for _ in 0..<8 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    @discardableResult @MainActor
    private func tapIfExists(_ element: XCUIElement) -> Bool {
        guard element.waitForExistence(timeout: 4) else { return false }
        element.tap()
        return true
    }
}
