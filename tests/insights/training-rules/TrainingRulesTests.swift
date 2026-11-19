import XCTest
@testable import FitnessCore

final class TrainingRulesTests: XCTestCase {
    private var db: Database!
    private let today = date("2026-11-19")
    private var bench = 0

    override func setUpWithError() throws {
        db = try Database.inMemory()
        bench = try db.addExercise("Bench press", muscle: "Chest")
        try SettingsRepository(db).setHistoryStartDate("2026-01-01")
    }

    private func setup() throws -> [Insight] { try InsightService(db, daily: [], setup: TrainingRules.setup).setup(on: today) }

    func testBackToBackDaysThatTrainTheSameMuscle() throws {
        let closeGrip = try db.addExercise("Close-grip bench press", muscle: "Chest")
        let monday = try db.addDay(position: 1, weekday: 1, title: "Push")
        try db.addEntry(day: monday, exercise: bench)
        let tuesday = try db.addDay(position: 2, weekday: 2, title: "Arms")
        try db.addEntry(day: tuesday, exercise: closeGrip)

        let item = try XCTUnwrap(try setup().first { $0.ruleID == "training-spacing" })
        XCTAssertTrue(item.detail.contains("Mon and Tue"), item.detail)
        XCTAssertTrue(item.detail.contains("Chest"), item.detail)
        XCTAssertTrue(item.why.contains("48"))

        try db.execute("UPDATE plan_days SET weekday = 3 WHERE id = ?", [.int(Int64(tuesday))])
        XCTAssertFalse(try setup().contains { $0.ruleID == "training-spacing" })
    }

    func testAKeyLiftDroppingTwoSessionsInARow() throws {
        let monday = try db.addDay(position: 1, weekday: 1, title: "Push")
        try db.addEntry(day: monday, exercise: bench)
        for (day, kg) in [("2026-11-03", 80.0), ("2026-11-10", 77.5), ("2026-11-17", 75.0)] { try db.addSet(exercise: bench, on: day, weight: kg, reps: 8) }

        let item = try XCTUnwrap(try setup().first { $0.ruleID == "deload" })
        XCTAssertEqual(item.title, "Deload suggested")
        XCTAssertTrue(item.detail.contains("Bench press dropped 2 sessions in a row"))
        XCTAssertEqual(item.action, .turnOnDeload)
    }

    func testWeeksSinceTheLastDeload() throws {
        try db.addSet(exercise: bench, on: today.adding(days: -63).string, weight: 60, reps: 8)
        try db.addSet(exercise: bench, on: today.adding(days: -2).string, weight: 62.5, reps: 8)

        let item = try XCTUnwrap(try setup().first { $0.ruleID == "deload" })
        XCTAssertEqual(item.title, "Deload due")
        XCTAssertTrue(item.detail.contains("9 weeks"))

        try SettingsRepository(db).setDeloadEnabled(true)
        XCTAssertFalse(try setup().contains { $0.ruleID == "deload" })
    }

    func testWeeklyHardSetsPerMuscle() throws {
        for _ in 0..<6 { try db.addSet(exercise: bench, on: "2026-11-17", weight: 60, reps: 8) }

        let rule = try XCTUnwrap(TrainingRules.daily.first { $0.id == "weekly-sets" })
        guard case .fired(let item) = try rule.evaluate(on: date("2026-11-18"), db: db) else { return XCTFail("should fire") }
        XCTAssertTrue(item.detail.contains("Chest 6 sets"), item.detail)
        XCTAssertEqual(item.severity, .tip)
    }

    func testACutLosingTooFast() throws {
        for offset in 0..<7 { try db.addBodyWeight(on: today.adding(days: -offset).string, kg: 65.0) }
        for offset in 7..<14 { try db.addBodyWeight(on: today.adding(days: -offset).string, kg: 66.0) }
        try CalorieService(db).setDefault(calories: 2500, multiplier: 0.85, from: date("2026-10-01"))

        let item = try XCTUnwrap(try setup().first { $0.ruleID == "cut-bulk-rate" })
        XCTAssertEqual(item.title, "Cutting fast")
        XCTAssertTrue(item.detail.contains("1.5%"), item.detail)
    }
}
