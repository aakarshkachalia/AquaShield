//
//  ClearWellNCUITests.swift
//  ClearWellNCUITests
//
//  Created by Aakarsh Kachalia on 10/2/26.
//

import XCTest

final class ClearWellNCUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Answers survive a real relaunch (the process is terminated, not just the view reloaded),
    /// the flow offers Continue, resumes on the next question, and Back shows earlier answers.
    @MainActor
    func testRiskCheckResumesAfterRelaunch() throws {
        // First launch: clean state, onboarding done.
        let app = XCUIApplication()
        app.launchArguments = ["-uiTestReset", "-uiTestSkipOnboarding"]
        app.launch()

        openRiskCheck(app)
        tap(app.buttons["flow.next"])                       // 1. County: keep "Not sure"
        tap(app.buttons["riskCheck.wellAge.0"])             // 2. Drilled before 2008: Yes
        tap(app.buttons["riskCheck.pregnancy.1"])           // 3. Pregnant or infant: No
        tap(app.buttons["riskCheck.flooding.0"])            // 4. Flooding: Yes
        XCTAssertTrue(app.buttons["riskCheck.nearbySources.0"].waitForExistence(timeout: 5))

        // Kill the process and launch again without resetting anything.
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
        app.launchArguments = ["-uiTestSkipOnboarding"]
        app.launch()

        openRiskCheck(app)
        let continueButton = app.buttons["flow.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5), "Expected the Continue / Start over prompt")
        XCTAssertTrue(app.buttons["flow.startOver"].exists)
        XCTAssertTrue(app.staticTexts["Started just now"].exists || app.staticTexts.containing(
            NSPredicate(format: "label BEGINSWITH 'Started'")).firstMatch.exists)
        continueButton.tap()

        // Resumes on question 5, where we left off.
        XCTAssertTrue(app.buttons["riskCheck.nearbySources.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.otherElements["flow.progress"].exists || app.descendants(matching: .any)["flow.progress"].exists)

        // Back walks through the saved answers.
        back(app)
        assertSelected(app.buttons["riskCheck.flooding.0"])
        back(app)
        assertSelected(app.buttons["riskCheck.pregnancy.1"])
        back(app)
        assertSelected(app.buttons["riskCheck.wellAge.0"])
        XCTAssertFalse(app.buttons["riskCheck.wellAge.1"].isSelected)
    }

    // MARK: Helpers

    @MainActor
    private func openRiskCheck(_ app: XCUIApplication) {
        let helpTab = app.tabBars.buttons["Get Help"]
        tap(helpTab)
        tap(app.buttons["getHelp.riskCheck"])
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        // The system back button's label is the previous screen's title; its identifier is stable.
        tap(app.navigationBars.buttons["BackButton"])
    }

    @MainActor
    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(element)", file: file, line: line)
        element.tap()
    }

    @MainActor
    private func assertSelected(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing \(element)", file: file, line: line)
        XCTAssertTrue(element.isSelected, "Expected \(element) to be selected", file: file, line: line)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
