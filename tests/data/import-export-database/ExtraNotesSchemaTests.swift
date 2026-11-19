import XCTest
@testable import FitnessCore

/// Version 11: extras gain a name, time and note, and the 91-calorie "Extra calorie batches" becomes 100 calories.
final class ExtraNotesSchemaTests: DatabaseFileTestCase {
    private func installVersion10Database(batchCarbs: Double, batchFat: Double) throws {
        let url = try makeFitnessDatabase(named: "v10.sqlite")
        let raw = try Database(path: url.path)
        try raw.runScript("""
            ALTER TABLE diet_extras DROP COLUMN label;
            ALTER TABLE diet_extras DROP COLUMN time_tag;
            ALTER TABLE diet_extras DROP COLUMN note;
            ALTER TABLE foods DROP COLUMN estimate_grams;
            PRAGMA user_version = 10;
            """)
        try raw.execute("INSERT INTO foods (id, name, kind, unit, base_qty, protein, carbs, fat, fiber, sat_fat, sodium) VALUES (66, 'Extra calorie batches', 'food', 'unit', 1, 0, ?, ?, 0, 0, 0)",
                        [.double(batchCarbs), .double(batchFat)])
        try raw.execute("INSERT INTO diet_extras (day, food_id, amount, pieces) VALUES ('2026-11-18', 66, 3, 3)")
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    func testUpgradingMakesTheBatch100CaloriesOnEveryDayItWasUsed() throws {
        try installVersion10Database(batchCarbs: 7, batchFat: 7)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        let batch = try XCTUnwrap(try FoodLibrary(db).food(66))
        XCTAssertEqual([batch.draft.carbs, batch.draft.fat, batch.draft.estimateGrams], [7.7, 7.7, 10])
        XCTAssertEqual(try DietDayService(db).day(date("2026-11-18")).extras.first?.nutrition.calories ?? 0, 300.3, accuracy: 1e-6)
    }

    func testABatchAlreadyChangedByHandIsLeftAsItIs() throws {
        try installVersion10Database(batchCarbs: 10, batchFat: 5)

        let db = try XCTUnwrap(try service.openLiveDatabase())

        let batch = try XCTUnwrap(try FoodLibrary(db).food(66))
        XCTAssertEqual([batch.draft.carbs, batch.draft.fat], [10, 5])
        XCTAssertNil(batch.draft.estimateGrams)
    }
}
