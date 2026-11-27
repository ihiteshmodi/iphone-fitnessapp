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

    func testF1_BodyThreeHoopTriadRecoverySleepTempAndLongevityGps() {
        launch(tab: 1)
        snap("f01-body-three-hoop-triad-and-quick-tiles")
        if open("whoop-body-triad-card", snap: "f02-recovery-temp-c-f-and-illness", swipes: 3) {
            app.swipeUp()
            snap("f03-sleep-stages-wake-consistency-and-naps")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        if open("whoop-open-longevity", snap: "f04-longevity-vo2-and-vitality-hoops", swipes: 3) {
            app.swipeUp()
            snap("f05-acsm-duration-and-gps-1km-vo2max")
        }
    }

    func testF2_BreatheBiofeedbackStressAlertnessAnd24MetricExplorer() {
        launch(tab: 1)
        if open("whoop-open-breathe-stress", snap: "f06-guided-breathing-physiological-sigh", swipes: 4) {
            app.swipeUp()
            snap("f07-24h-baevsky-stress-and-alertness-forecast")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        if open("whoop-open-metrics-explorer", snap: "f08-24-metric-trends-normal-bands", swipes: 4) {
            app.swipeUp()
            snap("f09-24-metric-all-variables-grid")
        }
    }

    func testF3_WorkoutLiveZonesConcentricHiitAndTimelineExercisePins() {
        launch(tab: 0)
        if app.buttons["day-1"].waitForExistence(timeout: 5) {
            app.buttons["day-1"].tap()
            sleep(1)
        }
        snap("f10-workout-idle-bar-and-zone-targets")
        if element("workout-open-hiit-button").waitForExistence(timeout: 5) {
            element("workout-open-hiit-button").tap()
            sleep(1)
            snap("f11-concentric-hiit-hr-threshold-mode")
            if element("hiit-mode-time").exists {
                element("hiit-mode-time").tap()
                sleep(1)
                snap("f12-concentric-hiit-time-intervals-mode")
            }
            if element("hiit-done-button").exists {
                element("hiit-done-button").tap()
                sleep(1)
            }
        }
        if element("workout-start-session-button").exists {
            element("workout-start-session-button").tap()
            sleep(1)
            snap("f13-workout-live-0x03-session-hoop")
            if element("workout-finish-session-button").exists {
                element("workout-finish-session-button").tap()
                sleep(1)
                snap("f14-post-workout-timeline-hr-pins-and-trim")
            }
        }
    }

    func testF4_DietMealTimeChipsAndPreSleepCheckInCutoffs() {
        launch(tab: 2)
        snap("f15-diet-today-meal-time-chips")
        for _ in 0..<4 { app.swipeUp() }
        snap("f16-diet-checkin-pre-sleep-carbs-and-cutoffs")
    }

    func testF5_ProgressFourModeCoachingRulesMatrixAndSeasonalReview() {
        launch(tab: 3)
        snap("f17-progress-general-health-rules-matrix")
        if element("coaching-seasonal-check-button").exists {
            element("coaching-seasonal-check-button").tap()
            sleep(1)
        }
        if element("coaching-mode-maximizing_vo2_max").exists {
            element("coaching-mode-maximizing_vo2_max").tap()
            sleep(1)
            snap("f18-progress-vo2max-and-90d-seasonal-prompt")
        }
        if element("coaching-mode-maximizing_hrv").exists {
            element("coaching-mode-maximizing_hrv").tap()
            sleep(1)
            snap("f19-progress-maximizing-hrv-rebound-rules")
        }
        if element("coaching-mode-reducing_rhr").exists {
            element("coaching-mode-reducing_rhr").tap()
            sleep(1)
            snap("f20-progress-reducing-rhr-step-microcycle")
        }
        if open("progress-open-principles", snap: "f21-coaching-principles-and-vo2-limiter", swipes: 2) {
            app.swipeUp()
            snap("f22-coaching-principles-bottom")
        }
    }

    func testF6_MoreSyncProgressNormalSmartAlarmsBatteryAndDefaultsRules() {
        launch(tab: 4)
        if open("whoop-band-row", snap: "f23-whoop-band-sync-progress-and-controls", swipes: 6) {
            app.swipeUp()
            snap("f24-whoop-band-normal-and-smart-alarms")
            if element("whoop-alarm-day-1").exists {
                element("whoop-alarm-day-1").tap()
                sleep(1)
                snap("f25-alarm-editor-normal-vs-smart-wake-sheet")
                if app.buttons["Cancel"].exists {
                    app.buttons["Cancel"].firstMatch.tap()
                    sleep(1)
                }
            }
            app.swipeUp()
            snap("f26-whoop-band-battery-drain-history-chart")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
        if open("app-defaults-row", snap: "f27-defaults-rules-profile-and-hr-zones", swipes: 6) {
            app.swipeUp()
            snap("f28-defaults-rules-step-breakdown-and-hiit")
            app.swipeUp()
            snap("f29-defaults-rules-cutoffs-warmup-pr-deload")
        }
    }

    func testF7_BloodworkDirectJsonInserterAndCustomGenes() {
        launch(tab: 1)
        if open("labs-entry", snap: "f30-bloodwork-overview-with-json-inserter", swipes: 6) {
            if open("labs-open-json-inserter", snap: "f31-labs-direct-json-inserter-sheet", swipes: 4) {
                if element("labs-json-load-sample").exists {
                    element("labs-json-load-sample").tap()
                    sleep(1)
                    snap("f32-labs-json-sample-loaded")
                }
            }
        }
    }
}
