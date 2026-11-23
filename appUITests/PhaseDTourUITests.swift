import XCTest

/// Screenshot tour for Phase D screens on iPhone 15 Pro Max against a copy of `output/fitness.sqlite`:
///   UI_SEED_DB=output/fitness.sqlite scripts/run-ui-tests.sh PhaseDTourUITests
final class PhaseDTourUITests: XCTestCase {
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

    func testA_WorkoutEditPlanCoverageRoutinesAndSavedWorkouts() {
        launch(tab: 4)
        guard open("edit-plan-row", snap: "d01-edit-plan-weekly-muscle-coverage") else { return }
        if open("plan-configure-muscle-targets", snap: "d02-muscle-set-targets-sheet", swipes: 3) {
            app.swipeUp(); snap("d02b-muscle-set-targets-scroll")
            if element("muscle-targets-done").exists { element("muscle-targets-done").tap(); sleep(1) }
        }
        for _ in 0..<3 { app.swipeDown() }
        if open("plan-saved-workouts", snap: "d03-saved-workouts-unlocked", swipes: 3) {
            let previewBtn = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preview-workout-'")).firstMatch
            if previewBtn.waitForExistence(timeout: 3) {
                previewBtn.tap(); sleep(1)
                snap("d04-saved-workout-preview")
                if element("workout-preview-done").exists { element("workout-preview-done").tap(); sleep(1) }
            }
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }
        if open("plan-routines", snap: "d05-routines-list-and-create", swipes: 3) {
            if open("routine-muscle-Back", snap: "d06-routines-filter-back", swipes: 2) {}
            if open("routine-muscle-Arms", snap: "d07-routines-filter-arms", swipes: 2) {}
            if open("create-routine-button", snap: "d08-create-routine-sheet", swipes: 2) {
                app.buttons["Cancel"].firstMatch.tap(); sleep(1)
            }
        }
    }

    func testB_DailyTargetsDualVitDCompoundsFoodSaveAndRecipes() {
        launch(tab: 2)
        if open("daily-targets-link", snap: "d09-daily-targets-overview", swipes: 3) {
            if open("target-fiber", snap: "d10-daily-targets-fiber-contributors", swipes: 2) {}
            if open("target-vitamin_d", snap: "d11-daily-targets-vitd-dual-contributors", swipes: 6) {}
            app.swipeUp()
            snap("d12-daily-targets-compounds")
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }

        for _ in 0..<4 { app.swipeDown() }
        if element("diet-segment-foods").exists {
            element("diet-segment-foods").tap(); sleep(1)
            if element("foods-filter-supplement").exists {
                element("foods-filter-supplement").tap(); sleep(1)
                let firstSupp = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'food-row-'")).firstMatch
                if firstSupp.waitForExistence(timeout: 3) {
                    firstSupp.tap(); sleep(1)
                    snap("d13-food-editor-top-save")
                    app.swipeUp(); app.swipeUp()
                    snap("d14-food-editor-vitd3-and-compounds")
                    app.buttons["Cancel"].firstMatch.tap(); sleep(1)
                }
            }
            for _ in 0..<3 { app.swipeDown() }
            if element("foods-filter-recipe").exists {
                element("foods-filter-recipe").tap(); sleep(1)
                let firstRecipe = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'food-row-'")).firstMatch
                if firstRecipe.waitForExistence(timeout: 3) {
                    firstRecipe.tap(); sleep(1)
                    snap("d15-recipe-top")
                    app.swipeUp(); snap("d16-recipe-gl-and-aminos")
                    app.swipeUp(); snap("d17-recipe-daily-targets")
                }
            }
        }
    }

    func testC_DietPlanLiveFeedbackAndSavedDietsPreview() {
        launch(tab: 2)
        guard element("diet-segment-plan").waitForExistence(timeout: 5) else { return }
        element("diet-segment-plan").tap(); sleep(1)
        snap("d18-diet-plan-live-feedback")

        if open("plan-daily-targets-link", snap: "d19-planned-daily-targets", swipes: 3) {
            if open("target-vitamin_d", snap: "d19b-planned-vitd-contributors", swipes: 6) {}
            app.navigationBars.buttons.firstMatch.tap(); sleep(1)
        }

        for _ in 0..<3 { app.swipeDown() }
        let mealProfileBtn = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'plan-meal-profile-'")).firstMatch
        if mealProfileBtn.waitForExistence(timeout: 3) || reveal(mealProfileBtn.identifier, swipes: 4) {
            mealProfileBtn.tap(); sleep(1)
            snap("d20-plan-meal-gl-and-aminos")
            if element("meal-profile-done").exists { element("meal-profile-done").tap(); sleep(1) }
        }

        for _ in 0..<4 { app.swipeDown() }
        if open("plan-saved-diets", snap: "d21-saved-diets-list", swipes: 2) {
            var previewBtn = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preview-diet-'")).firstMatch
            if !previewBtn.exists && element("save-current-diet").exists {
                element("save-current-diet").tap(); sleep(1)
                let field = app.alerts.textFields.firstMatch
                if field.waitForExistence(timeout: 3) {
                    field.typeText("Tour Snapshot")
                    app.alerts.buttons["Save"].tap(); sleep(1)
                }
                previewBtn = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'preview-diet-'")).firstMatch
            }
            if previewBtn.waitForExistence(timeout: 3) {
                previewBtn.tap(); sleep(1)
                snap("d22-saved-diet-preview")
                if element("saved-diet-preview-done").exists { element("saved-diet-preview-done").tap(); sleep(1) }
            }
        }
    }
}
