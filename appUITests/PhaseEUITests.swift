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
        let anyEl = element(id)
        XCTAssertTrue(anyEl.waitForExistence(timeout: 10) || scrollUntilExists(anyEl), "missing \(id)", file: file, line: line)
        let target = app.buttons[id].exists ? app.buttons[id].firstMatch : anyEl
        for _ in 0..<6 where target.exists && target.frame.minY < 100 { app.swipeDown() }
        for _ in 0..<6 where target.exists && target.frame.maxY >= app.frame.maxY - 110 { app.swipeUp() }
        target.tap()
    }

    private func scrollUntilExists(_ target: XCUIElement) -> Bool {
        for _ in 0..<10 where !target.exists { app.swipeUp() }
        return target.exists
    }

    func testBloodworkDashboardLoadsCleanly() {
        launch(tab: 1)
        tap("labs-entry")
        if element("labs-confirm-male").exists { tap("labs-confirm-male") }

        tap("labs-open-dashboard")
        XCTAssertTrue(app.navigationBars["Bloodwork Dashboard"].waitForExistence(timeout: 5))
    }

    func testMarkersQuickFiltersAndCustomFilterSheetLoadCleanly() {
        launch(tab: 1)
        tap("labs-entry")
        if element("labs-confirm-male").exists { tap("labs-confirm-male") }

        tap("labs-marker-library")
        let markersNav = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Markers'")).firstMatch
        XCTAssertTrue(markersNav.waitForExistence(timeout: 5))
        XCTAssertTrue(element("labs-marker-chip-★ Core").waitForExistence(timeout: 5))
        tap("labs-marker-chip-★ Core")
        tap("labs-markers-custom-filter-button")
        XCTAssertTrue(element("labs-custom-filter-tier").waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
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

    func testWorkoutOpensStandaloneWhoopDiagnosticConsoleWithSqliteInspectorAndExporter() {
        launch(tab: 0)
        XCTAssertTrue(element("workout-whoop-diag-button").waitForExistence(timeout: 10))
        element("workout-whoop-diag-button").tap()

        XCTAssertTrue(app.navigationBars["WHOOP Diagnostic"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("whoop-diag-connect-button").exists)
        XCTAssertTrue(element("whoop-diag-disconnect-button").exists)
        XCTAssertTrue(element("whoop-diag-force-drain-button").exists)
        XCTAssertTrue(element("whoop-diag-crc-errors").exists || scrollUntilExists(element("whoop-diag-crc-errors")))
        XCTAssertTrue(element("whoop-diag-burst-stats").exists || scrollUntilExists(element("whoop-diag-burst-stats")))
        XCTAssertTrue(element("whoop-diag-ack-verdict").exists || scrollUntilExists(element("whoop-diag-ack-verdict")))
        XCTAssertTrue(element("whoop-diag-export-sqlite-button").exists || scrollUntilExists(element("whoop-diag-export-sqlite-button")))

        app.buttons["whoop-diag-done"].tap()
        XCTAssertTrue(element("workout-whoop-diag-button").waitForExistence(timeout: 5))
    }
}
