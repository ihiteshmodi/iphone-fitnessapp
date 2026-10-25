import XCTest
@testable import FitnessCore

final class CalorieTargetTests: XCTestCase {
    private let defaultRules = MacroRules(proteinGramsPerLb: 1.2, fatPercent: 25)

    // MARK: pure calculator

    func testWeightDroppingMeansCutPhase() {
        let target = CalorieTarget.calculate(currentAverageKg: 63.86, pastAverageKg: 63.94, caloriesEaten: 2948.5, rules: defaultRules)

        XCTAssertEqual(target.maintenanceCalories, 3036.61)
        XCTAssertEqual(target.phase, .cut)
        XCTAssertEqual(target.dailyDeficitOrSurplus, 88.11)
        XCTAssertEqual(target.adjustedTarget, 3037)
        XCTAssertNil(target.macros)
    }

    func testWeightRisingMeansMaintenanceOrBulkPhase() {
        let target = CalorieTarget.calculate(currentAverageKg: 64.5, pastAverageKg: 64.0, caloriesEaten: 3000, rules: defaultRules)

        XCTAssertEqual(target.phase, .maintenanceOrBulk)
        XCTAssertEqual(target.phase.rawValue, "Maintenance / Bulk")
        XCTAssertEqual(target.dailyDeficitOrSurplus, 550.66)
        XCTAssertEqual(target.maintenanceCalories, 2449.34)
    }

    func testCuttingMultiplierAddsMacros() throws {
        let target = CalorieTarget.calculate(currentAverageKg: 63.86, pastAverageKg: 63.94, caloriesEaten: 2948.5,
                                             multiplier: 0.8, rules: defaultRules)

        XCTAssertEqual(target.adjustedTarget, 2429)
        let macros = try XCTUnwrap(target.macros)
        XCTAssertEqual(macros.proteinGrams, 168.59)
        XCTAssertEqual(macros.proteinCalories, 674.36)
        XCTAssertEqual(macros.fatGrams, 67.47)
        XCTAssertEqual(macros.fatCalories, 607.25)
        XCTAssertEqual(macros.carbsGrams, 286.85)
        XCTAssertEqual(macros.carbsCalories, 1147.39)
    }

    func testMacrosAreOnlyForAMultiplierBelowOne() {
        for multiplier in [1.0, 1.1] {
            let target = CalorieTarget.calculate(currentAverageKg: 63.86, pastAverageKg: 63.94, caloriesEaten: 2948.5,
                                                 multiplier: multiplier, rules: defaultRules)
            XCTAssertNil(target.macros, "multiplier \(multiplier)")
        }
    }

    func testTargetRoundsHalvesToEvenLikePython() {
        // Zero weight change keeps maintenance equal to calories eaten: 2500.5 * 1 -> 2500, 2501.5 -> 2502.
        let down = CalorieTarget.calculate(currentAverageKg: 64, pastAverageKg: 64, caloriesEaten: 2500.5, rules: defaultRules)
        let up = CalorieTarget.calculate(currentAverageKg: 64, pastAverageKg: 64, caloriesEaten: 2501.5, rules: defaultRules)

        XCTAssertEqual(down.adjustedTarget, 2500)
        XCTAssertEqual(up.adjustedTarget, 2502)
    }

    func testNoWeightChangeIsTreatedAsCutLikeTheNotebook() {
        let target = CalorieTarget.calculate(currentAverageKg: 64, pastAverageKg: 64, caloriesEaten: 2800, rules: defaultRules)

        XCTAssertEqual(target.phase, .cut)
        XCTAssertEqual(target.dailyDeficitOrSurplus, 0)
        XCTAssertEqual(target.maintenanceCalories, 2800)
    }

    func testCurrentVersusTargetIsCaloriesEatenMinusNewTarget() {
        let target = CalorieTarget.calculate(currentAverageKg: 63.86, pastAverageKg: 63.94, caloriesEaten: 2948.5,
                                             multiplier: 0.8, rules: defaultRules)

        XCTAssertEqual(target.currentVersusTarget, 519.5)
    }

    // MARK: service

    private func makeDatabase(weights: [(String, Double)] = [], calories: (String, Double, Double)? = nil) throws -> (Database, CalorieService) {
        let db = try Database.inMemory()
        for (day, kg) in weights { try db.addBodyWeight(on: day, kg: kg) }
        let service = CalorieService(db)
        if let calories { try service.saveCalories(on: calories.0, calories: calories.1, multiplier: calories.2) }
        return (db, service)
    }

    /// Seven weigh-ins ending 2026-10-23 at 63.86 and seven before that at 63.94.
    private var twoWeeksOfWeights: [(String, Double)] {
        let latest = date("2026-10-23")
        return (0..<7).map { (latest.adding(days: -$0).string, 63.86) } + (7..<14).map { (latest.adding(days: -$0).string, 63.94) }
    }

