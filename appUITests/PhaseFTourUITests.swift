import XCTest

/// Screenshot tour for Phase F (WHOOP 3-Hoop Body Hub, Recovery & 4-Stage Sleep, Longevity & ACSM Treadmill,
/// Workout Live Hoop & Concentric Dual-Hoop HIIT, Diet Meal ate_at & Sleep-Gap Hoop, Progress 4-Mode Coaching, More 7-Day Alarms & Defaults):
///   UI_SEED_DB=output/fitness.sqlite UI_WHOOP_SEED_DB=output/whoop.sqlite scripts/run-ui-tests.sh PhaseFTourUITests
final class PhaseFTourUITests: XCTestCase {
    private var app: XCUIApplication!

    private func launch(tab: Int) {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "\(tab)"]
        app.launch()
        sleep(2)
    }

    private func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    @discardableResult
    private func reveal(_ id: String, swipes: Int = 8) -> Bool {
        let target = element(id)
        for _ in 0..<swipes where !(target.exists && target.isHittable && target.frame.maxY < app.frame.maxY - 110) {
            app.swipeUp()
        }
        return target.exists && target.isHittable
    }

    @discardableResult
    private func open(_ id: String, snap name: String, swipes: Int = 8) -> Bool {
        guard reveal(id, swipes: swipes) else { snap("\(name)-MISSING"); return false }
        element(id).tap()
        sleep(1)
        snap(name)
        return true
    }

    func testF1_BodyThreeHoopTriadRecoverySleepAndLongevity() {
        launch(tab: 1)
        snap("f01-body-three-hoop-triad-recovery-strain-sleep")
        if open("whoop-body-triad-card", snap: "f02-recovery-and-sleep-top", swipes: 3) {
            app.swipeUp()
            snap("f03-sleep-stages-naps-and-energy")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        if open("whoop-open-longevity", snap: "f04-longevity-vo2-and-vitality-hoops", swipes: 3) {
            app.swipeUp()
            snap("f05-acsm-treadmill-vo2-calculator")
        }
    }

    func testF2_WorkoutLiveHoopConcentricHiitAndSessionReview() {
        launch(tab: 0)
        if app.buttons["day-1"].waitForExistence(timeout: 5) {
            app.buttons["day-1"].tap()
            sleep(1)
        }
        snap("f06-workout-idle-whoop-bar")
        if element("workout-open-hiit-button").waitForExistence(timeout: 5) {
            element("workout-open-hiit-button").tap()
            sleep(1)
            snap("f07-concentric-hiit-hr-threshold-mode")
            if element("hiit-mode-time").exists {
                element("hiit-mode-time").tap()
                sleep(1)
                snap("f08-concentric-hiit-time-intervals-mode")
            }
            if element("hiit-done-button").exists {
                element("hiit-done-button").tap()
                sleep(1)
            }
        }
        if element("workout-start-session-button").exists {
            element("workout-start-session-button").tap()
            sleep(1)
            snap("f09-workout-live-0x03-session-hoop")
            if element("workout-finish-session-button").exists {
                element("workout-finish-session-button").tap()
                sleep(1)
                snap("f10-workout-finish-and-trim-review-sheet")
            }
        }
    }

    func testF3_DietMealTimeChipsAndPreSleepCheckInHoop() {
        launch(tab: 2)
        snap("f11-diet-today-meal-time-chips")
        for _ in 0..<4 { app.swipeUp() }
        snap("f12-diet-checkin-pre-sleep-cutoffs")
    }

    func testF4_ProgressFourModeCoachingHoopsAndPrinciples() {
        launch(tab: 3)
        snap("f13-progress-coaching-general-health")
        if element("coaching-mode-maximizing_vo2_max").exists {
            element("coaching-mode-maximizing_vo2_max").tap()
            sleep(1)
            snap("f14-progress-coaching-vo2-max-mode")
        }
        if element("coaching-mode-reducing_rhr").exists {
            element("coaching-mode-reducing_rhr").tap()
            sleep(1)
            snap("f15-progress-coaching-reducing-rhr-mode")
        }
        if open("progress-open-principles", snap: "f16-coaching-principles-and-vo2-limiter", swipes: 2) {
            app.swipeUp()
            snap("f17-coaching-principles-bottom")
        }
    }

    func testF5_MoreSevenDaySilentAlarmsStepDivisorAndDefaults() {
        launch(tab: 4)
        if open("whoop-band-row", snap: "f18-whoop-band-silent-alarms-top", swipes: 6) {
            app.swipeUp()
            snap("f19-whoop-band-alarms-and-step-divisor")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        if open("app-defaults-row", snap: "f20-app-defaults-and-cutoffs-top", swipes: 6) {
            app.swipeUp()
            snap("f21-app-defaults-zones-and-sleep")
        }
    }

    func testF6_BloodworkAiJsonTemplatesAndCustomGenes() {
        launch(tab: 1)
        if open("labs-entry", snap: "f22-bloodwork-dashboard", swipes: 6) {
            if element("labs-settings-button").waitForExistence(timeout: 3) {
                element("labs-settings-button").tap()
                sleep(1)
                app.swipeUp()
                snap("f23-labs-ai-json-template-export-import")
                if app.buttons["Done"].exists {
                    app.buttons["Done"].firstMatch.tap()
                    sleep(1)
                } else if app.buttons["Cancel"].exists {
                    app.buttons["Cancel"].firstMatch.tap()
                    sleep(1)
                }
            }
            if open("labs-genetics", snap: "f24-genetics-overview", swipes: 6) {
                if open("labs-add-custom-gene", snap: "f25-add-custom-gene-sheet", swipes: 12) {
                    // sheet captured
                }
            }
        }
    }
}
