import XCTest
@testable import FitnessCore

/// The diet tables arrive with schema version 8 and an older database is upgraded in place, keeping what it had.
final class DietSchemaTests: DatabaseFileTestCase {
    private let dietTables = ["foods", "recipe_items", "diet_plans", "diet_plan_items", "diet_day_ticks", "diet_extras"]

    private func tableNames(in db: Database) throws -> Set<String> {
        Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").map { $0.text("name") })
    }

    private func installVersion7Database() throws {
        let url = try makeFitnessDatabase(named: "v7.sqlite")
        let raw = try Database(path: url.path)
        for table in ["diet_extras", "diet_day_ticks", "diet_plan_items", "diet_plans", "recipe_items", "foods"] {
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
        XCTAssertEqual(db.userVersion, 9)
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

    /// A version 8 database: the diet tables as they were, when "skipped" items were stored and everything else counted.
    private func installVersion8Database(skipOatsOn skipDay: String = "2026-10-29") throws {
        let url = try makeFitnessDatabase(named: "v8.sqlite")
        let raw = try Database(path: url.path)
        try raw.execute("DROP TABLE diet_day_ticks")
        try raw.execute("""
            CREATE TABLE diet_day_skips (
                day TEXT NOT NULL, meal TEXT NOT NULL,
                food_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE, PRIMARY KEY (day, meal, food_id))
            """)
        try raw.execute("INSERT INTO foods (name) VALUES ('Oats')")
        let oats = Int64(raw.lastInsertRowID)
        try raw.execute("INSERT INTO foods (name) VALUES ('Shake')")
        let shake = Int64(raw.lastInsertRowID)
        try raw.execute("INSERT INTO diet_plans (effective_from) VALUES ('2026-10-26')")
        try raw.execute("INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity) VALUES ('2026-10-26', 'Morning', 1, ?, 50)", [.int(oats)])
        try raw.execute("INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity) VALUES ('2026-10-26', 'Brunch', 2, ?, 1)", [.int(shake)])
        try raw.execute("INSERT INTO diet_day_skips (day, meal, food_id) VALUES (?, 'Morning', ?)", [.text(skipDay), .int(oats)])
        try raw.addBodyWeight(on: "2026-10-30", kg: 64)
        try raw.runScript("PRAGMA user_version = 8")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    private func ticks(_ db: Database) throws -> [String] {
        try db.query("SELECT t.day, t.meal, f.name FROM diet_day_ticks t JOIN foods f ON f.id = t.food_id ORDER BY t.day, t.meal")
            .map { "\($0.text("day")) \($0.text("meal")) \($0.text("name"))" }
    }

    func testOpeningAVersion8DatabaseKeepsEveryEarlierDietDayAsItWas() throws {
        try installVersion8Database()

        let db = try XCTUnwrap(try service.openLiveDatabase())
        let all = try ticks(db)

        XCTAssertEqual(db.userVersion, Schema.currentVersion)
        XCTAssertEqual(all.filter { $0.hasSuffix("Shake") }.map { String($0.prefix(10)) },
                       ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30"], "the plan start to the latest activity")
        XCTAssertEqual(all.filter { $0.hasSuffix("Oats") }.map { String($0.prefix(10)) },
                       ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-30"], "Oats was unticked on the 29th")
        XCTAssertFalse(all.contains { $0.hasPrefix("2026-10-31") }, "days after the latest activity start unticked")
        XCTAssertFalse(try tableNames(in: db).contains("diet_day_skips"))
    }

    func testOpeningAVersion8DatabaseAgainDoesNotTickAnythingBack() throws {
        try installVersion8Database()
        let first = try XCTUnwrap(try service.openLiveDatabase())
        try first.execute("DELETE FROM diet_day_ticks WHERE day = '2026-10-30'")

        let again = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertFalse(try ticks(again).contains { $0.hasPrefix("2026-10-30") })
    }

    func testAVersion8DatabaseWithoutADietPlanGetsNoTicks() throws {
        let url = try makeFitnessDatabase(named: "v8-empty.sqlite")
        let raw = try Database(path: url.path)
        try raw.execute("DROP TABLE diet_day_ticks")
        try raw.execute("CREATE TABLE diet_day_skips (day TEXT NOT NULL, meal TEXT NOT NULL, food_id INTEGER NOT NULL, PRIMARY KEY (day, meal, food_id))")
        try raw.runScript("PRAGMA user_version = 8")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertEqual(try db.count("diet_day_ticks"), 0)
    }

    func testATickNeedsAValidDayAndIsKeptOncePerItem() throws {
        let db = try Database.inMemory()
        try db.execute("INSERT INTO foods (name) VALUES ('Oats')")
        let oats = Int64(db.lastInsertRowID)

        XCTAssertNoThrow(try db.execute("INSERT INTO diet_day_ticks (day, meal, food_id) VALUES ('2026-10-26', 'Morning', ?)", [.int(oats)]))
        XCTAssertThrowsError(try db.execute("INSERT INTO diet_day_ticks (day, meal, food_id) VALUES ('2026-10-26', 'Morning', ?)", [.int(oats)]))
        XCTAssertThrowsError(try db.execute("INSERT INTO diet_day_ticks (day, meal, food_id) VALUES ('26 Oct', 'Morning', ?)", [.int(oats)]))
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
