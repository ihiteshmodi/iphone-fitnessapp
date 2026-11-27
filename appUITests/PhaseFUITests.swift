import XCTest

/// Acceptance UI tests for Phase F (Body 3-Hoop Triad, Recovery/Sleep, Longevity/ACSM, Concentric HIIT, 4-Mode Coaching, Alarms & Defaults):
///   scripts/run-ui-tests.sh PhaseFUITests
final class PhaseFUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(tab: Int) {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "\(tab)"]
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    private func scrollUntilExists(_ target: XCUIElement) -> Bool {
        for _ in 0..<8 where !target.exists { app.swipeUp() }
        return target.exists
    }

    func testBodyShowsThreeHoopTriadInRecoveryStrainSleepOrderAndOpensDrilldowns() {
        launch(tab: 1)
        let recHoop = element("whoop-triad-recovery")
        let strainHoop = element("whoop-triad-strain")
        let sleepHoop = element("whoop-triad-sleep")
        XCTAssertTrue(recHoop.waitForExistence(timeout: 10))
        XCTAssertTrue(strainHoop.exists)
        XCTAssertTrue(sleepHoop.exists)
        // Verify horizontal order: Recovery (left) < Strain (middle) < Sleep (right)
        XCTAssertLessThan(recHoop.frame.minX, strainHoop.frame.minX)
        XCTAssertLessThan(strainHoop.frame.minX, sleepHoop.frame.minX)

        element("whoop-body-triad-card").tap()
        XCTAssertTrue(app.navigationBars["Recovery & Sleep"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("whoop-sleep-card").exists || scrollUntilExists(element("whoop-sleep-card")))
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(element("whoop-open-longevity").waitForExistence(timeout: 5))
        element("whoop-open-longevity").tap()
        XCTAssertTrue(app.navigationBars["Longevity & VO2"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("whoop-acsm-card").exists || scrollUntilExists(element("whoop-acsm-card")))
    }

    func testWorkoutHiitDualModeProgressCoachingModesAndMoreDefaultsLoadCleanly() {
        launch(tab: 0)
        XCTAssertTrue(app.buttons["day-1"].waitForExistence(timeout: 10))
        app.buttons["day-1"].tap()
        XCTAssertTrue(element("workout-open-hiit-button").waitForExistence(timeout: 10))
        element("workout-open-hiit-button").tap()
        XCTAssertTrue(app.navigationBars["HIIT Timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("hiit-mode-time").exists)
        element("hiit-mode-time").tap()
        element("hiit-done-button").tap()

        // Progress tab: 4-mode coaching switcher
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(element("coaching-hero-card").waitForExistence(timeout: 8))
        element("coaching-mode-maximizing_vo2_max").tap()
        element("coaching-mode-general_health").tap()

        // More tab: Defaults & Rules + WHOOP Silent Alarms
        app.tabBars.buttons["More"].tap()
        let defaultsRow = element("app-defaults-row")
        XCTAssertTrue(defaultsRow.exists || scrollUntilExists(defaultsRow))
        defaultsRow.tap()
        XCTAssertTrue(app.navigationBars["Defaults & Rules"].waitForExistence(timeout: 5))
    }
}
