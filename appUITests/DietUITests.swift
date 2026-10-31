import XCTest

/// The Diet tab against the seeded database plus the made-up demo diet (`tools/diet-import/demo_diet.py`).
final class DietUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Some simulator layouts (the iPhone Duo) mis-route taps on later tabs, so start on the Diet tab (index 2).
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "2"]
        app.launch()
    }

    private var total: XCUIElement { app.staticTexts["diet-total-calories"] }

    private func element(_ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }

    func testTodayAddsUpThePlanAndShowsTheProteinAndFatTargets() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        XCTAssertNotEqual(total.label, "–")
        XCTAssertTrue(element("diet-macro-protein").exists)
        XCTAssertTrue(element("diet-macro-fat").exists)
        XCTAssertTrue(element("diet-line-Rolled oats").exists, "the plan's items are listed under their meals")
    }

    func testNothingCountsUntilItIsTickedAndTickingAnItemAddsItsCalories() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        XCTAssertEqual(calories(total), 0, "nothing is ticked by default")
        let oats = app.buttons["diet-line-Rolled oats"]
        XCTAssertTrue(oats.exists)
        XCTAssertEqual(oats.value as? String, "not eaten")

        oats.tap()

        XCTAssertEqual(app.buttons["diet-line-Rolled oats"].value as? String, "eaten")
        XCTAssertGreaterThan(calories(total), 0)

        app.buttons["diet-line-Rolled oats"].tap()

        XCTAssertEqual(app.buttons["diet-line-Rolled oats"].value as? String, "not eaten")
        XCTAssertEqual(calories(total), 0)
    }

    func testOneBoxTicksAndUnticksAWholeMeal() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let meal = app.buttons["diet-meal-Morning"]
        XCTAssertTrue(meal.exists)
        XCTAssertEqual(meal.value as? String, "none")

        meal.tap()

        XCTAssertEqual(app.buttons["diet-meal-Morning"].value as? String, "all")
        XCTAssertEqual(app.buttons["diet-line-Rolled oats"].value as? String, "eaten")
        XCTAssertEqual(app.buttons["diet-line-Whey blend"].value as? String, "eaten")
        XCTAssertGreaterThan(calories(total), 0)

        app.buttons["diet-line-Whey blend"].tap()
        XCTAssertEqual(app.buttons["diet-meal-Morning"].value as? String, "some")

        app.buttons["diet-meal-Morning"].tap()
        XCTAssertEqual(app.buttons["diet-meal-Morning"].value as? String, "all", "a meal that is only partly ticked is completed first")
        app.buttons["diet-meal-Morning"].tap()
        XCTAssertEqual(app.buttons["diet-meal-Morning"].value as? String, "none")
        XCTAssertEqual(calories(total), 0)
    }

    func testTheDayCanBeChangedWithTheArrows() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let today = app.staticTexts["diet-date"].label

        app.buttons["diet-next-day"].tap()

        XCTAssertNotEqual(app.staticTexts["diet-date"].label, today)
        XCTAssertTrue(app.buttons["diet-back-to-today"].waitForExistence(timeout: 5))
        app.buttons["diet-back-to-today"].tap()
        XCTAssertEqual(app.staticTexts["diet-date"].label, today)
    }

    // MARK: Extras

    private func calories(_ element: XCUIElement) -> Int {
        Int(element.label.replacingOccurrences(of: ",", with: "").filter(\.isNumber)) ?? -1
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
    }

    func testFourBiscuitsAreWorkedOutFromThePackAndAddedToTheDay() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let before = calories(total)
        let add = app.buttons["diet-add-extra"]
        scrollTo(add)
        add.tap()

        let search = app.textFields["extra-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Tea")
        let result = app.buttons["extra-result-Tea biscuits"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()

        let plus = app.buttons["extra-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        for _ in 0..<3 { plus.tap() }
        XCTAssertEqual(app.textFields["extra-amount-field"].value as? String, "4")
        XCTAssertEqual(calories(app.staticTexts["extra-preview-calories"]), 137, "4 pieces of 250 g / 35 at 480 kcal per 100 g")

        app.buttons["extra-add-button"].tap()

        XCTAssertTrue(app.descendants(matching: .any)["diet-extra-Tea biscuits"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(abs(calories(total) - (before + 137)), 1, "the totals are shown rounded")
    }

    private func addTeaBiscuits(pieces: Int) {
        let add = app.buttons["diet-add-extra"]
        scrollTo(add)
        add.tap()
        let search = app.textFields["extra-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Tea")
        app.buttons["extra-result-Tea biscuits"].tap()
        let plus = app.buttons["extra-plus"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5))
        for _ in 1..<pieces { plus.tap() }
        app.buttons["extra-add-button"].tap()
    }

    func testAnExtraCanBeChangedFromThreePiecesToFourWithoutAddingAnother() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let before = calories(total)
        addTeaBiscuits(pieces: 3)
        let extra = app.buttons["diet-extra-Tea biscuits"]
        XCTAssertTrue(extra.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(abs(calories(total) - (before + 103)), 1, "3 pieces are 103 kcal")

        extra.tap()

        XCTAssertEqual(app.textFields["extra-amount-field"].value as? String, "3", "it reopens on the 3 pieces it was added with")
        XCTAssertTrue(app.staticTexts["extra-editing-food"].exists)
        app.buttons["extra-plus"].tap()
        XCTAssertEqual(app.textFields["extra-amount-field"].value as? String, "4")
        app.buttons["extra-add-button"].tap()

        XCTAssertTrue(app.buttons["diet-extra-Tea biscuits"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "diet-extra-Tea biscuits").count, 1, "the extra was changed, not added again")
        XCTAssertLessThanOrEqual(abs(calories(total) - (before + 137)), 1, "4 pieces are 137 kcal")
    }

    func testAnExtraCanBeRemovedFromItsEditSheet() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let before = calories(total)
        addTeaBiscuits(pieces: 2)
        let extra = app.buttons["diet-extra-Tea biscuits"]
        XCTAssertTrue(extra.waitForExistence(timeout: 5))
        extra.tap()

        let remove = app.buttons["extra-remove-button"]
        scrollTo(remove)
        remove.tap()

        XCTAssertTrue(app.staticTexts["diet-total-calories"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["diet-extra-Tea biscuits"].exists)
        XCTAssertEqual(calories(total), before)
    }

    func testANewFoodCanBeCreatedFromTheSheetAndAddedStraightAway() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        let add = app.buttons["diet-add-extra"]
        scrollTo(add)
        add.tap()
        let search = app.textFields["extra-search-field"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Rice cakes")
        let newFood = app.buttons["extra-new-food"]
        XCTAssertTrue(newFood.waitForExistence(timeout: 5))
        newFood.tap()

        let calories = app.textFields["food-calories-field"]
        XCTAssertTrue(calories.waitForExistence(timeout: 5))
        calories.tap()
        calories.typeText("400")
        app.buttons["food-save-button"].tap()

        // The new food is selected with 30 g, which is 120 kcal at 400 kcal per 100 g.
        XCTAssertTrue(app.staticTexts["extra-preview-calories"].waitForExistence(timeout: 5))
        XCTAssertEqual(self.calories(app.staticTexts["extra-preview-calories"]), 120)
    }

    // MARK: Foods and recipes

    private func openFoods() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        app.buttons["diet-segment-foods"].tap()
    }

    func testFoodsListsTheLibraryAndCanBeSearched() {
        openFoods()
        XCTAssertTrue(app.descendants(matching: .any)["food-row-Peanuts"].waitForExistence(timeout: 5))

        let search = app.textFields["foods-search-field"]
        search.tap()
        search.typeText("oats")

        XCTAssertTrue(app.descendants(matching: .any)["food-row-Rolled oats"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["food-row-Peanuts"].exists)
    }

    func testARecipeShowsWhatOnePieceMakesAndItsIngredients() {
        openFoods()
        let recipe = app.descendants(matching: .any)["food-row-Flatbread"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()

        let kcal = app.staticTexts["recipe-calories"]
        XCTAssertTrue(kcal.waitForExistence(timeout: 5))
        XCTAssertEqual(calories(kcal), 145, "60 g rice flour and 20 g oats make 2 pieces")
        XCTAssertTrue(app.descendants(matching: .any)["recipe-line-Rice flour"].exists)
    }

    func testChangingAnIngredientQuantityUpdatesTheRecipe() {
        openFoods()
        let recipe = app.descendants(matching: .any)["food-row-Flatbread"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 5))
        recipe.tap()
        let line = app.descendants(matching: .any)["recipe-line-Rice flour"]
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        line.tap()

        let quantity = app.textFields["ingredient-quantity-field"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        quantity.tap()
        quantity.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        quantity.typeText("100")
        app.buttons["ingredient-save-button"].tap()

        XCTAssertTrue(app.staticTexts["recipe-calories"].waitForExistence(timeout: 5))
        XCTAssertEqual(calories(app.staticTexts["recipe-calories"]), 216, "100 g rice flour and 20 g oats make 2 pieces")
    }

    // MARK: Plan and cycles

    private func openPlan() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        app.buttons["diet-segment-plan"].tap()
    }

    private func clearAndType(_ field: XCUIElement, _ text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        field.typeText(text)
    }

    func testThePlanListsItsMealsAndChangesStartFromToday() {
        openPlan()

        XCTAssertTrue(app.descendants(matching: .any)["plan-item-Morning-Rolled oats"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["plan-edit-from"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["plan-item-Lunch-Mineral"].exists)
    }

    func testChangingAQuantityInThePlanChangesTodaysTotal() {
        XCTAssertTrue(total.waitForExistence(timeout: 15))
        app.buttons["diet-meal-Morning"].tap()
        let before = calories(total)
        XCTAssertGreaterThan(before, 0)
        app.buttons["diet-segment-plan"].tap()
        let item = app.descendants(matching: .any)["plan-item-Morning-Rolled oats"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()

        let quantity = app.textFields["plan-quantity-field"]
        XCTAssertTrue(quantity.waitForExistence(timeout: 5))
        clearAndType(quantity, "120")
        app.buttons["plan-item-save"].tap()

        app.buttons["diet-segment-today"].tap()
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(calories(total), before, "60 g more oats from today on")
    }

    func testACycleCanBeChosenInWeeksFromAPresetAndShowsWhereTodayIs() {
        openPlan()
        let mineral = app.descendants(matching: .any)["plan-item-Lunch-Mineral"]
        XCTAssertTrue(mineral.waitForExistence(timeout: 5))
        mineral.tap()

        let summary = app.staticTexts["cycle-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("2 weeks on · 1 week off"), summary.label)

        let preset = app.buttons["cycle-preset-3-1"]
        scrollTo(preset)
        preset.tap()
        XCTAssertTrue(app.staticTexts["cycle-summary"].label.contains("3 weeks on · 1 week off"))
        XCTAssertTrue(app.descendants(matching: .any)["cycle-calendar"].exists)

        let save = app.buttons["plan-item-save"]
        scrollTo(save)
        save.tap()

        XCTAssertTrue(app.descendants(matching: .any)["plan-item-Lunch-Mineral"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["plan-item-Lunch-Mineral"].label.contains("3 weeks on · 1 week off"))
    }

    func testAFoodCanBeGivenWeekdaysOnly() {
        openPlan()
        let oats = app.descendants(matching: .any)["plan-item-Morning-Rolled oats"]
        XCTAssertTrue(oats.waitForExistence(timeout: 5))
        oats.tap()

        let weekdays = app.buttons["cycle-mode-Weekdays"]
        scrollTo(weekdays)
        weekdays.tap()
        let quick = app.buttons["cycle-quick-Weekends"]
        scrollTo(quick)
        quick.tap()

        XCTAssertTrue(app.staticTexts["cycle-summary"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["cycle-summary"].label.contains("Weekends"))
    }

    func testTheDietTargetsCanBeChanged() {
        openPlan()
        let edit = app.buttons["plan-edit-rules"]
        scrollTo(edit)
        edit.tap()

        let protein = app.textFields["rules-protein-field"]
        XCTAssertTrue(protein.waitForExistence(timeout: 5))
        clearAndType(protein, "190")
        app.buttons["rules-save-button"].tap()

        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Protein at least 190'")).firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: Body tab

    private func launchOnBody() {
        app.terminate()
        app.launchArguments = UITestSeed.launchArguments + ["-UITestInitialTab", "1"]
        app.launch()
    }

    func testTheBodyTabOpensTodaysDietAndSaysWhereTheCaloriesComeFrom() {
        launchOnBody()
        let open = app.buttons["open-todays-diet-button"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["calorie-source-note"].exists, "the demo plan covers the recent days")

        open.tap()

        XCTAssertTrue(total.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["diet-date"].exists)
    }

    func testTappingADayInRecentCaloriesOpensThatDaysDiet() {
        launchOnBody()
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'calorie-day-'")).firstMatch
        scrollTo(row)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()

        XCTAssertTrue(total.waitForExistence(timeout: 10))
    }
}
