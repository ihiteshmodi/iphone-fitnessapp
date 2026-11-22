import XCTest

/// Acceptance tests for Blood Labs on the seeded database (no lab history). The class shares one database.
///   scripts/run-ui-tests.sh PhaseBUITests
final class PhaseBUITests: XCTestCase {
    private var app: XCUIApplication!

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func tap(_ id: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = element(id)
        XCTAssertTrue(target.waitForExistence(timeout: 10) || scrollUntilHittable(target), "missing \(id)", file: file, line: line)
        for _ in 0..<10 where !(target.isHittable && target.frame.maxY < app.frame.maxY - 110) { app.swipeUp() }
        target.tap()
    }

    private func scrollUntilHittable(_ target: XCUIElement) -> Bool {
        for _ in 0..<12 where !target.exists { app.swipeUp() }
        return target.exists
    }

    private func openLabs() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "1"]
        app.launch()
        tap("labs-entry")
        XCTAssertTrue(app.navigationBars["Bloodwork"].waitForExistence(timeout: 5))
    }

    func testAddADrawWithAResultAndSeeItRead() {
        openLabs()
        tap("labs-add-draw")
        tap("labs-add-result")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("ferritin")
        app.staticTexts["Ferritin"].firstMatch.tap()
        let value = element("labs-result-value")
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap()
        value.typeText("15")
        tap("labs-save-draw")

        tap("labs-draw-row")
        XCTAssertTrue(app.staticTexts["15 ng/mL"].waitForExistence(timeout: 5), "the result is listed")
        XCTAssertTrue(app.staticTexts["Low"].exists, "and read against the vault's band")
    }

    func testDrugNotesSwitchIsKept() {
        openLabs()
        tap("labs-settings-button")
        let toggle = app.switches["labs-drug-notes-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        app.buttons["Save"].tap()

        tap("labs-settings-button")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "1")
    }

    func testConfirmMaleHidesFemaleCycleFieldAndUnitMismatchSwitchesUnit() {
        openLabs()
        if element("labs-confirm-male").exists {
            tap("labs-confirm-male")
        }
        XCTAssertFalse(element("labs-sex-confirm-card").exists)

        tap("labs-add-draw")
        XCTAssertFalse(element("labs-cycle-day").exists, "female cycle day stays hidden when Male is selected")

        tap("labs-add-result")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Free T3")
        app.staticTexts["Free T3"].firstMatch.tap()

        let value = element("labs-result-value")
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        value.tap()
        value.typeText("0.34")

        let switchBtn = element("labs-switch-suggested-unit")
        XCTAssertTrue(switchBtn.waitForExistence(timeout: 5), "10x scale mismatch suggests switching pg/mL to ng/dL")
        switchBtn.tap()
        tap("labs-save-draw")
    }

    func testGeneticsTRTRxContextSheetAndActionCategories() {
        openLabs()
        tap("labs-open-context-sheet")
        let trtToggle = app.switches["labs-context-trt-toggle"]
        XCTAssertTrue(trtToggle.waitForExistence(timeout: 5))
        trtToggle.switches.firstMatch.tap()
        tap("labs-context-save")

        tap("labs-genetics")
        XCTAssertTrue(app.navigationBars["Genetics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'TRT/HRT: On'")).firstMatch.waitForExistence(timeout: 5))
        tap("labs-gene-row-vdr")
        XCTAssertTrue(app.staticTexts["Change-Nothing Mandate"].waitForExistence(timeout: 5))
    }
}

