import XCTest

/// Acceptance UI tests for Phase E (Bloodwork Dashboard/Filters/Genetics, 5 Multivitamins, WHOOP Band & Dual-DB Backup):
///   scripts/run-ui-tests.sh PhaseEUITests
final class PhaseEUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(tab: Int) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "\(tab)"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 10) || scrollUntilExists(target), "missing \(id)", file: file, line: line)
        for _ in 0..<10 where !(target.isHittable && target.frame.maxY < app.frame.maxY - 110) { app.swipeUp() }
        target.tap()
    }

    private func scrollUntilExists(_ target: XCUIElement) -> Bool {
        for _ in 0..<10 where !target.exists { app.swipeUp() }
        return target.exists
    }

    func testBloodworkDashboardMarkerQuickFiltersAndGeneticsScreenLoadCleanly() {
        launch(tab: 1)
        tap("labs-entry")
        if element("labs-confirm-male").exists { tap("labs-confirm-male") }

        tap("labs-open-dashboard")
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()

        tap("labs-marker-library")
        XCTAssertTrue(app.navigationBars["Markers"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("labs-marker-chip-core").waitForExistence(timeout: 5))
        element("labs-marker-chip-core").tap()
        XCTAssertTrue(element("labs-markers-custom-filter-button").exists)
        element("labs-markers-custom-filter-button").tap()
        XCTAssertTrue(element("labs-custom-filter-tier").waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()

        tap("labs-genetics")
        XCTAssertTrue(app.navigationBars["Genetics"].waitForExistence(timeout: 5))
    }

    func testMoreShowsDualDatabaseBackupFiveMultivitaminsAndWhoopBandScreen() {
        launch(tab: 4)
        XCTAssertTrue(element("export-database-button").waitForExistence(timeout: 10))
        XCTAssertTrue(element("more-import-whoop-button").exists || scrollUntilExists(element("more-import-whoop-button")))

        tap("whoop-band-row")
        XCTAssertTrue(app.navigationBars["WHOOP Band"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("whoop-scan-button").exists)
        XCTAssertTrue(element("whoop-phase-badge").exists)
        app.navigationBars.buttons.firstMatch.tap()

        for _ in 0..<4 { app.swipeDown() }
        tap("supplements-row")
        tap("open-multivitamin-stack")
        XCTAssertTrue(app.staticTexts["Centrum Men Multivitamin"].waitForExistence(timeout: 5) || scrollUntilExists(app.staticTexts["Centrum Men Multivitamin"]))
    }
}