    func testServiceCalculatesFromTheLatestCalorieEntryAndWeights() throws {
        let (_, service) = try makeDatabase(weights: twoWeeksOfWeights, calories: ("2026-10-23", 2948.5, 1))

        let advice = try service.currentAdvice()

        XCTAssertEqual(advice.averages.latestWeighIn, date("2026-10-23"))
        XCTAssertEqual(advice.averages.currentAverageKg, 63.86, accuracy: 1e-9)
        XCTAssertEqual(advice.averages.pastAverageKg, 63.94, accuracy: 1e-9)
        XCTAssertEqual(advice.target.maintenanceCalories, 3036.61)
        XCTAssertEqual(advice.target.adjustedTarget, 3037)
    }

    func testServiceUsesTheSavedMultiplierAndMacroRules() throws {
        let (db, service) = try makeDatabase(weights: twoWeeksOfWeights, calories: ("2026-10-23", 2948.5, 0.8))
        try SettingsRepository(db).setProteinGramsPerLb(1.0)

        let target = try service.currentAdvice().target

        XCTAssertEqual(target.adjustedTarget, 2429)
        XCTAssertEqual(target.macros?.proteinGrams, 140.49)
    }

    func testWindowsIncludeTheirBoundaryDays() throws {
        // latest 10-23: current window 10-17...10-23, previous 10-10...10-16, 10-09 is ignored.
        let weights: [(String, Double)] = [("2026-10-23", 64), ("2026-10-17", 66), ("2026-10-16", 70), ("2026-10-10", 72), ("2026-10-09", 100)]
        let (_, service) = try makeDatabase(weights: weights)

        let averages = try service.weeklyAverages()

        XCTAssertEqual(averages.currentAverageKg, 65, accuracy: 1e-9)
        XCTAssertEqual(averages.pastAverageKg, 71, accuracy: 1e-9)
    }

    func testNotEnoughWeighInsInThePreviousWeek() throws {
        let weights: [(String, Double)] = [("2026-10-23", 64), ("2026-10-20", 64), ("2026-10-09", 70)]
        let (_, service) = try makeDatabase(weights: weights, calories: ("2026-10-23", 2900, 1))

        XCTAssertThrowsError(try service.currentAdvice()) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Log body weight for both of the last two weeks"))
        }
    }

    func testNoWeighInsAtAll() throws {
        let (_, service) = try makeDatabase(calories: ("2026-10-23", 2900, 1))

        XCTAssertThrowsError(try service.weeklyAverages()) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Log body weight for both of the last two weeks"))
        }
    }

    func testAdviceNeedsCaloriesEaten() throws {
        let (_, service) = try makeDatabase(weights: twoWeeksOfWeights)

        XCTAssertThrowsError(try service.currentAdvice()) { error in
            XCTAssertEqual(error as? ValidationError, ValidationError("Log the calories you ate per day"))
        }
    }

    func testPreviewAdviceDoesNotSaveAnything() throws {
        let (_, service) = try makeDatabase(weights: twoWeeksOfWeights)

        let advice = try service.advice(caloriesEaten: 3000, multiplier: 1)

        XCTAssertEqual(advice.target.caloriesEaten, 3000)
        XCTAssertNil(try service.latestEntry())
    }

    func testSavingCaloriesReplacesTheSameDay() throws {
        let (_, service) = try makeDatabase(calories: ("2026-10-23", 2948.5, 1))

        try service.saveCalories(on: date("2026-10-23"), calories: 3100, multiplier: 0.9)
        try service.saveCalories(on: "2026-10-22", calories: 2800)

        XCTAssertEqual(try service.latestEntry(), CalorieEntry(date: date("2026-10-23"), calories: 3100, multiplier: 0.9))
        XCTAssertEqual(try service.recentEntries().map(\.calories), [3100, 2800])
        XCTAssertEqual(try service.recentEntries(limit: 1).count, 1)
    }

    func testDeletingACalorieEntry() throws {
        let (_, service) = try makeDatabase(calories: ("2026-10-23", 2948.5, 1))

        try service.deleteCalories(on: date("2026-10-23"))

        XCTAssertNil(try service.latestEntry())
    }

    func testRejectsInvalidCalorieEntries() throws {
        let (_, service) = try makeDatabase()
        let examples: [(Double, Double, String, String)] = [
            (0, 1, "2026-10-23", "Calories must be above 0"),
            (-100, 1, "2026-10-23", "Calories must be above 0"),
            (2900, 0, "2026-10-23", "Multiplier must be above 0"),
            (2900, 1, "2026-02-30", "Date is not valid"),
        ]

        for (calories, multiplier, day, message) in examples {
            XCTAssertThrowsError(try service.saveCalories(on: day, calories: calories, multiplier: multiplier), message) { error in
                XCTAssertEqual(error as? ValidationError, ValidationError(message))
            }
        }
        XCTAssertNil(try service.latestEntry())
    }
}
