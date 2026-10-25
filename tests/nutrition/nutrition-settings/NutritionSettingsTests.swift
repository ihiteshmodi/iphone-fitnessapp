import XCTest
@testable import FitnessCore

final class NutritionSettingsTests: XCTestCase {
    private var db: Database!
    private var nutrition: NutritionSettings!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        nutrition = NutritionSettings(db)
    }

    private func addTwoWeeksOfWeights() throws {
        let latest = date("2026-10-23")
        for offset in 0..<7 { try db.addBodyWeight(on: latest.adding(days: -offset).string, kg: 63.86) }
        for offset in 7..<14 { try db.addBodyWeight(on: latest.adding(days: -offset).string, kg: 63.94) }
    }

    func testDefaultRulesAre1Point2GramsPerLbAnd25PercentFat() throws {
        XCTAssertEqual(try nutrition.rules(), MacroRules(proteinGramsPerLb: 1.2, fatPercent: 25))
    }

    func testChangingTheProteinRuleChangesCuttingMacros() throws {
        try nutrition.setProteinGramsPerLb(1.0)

        let target = CalorieTarget.calculate(currentAverageKg: 63.86, pastAverageKg: 63.94, caloriesEaten: 2948.5,
                                             multiplier: 0.8, rules: try nutrition.rules())

        XCTAssertEqual(target.macros?.proteinGrams, 140.49)
    }

    func testChangingTheFatShareChangesCuttingMacros() throws {
        try nutrition.setFatPercent(30)

        let target = CalorieTarget.calculate(currentAverageKg: 63.86, pastAverageKg: 63.94, caloriesEaten: 2948.5,
                                             multiplier: 0.8, rules: try nutrition.rules())

        XCTAssertEqual(target.adjustedTarget, 2429)
        XCTAssertEqual(target.macros?.fatGrams, 80.97)
    }

    func testRejectsRulesThatLeaveNoRoomForCarbs() throws {
        XCTAssertThrowsError(try nutrition.setFatPercent(95)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Fat share must be between 10% and 60%"))
        }
        XCTAssertThrowsError(try nutrition.setProteinGramsPerLb(0)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Protein must be greater than 0"))
        }
        XCTAssertEqual(try nutrition.rules().fatPercent, 25)
    }

    func testCorrectingATypoInBodyWeight() throws {
        try db.addBodyWeight(on: "2022-09-22", kg: 6.95)
        let log = LogBodyMetrics(db)
        let entry = try XCTUnwrap(try log.recentWeights().first)

        try log.updateWeight(id: entry.id, kg: 69.5)

        let edited = try XCTUnwrap(try log.recentWeights().first)
        XCTAssertEqual(edited.kg, 69.5)
        XCTAssertEqual(edited.date, date("2022-09-22"))
    }

    func testEditingAWeighInCanAlsoMoveItsDate() throws {
        let log = LogBodyMetrics(db)
        let id = try log.logWeight(kg: 63.9, on: "2026-10-23")

        try log.updateWeight(id: id, kg: 64.1, on: "2026-10-22")

        XCTAssertEqual(try log.recentWeights(), [BodyWeightEntry(id: id, date: date("2026-10-22"), kg: 64.1)])
        XCTAssertThrowsError(try log.updateWeight(id: id, kg: 64.1, on: "2026-13-01")) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Date is not valid"))
        }
        XCTAssertThrowsError(try log.updateWeight(id: id, kg: 0)) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Body weight must be above 0"))
        }
    }

    func testDeletingAWrongWeighInRecalculatesTheAverages() throws {
        try addTwoWeeksOfWeights()
        let log = LogBodyMetrics(db)
        let wrong = try log.logWeight(kg: 90, on: "2026-10-23")
        let service = CalorieService(db)
        XCTAssertGreaterThan(try service.weeklyAverages().currentAverageKg, 65)

        try log.deleteWeight(id: wrong)

        XCTAssertEqual(try service.weeklyAverages().currentAverageKg, 63.86, accuracy: 1e-9)
    }

    func testEditingCaloriesEatenChangesTheTarget() throws {
        try addTwoWeeksOfWeights()
        let service = CalorieService(db)
        try service.saveCalories(on: date("2026-10-23"), calories: 2948.5)

        try service.saveCalories(on: date("2026-10-23"), calories: 3100)

        let target = try service.currentAdvice().target
        XCTAssertEqual(target.caloriesEaten, 3100)
        XCTAssertEqual(target.adjustedTarget, 3188)
    }
}
