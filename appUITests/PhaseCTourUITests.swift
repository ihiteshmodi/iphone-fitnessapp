import XCTest

/// Screenshot tour for Phase C screens on iPhone 15 Pro Max against a copy of `output/fitness.sqlite`:
///   UI_SEED_DB=output/fitness.sqlite scripts/run-ui-tests.sh PhaseCTourUITests
final class PhaseCTourUITests: XCTestCase {
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

    func testA_BodyOrderAndGoalMode() {
        launch(tab: 1)
        snap("c01-body-top")
        app.swipeUp()
        snap("c01-body-bloodwork-position")
        for _ in 0..<3 { app.swipeDown() }
        if open("calories-edit-button", snap: "c02-goal-mode-sheet") {
            app.swipeDown(velocity: .fast)
            sleep(1)
        }
    }

    func testB_DietMealProfileAndDailyTargets() {
        launch(tab: 2)
        snap("c03-diet-today")
        if open("daily-targets-link", snap: "c05-daily-targets-no-aa", swipes: 3) {
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        if open("diet-meal-profile-Brunch", snap: "c04-brunch-meal-profile", swipes: 6) {
            if open("meal-amino-leucine", snap: "c04b-brunch-leucine-contributors", swipes: 3) {}
            if element("meal-profile-done").exists {
                element("meal-profile-done").tap(); sleep(1)
            } else {
                app.swipeDown(velocity: .fast); sleep(1)
            }
        }
    }

    func testC_ProgressUnits() {
        launch(tab: 3)
        snap("c06-progress-rings-mm")
        if open("measurement-ring-Body Fat (belly Button)", snap: "c08-skinfold-detail-mm", swipes: 2) {
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        if open("add-site-button", snap: "c07-add-site-unit-picker", swipes: 8) {
            app.buttons["Cancel"].firstMatch.tap(); sleep(1)
        }
    }

    func testD_MoreAndMultivitaminStack() {
        launch(tab: 4)
        snap("c09-more-cleaned")
        app.swipeUp(); snap("c09-more-cleaned-scroll")
        for _ in 0..<3 { app.swipeDown() }
        if open("supplements-row", snap: "c10-supplements-stack-card", swipes: 4) {
            if open("open-multivitamin-stack", snap: "c11-mvi-stack-builder", swipes: 2) {
                if open("suggest-best-stack-button", snap: "c11a-mvi-suggested", swipes: 2) {}
                app.swipeUp(); snap("c11b-mvi-zero-out-of-target")
                app.swipeUp(); snap("c11c-mvi-minerals-zero")
            }
        }
    }

    func testE_GuidedBloodworkAndRangeBars() {
        launch(tab: 1)
        guard open("labs-entry", snap: "c12-labs-core-guide") else { return }
        if element("labs-confirm-male").exists {
            element("labs-confirm-male").tap(); sleep(1)
            snap("c12a-labs-confirmed")
        }
        if open("labs-guide-button", snap: "c13-how-bloodwork-works-sheet") {
            app.buttons["Done"].firstMatch.tap(); sleep(1)
        }
        if open("labs-plan-draw", snap: "c14-plan-draw-core-first") {
            app.swipeUp(); snap("c14-plan-draw-scroll")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        if open("labs-draw-row", snap: "c15-draw-mini-range-bars") {
            if let firstCell = app.cells.allElementsBoundByIndex.first(where: { $0.buttons.count > 0 || $0.staticTexts.count > 1 }) {
                firstCell.tap(); sleep(1)
                snap("c16-marker-detail-range-bar")
            }
        }
    }
}
