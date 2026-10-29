import XCTest
@testable import FitnessCore

/// The diet tables arrive with schema version 8 and an older database is upgraded in place, keeping what it had.
final class DietSchemaTests: DatabaseFileTestCase {
    private let dietTables = ["foods", "recipe_items", "diet_plans", "diet_plan_items", "diet_day_skips", "diet_extras"]

    private func tableNames(in db: Database) throws -> Set<String> {
        Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").map { $0.text("name") })
    }

    private func installVersion7Database() throws {
        let url = try makeFitnessDatabase(named: "v7.sqlite")
        let raw = try Database(path: url.path)
        for table in ["diet_extras", "diet_day_skips", "diet_plan_items", "diet_plans", "recipe_items", "foods"] {
            try raw.execute("DROP TABLE \(table)")
        }
        try raw.execute("DELETE FROM settings WHERE key IN ('protein_min_g', 'diet_fat_percent', 'fat_ceiling_g_per_lb')")
        try raw.execute("INSERT INTO calorie_defaults (effective_from, calories, multiplier) VALUES ('2026-10-26', 2839, 1)")
        try raw.runScript("PRAGMA user_version = 7")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    func testAFreshDatabaseHasTheDietTablesAndTheDietRulesAtTheirDefaults() throws {
        let db = try Database.inMemory()

        XCTAssertTrue(Set(dietTables).isSubset(of: try tableNames(in: db)))
        XCTAssertEqual(db.userVersion, 8)
        XCTAssertEqual(try DietSettings(db).load(), DietRules(proteinMinimumGrams: 180, fatPercentOfCalories: 20, fatCeilingGramsPerPound: 0.4))
    }

    func testOpeningAVersion7DatabaseAddsTheDietTablesAndKeepsItsData() throws {
        try installVersion7Database()

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(db.userVersion, Schema.currentVersion)
        XCTAssertTrue(Set(dietTables).isSubset(of: try tableNames(in: db)))
        XCTAssertEqual(try db.query("SELECT calories FROM calorie_defaults").map { $0.double("calories") }, [2839])
        XCTAssertEqual(try DietSettings(db).load().proteinMinimumGrams, 180)
    }

    func testMigrationKeepsAChosenDietRuleAndRunsOnlyOnce() throws {
        try installVersion7Database()
        let first = try XCTUnwrap(try service.openLiveDatabase())
        try first.execute("UPDATE settings SET value = '150' WHERE key = 'protein_min_g'")

        let again = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(try DietSettings(again).load().proteinMinimumGrams, 150)
    }

    func testFoodNamesAreUniqueIgnoringCase() throws {
        let db = try Database.inMemory()
        try db.execute("INSERT INTO foods (name) VALUES ('Rolled oats')")

        XCTAssertThrowsError(try db.execute("INSERT INTO foods (name) VALUES ('rolled OATS')"))
    }

    func testAFoodUsedByARecipeOrAPlanCannotBeDeleted() throws {
        let db = try Database.inMemory()
        try db.execute("INSERT INTO foods (name) VALUES ('Flour')")
        let flour = db.lastInsertRowID
        try db.execute("INSERT INTO foods (name, kind, recipe_makes) VALUES ('Flatbread', 'recipe', 2)")
        let flatbread = db.lastInsertRowID
        try db.execute("INSERT INTO recipe_items (recipe_id, food_id, quantity) VALUES (?, ?, 40)", [.int(Int64(flatbread)), .int(Int64(flour))])
        try db.execute("INSERT INTO diet_plans (effective_from) VALUES ('2026-10-26')")
        try db.execute("INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity) VALUES ('2026-10-26', 'Brunch', 1, ?, 3)", [.int(Int64(flatbread))])

        XCTAssertThrowsError(try db.execute("DELETE FROM foods WHERE id = ?", [.int(Int64(flour))]))
        XCTAssertThrowsError(try db.execute("DELETE FROM foods WHERE id = ?", [.int(Int64(flatbread))]))
    }

    func testDeletingARecipeOrAPlanDeletesItsLines() throws {
        let db = try Database.inMemory()
        try db.execute("INSERT INTO foods (name) VALUES ('Flour')")
        let flour = db.lastInsertRowID
        try db.execute("INSERT INTO foods (name, kind, recipe_makes) VALUES ('Flatbread', 'recipe', 2)")
        let flatbread = db.lastInsertRowID
        try db.execute("INSERT INTO recipe_items (recipe_id, food_id, quantity) VALUES (?, ?, 40)", [.int(Int64(flatbread)), .int(Int64(flour))])
        try db.execute("INSERT INTO diet_plans (effective_from) VALUES ('2026-10-26')")
        try db.execute("INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity) VALUES ('2026-10-26', 'Brunch', 1, ?, 3)", [.int(Int64(flour))])

        try db.execute("DELETE FROM diet_plans WHERE effective_from = '2026-10-26'")
        try db.execute("DELETE FROM foods WHERE id = ?", [.int(Int64(flatbread))])

        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM diet_plan_items").first?.int("n"), 0)
        XCTAssertEqual(try db.query("SELECT COUNT(*) AS n FROM recipe_items").first?.int("n"), 0)
    }

    func testAnExtraNeedsAnAmountAboveZeroAndAValidDay() throws {
        let db = try Database.inMemory()
        try db.execute("INSERT INTO foods (name) VALUES ('Biscuit')")
        let biscuit = Int64(db.lastInsertRowID)

        XCTAssertThrowsError(try db.execute("INSERT INTO diet_extras (day, food_id, amount) VALUES ('2026-10-26', ?, 0)", [.int(biscuit)]))
        XCTAssertThrowsError(try db.execute("INSERT INTO diet_extras (day, food_id, amount) VALUES ('26 Oct', ?, 10)", [.int(biscuit)]))
        XCTAssertNoThrow(try db.execute("INSERT INTO diet_extras (day, food_id, amount) VALUES ('2026-10-26', ?, 10)", [.int(biscuit)]))
    }

    func testAPlanItemCanHoldEachKindOfCycleButNotAnUnknownOne() throws {
        let db = try Database.inMemory()
        try db.execute("INSERT INTO foods (name) VALUES ('Mineral')")
        let food = Int64(db.lastInsertRowID)
        try db.execute("INSERT INTO diet_plans (effective_from) VALUES ('2026-10-26')")

        for mode in ["daily", "weeks", "days", "weekdays", "training"] {
            XCTAssertNoThrow(try db.execute("INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity, cycle_mode) VALUES ('2026-10-26', ?, 1, ?, 1, ?)",
                                            [.text(mode), .int(food), .text(mode)]), mode)
        }
        XCTAssertThrowsError(try db.execute("INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity, cycle_mode) VALUES ('2026-10-26', 'x', 1, ?, 1, 'monthly')", [.int(food)]))
    }
}
