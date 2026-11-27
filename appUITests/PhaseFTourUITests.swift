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

    func testF1_BodyClickableHoopsReviewBannerAndStepsCalculator() {
        launch(tab: 1)
        snap("h01-body-triad-review-banner-and-steps-tile")

        if open("whoop-triad-recovery", snap: "h02-recovery-detail-drivers-and-illness", swipes: 3) {
            app.swipeUp()
            snap("h03-recovery-31d-rated-bars")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        if open("whoop-triad-strain", snap: "h04-strain-detail-intraday-curve-and-zones", swipes: 3) {
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        if open("whoop-triad-sleep", snap: "h05-sleep-detail-openstrap-hypnogram", swipes: 3) {
            app.swipeUp()
            snap("h06-sleep-detail-stage-ranges-and-against-usual")
            app.swipeUp()
            snap("h07-sleep-detail-4-overnight-signals")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        if open("whoop-open-steps-detail", snap: "h08-steps-detail-hourly-bars-and-zone-checkmarks", swipes: 4) {
            app.swipeUp()
            snap("h09-steps-detail-divisor-explainer")
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }
    }

    func testF2_LiveTreadmillVo2BreatheHapticsAndClean24MetricTrends() {
        launch(tab: 1)
        if open("whoop-open-longevity", snap: "h10-longevity-overview", swipes: 3) {
            app.swipeUp()
            snap("h11-longevity-live-treadmill-vo2-idle")
            if reveal("whoop-start-live-treadmill-button", swipes: 4) {
                element("whoop-start-live-treadmill-button").tap()
                sleep(2)
                snap("h12-longevity-live-treadmill-running")
                if reveal("whoop-stop-live-treadmill-button", swipes: 3) {
                    element("whoop-stop-live-treadmill-button").tap()
                    sleep(1)
                    snap("h13-longevity-treadmill-conclude-display-distance")
                    if app.buttons["Discard"].exists {
                        app.buttons["Discard"].firstMatch.tap()
                        sleep(1)
                    }
                }
            }
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        if open("whoop-open-breathe-stress", snap: "h14-breathe-spaced-wrist-haptic-legend", swipes: 4) {
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        if open("whoop-open-metrics-explorer", snap: "h15-24-metric-clean-single-dropdown-30d", swipes: 4) {
            // Confirm no duplicate grid below when swiping
            app.swipeUp()
            snap("h16-24-metric-clean-bottom-no-duplicate-grid")
        }
    }

    func testF3_WorkoutTrue7dZoneTargetsAndHiitHrDurationOpenModes() {
        launch(tab: 0)
        if app.buttons["day-1"].waitForExistence(timeout: 5) {
            app.buttons["day-1"].tap()
            sleep(1)
        }
        snap("h17-workout-true-7d-zone-targets")
        if element("workout-open-hiit-button").waitForExistence(timeout: 5) {
            element("workout-open-hiit-button").tap()
            sleep(1)
            if element("hiit-hr-goal-total_duration").exists {
                element("hiit-hr-goal-total_duration").tap()
                sleep(1)
                snap("h18-hiit-hr-threshold-total-duration-mode")
            }
            if element("hiit-hr-goal-open_unlimited").exists {
                element("hiit-hr-goal-open_unlimited").tap()
                sleep(1)
                snap("h19-hiit-hr-threshold-open-unlimited-mode")
            }
            if element("hiit-done-button").exists {
                element("hiit-done-button").tap()
                sleep(1)
            }
        }
    }

    func testF4_CoachingActiveVsPreviewCtlProvenanceAndLiveMaxHrTest() {
        launch(tab: 3)
        snap("h20-coaching-active-focus-and-true-z2")
        if element("coaching-mode-maximizing_vo2_max").exists {
            element("coaching-mode-maximizing_vo2_max").tap()
            sleep(1)
            snap("h21-coaching-previewing-vo2max-without-overwriting-active")
        }
        if element("coaching-mode-reducing_rhr").exists {
            element("coaching-mode-reducing_rhr").tap()
            sleep(1)
            snap("h22-coaching-previewing-reducing-rhr")
        }
        if element("coaching-cancel-preview-button").exists {
            element("coaching-cancel-preview-button").tap()
            sleep(1)
        }
        app.swipeUp()
        snap("h23-coaching-ctl-atl-live-provenance")

        // Scroll back up to open Principles & Max HR
        app.swipeDown()
        if open("progress-open-principles", snap: "h24-principles-live-maxhr-calibration-idle", swipes: 2) {
            if element("principles-start-maxhr-test").exists {
                element("principles-start-maxhr-test").tap()
                sleep(1)
                snap("h25-principles-live-maxhr-calibration-active")
                if element("principles-stop-maxhr-test").exists {
                    element("principles-stop-maxhr-test").tap()
                }
            }
        }
    }

    func testF5_DefaultsAutoSyncedReadOnlyWaist() {
        launch(tab: 4)
        if open("app-defaults-row", snap: "h26-defaults-auto-synced-readonly-waist", swipes: 6) {
            app.swipeUp()
            snap("h27-defaults-hr-zones-and-maxhr-test-link")
        }
    }
}
