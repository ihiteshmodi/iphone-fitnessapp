import XCTest
@testable import FitnessCore

final class ExtraNotesTests: XCTestCase {
    private var db: Database!
    private var library: FoodLibrary!
    private var diet: DietDayService!
    private let day = date("2026-11-19")

    override func setUpWithError() throws {
        db = try Database.inMemory()
        library = FoodLibrary(db)
        diet = DietDayService(db)
    }

    private func extras() throws -> [DietExtra] { try diet.day(day).extras }

    func testAnExtraKeepsATimeANameAndANoteThatCanBeChanged() throws {
        let oreo = try library.add(FoodDraft(name: "Oreo biscuit", unit: "unit", baseQuantity: 1, carbs: 7, fat: 2.3))
        let id = try diet.addExtra(foodID: oreo, .amount(4), on: day, details: ExtraDetails(time: .evening, note: "office"))

        XCTAssertEqual(try extras().first?.details, ExtraDetails(time: .evening, note: "office"))

        try diet.updateExtraDetails(id, ExtraDetails(time: .night))

        XCTAssertEqual(try extras().first?.details, ExtraDetails(time: .night))
        XCTAssertEqual(try extras().first?.displayName, "Oreo biscuit")
    }

    func testExtrasAreGroupedMorningNoonEveningNightThenNoTime() throws {
        let banana = try library.add(FoodDraft(name: "Banana", unit: "unit", baseQuantity: 1, carbs: 27))
        for time in [ExtraTime.evening, .morning, nil, .noon] {
            try diet.addExtra(foodID: banana, .amount(1), on: day, details: ExtraDetails(time: time))
        }

        XCTAssertEqual(try diet.day(day).extrasByTime.map(\.time), [.morning, .noon, .evening, nil])
    }

    func testQuickAddByWeightUsesThePresetGramsPerUnit() throws {
        let batch = try library.add(FoodDraft(name: "Extra calorie batches", unit: "unit", baseQuantity: 1, carbs: 12.7, fat: 5.5, estimateGrams: 20))

        try diet.quickAddByWeight(presetID: batch, grams: 30, on: day, details: ExtraDetails(label: "Kaju katli", time: .evening))

        let extra = try XCTUnwrap(try extras().first)
        XCTAssertEqual(extra.displayName, "Kaju katli")
        XCTAssertEqual(extra.amount, 1.5, accuracy: 1e-9)
        XCTAssertEqual(extra.nutrition.calories, 100.3 * 1.5, accuracy: 1e-6)
        XCTAssertEqual(extra.nutrition.carbs, 19.05, accuracy: 1e-9)
        XCTAssertEqual(try library.estimatePresets().map(\.id), [batch])
    }

    func testQuickAddByWeightNeedsAPreset() throws {
        let oats = try library.add(FoodDraft(name: "Oats", protein: 13, carbs: 68, fat: 7))

        XCTAssertThrowsError(try diet.quickAddByWeight(presetID: oats, grams: 30, on: day, details: ExtraDetails())) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Oats is not set up for quick add by weight"))
        }
    }

    func testQuickAddCaloriesOnly() throws {
        try diet.quickAddCalories(300, on: day, details: ExtraDetails(label: "Pani puri"))

        let extra = try XCTUnwrap(try extras().first)
        XCTAssertEqual(extra.displayName, "Pani puri")
        XCTAssertEqual(extra.nutrition, Nutrition(calories: 300))
    }
}
