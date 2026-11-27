import XCTest

/// Acceptance UI tests for Phase C on the test fixture database:
///   scripts/run-ui-tests.sh PhaseCUITests
final class PhaseCUITests: XCTestCase {
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

    func testMoreRemovesManualLoaderButtonsAndProgressSupportsMillimeterSites() {
        launch(tab: 4)
        XCTAssertTrue(app.buttons["export-database-button"].waitForExistence(timeout: 10))
        XCTAssertFalse(element("load-coach-presets").exists)
        XCTAssertFalse(element("apply-nutrient-data").exists)
        XCTAssertFalse(element("apply-lab-history").exists)

        app.tabBars.buttons.element(boundBy: 3).tap()
        tap("add-site-button")
        let picker = app.segmentedControls["site-unit-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["mm"].tap()
        XCTAssertTrue(picker.buttons["mm"].isSelected)

        let nameField = app.textFields["site-name-field"]
        nameField.tap()
        nameField.typeText("Tricep Caliper\n")

        let readingField = app.textFields["site-reading-field"]
        readingField.tap()
        readingField.typeText("7.4")

        let targetField = app.textFields["site-target-field"]
        targetField.tap()
        targetField.typeText("5.0")

        app.buttons["sheet-save-button"].tap()

        let ring = element("measurement-ring-Tricep Caliper")
        for _ in 0..<4 { app.swipeDown() }
        XCTAssertTrue(ring.waitForExistence(timeout: 5) || scrollUntilExists(ring))
        XCTAssertTrue(ring.label.contains("mm"), "Expected mm in ring label: \(ring.label)")

        // Clean up shared fixture database.
        tap("measurement-ring-Tricep Caliper")
        tap("remove-site-button")
        app.buttons["Remove site"].tap()
    }

    func testBloodworkShowsCoreTestsPendingGuideAndVisualRangeBar() {
        launch(tab: 1)
        tap("labs-entry")
        if element("labs-confirm-male").exists { tap("labs-confirm-male") }
        XCTAssertTrue(element("labs-how-it-works-card").waitForExistence(timeout: 5))
        XCTAssertTrue(element("labs-core-pending-card").exists)

        tap("labs-marker-library")
        let markersNav = app.navigationBars.matching(NSPredicate(format: "identifier BEGINSWITH 'Markers'")).firstMatch
        XCTAssertTrue(markersNav.waitForExistence(timeout: 5))
        let firstMarker = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'labs-marker-row-'")).firstMatch
        XCTAssertTrue(firstMarker.waitForExistence(timeout: 5))
        firstMarker.tap()
        XCTAssertTrue(element("labs-marker-range-bar").waitForExistence(timeout: 5))
    }
}
