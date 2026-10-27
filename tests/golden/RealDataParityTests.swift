import XCTest
@testable import FitnessCore

/// Runs the new Swift logic against the user's real seeded database and compares it with
/// what the Python notebook printed for the same data (Day 3 table, recommendation counts,
/// calorie output, body-measurement gaps). Skipped when the seed database has not been built.
final class RealDataParityTests: XCTestCase {
    private var db: Database!
    private var workDirectory: URL!

    override func setUpWithError() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let seed = root.appendingPathComponent("output/fitness.seed.sqlite")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: seed.path), "output/fitness.seed.sqlite not built")

        // Import and open exactly like the app does, so an older seed file is upgraded on the way in.
        workDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let live = workDirectory.appendingPathComponent("live")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        let files = DatabaseFileService(location: AppDatabaseLocation(directory: live))
        try files.importDatabase(from: seed, clock: FixedClock(date("2026-10-25")))
        db = try XCTUnwrap(try files.openLiveDatabase())
    }

    override func tearDownWithError() throws {
        db = nil
        if let workDirectory { try? FileManager.default.removeItem(at: workDirectory) }
    }

    private var service: WorkoutService { WorkoutService(db, clock: FixedClock(date("2026-10-25"))) }

    func testDay3MatchesTheNotebookTable() throws {
        let day3 = try XCTUnwrap(service.days().first { $0.position == 3 })
        let workout = try service.workout(dayId: day3.id)

        let expectedWeights: [String: Double] = [
            "Triceps Press": 45, "Triceps Pushdown": 45, "DB Overhead Triceps": 35, "Lat Pulldown": 36,
            "Vertical Pulldown - Black Machine": 60, "Power Row machine - Orange": 25, "T bar row - panatta machine": 15,
            "Chest Dips Machine": 54, "Reverse Lat Pulldown": 36, "Preacher Curls": 25, "Champagne Press": 30,
            "Guillotine press - incline black chest machine": 60, "Chest Fly Machine": 59,
            "Belt machine Stiff Leg Deadlift": 100, "Seated rows mid back": 40, "DB Hammer Curls": 12.5,
        ]
        XCTAssertEqual(workout.exercises.count, expectedWeights.count)
        for exercise in workout.exercises {
            XCTAssertEqual(exercise.workingWeight, expectedWeights[exercise.name], "working weight of \(exercise.name)")
        }

        let increaseWeight = Set(workout.exercises.filter { $0.recommendation == .increaseWeight }.map(\.name))
        XCTAssertEqual(increaseWeight, ["Triceps Pushdown", "Reverse Lat Pulldown"])
        XCTAssertTrue(workout.exercises.filter { !increaseWeight.contains($0.name) }.allSatisfy { $0.recommendation == .increaseReps })
    }

    func testChestDipsShowsTheCurrentInstructionNotTheStaleOne() throws {
        let day3 = try XCTUnwrap(service.days().first { $0.position == 3 })
        let dips = try XCTUnwrap(service.workout(dayId: day3.id).exercises.first { $0.name == "Chest Dips Machine" })
        XCTAssertTrue(dips.instructions?.hasPrefix("handle inner") == true)
        XCTAssertEqual(dips.warmup75, 40.5)
        XCTAssertEqual(dips.warmup90, 48.6)
    }

    func testRecommendationCountsAcrossAllDaysMatchTheNotebook() throws {
        let all = try service.days().flatMap { try service.workout(dayId: $0.id).exercises }
        XCTAssertEqual(all.count, 49)
        XCTAssertEqual(all.filter { $0.recommendation == .increaseReps }.count, 44)
        XCTAssertEqual(all.filter { $0.recommendation == .increaseWeight }.count, 5)
        XCTAssertTrue(all.allSatisfy { $0.recommendation != .noHistory })
    }

    func testCalorieOutputMatchesTheNotebook() throws {
        let advice = try CalorieService(db).advice(caloriesEaten: 2948.5, multiplier: 1)
        XCTAssertEqual(advice.averages.currentAverageKg, 63.86, accuracy: 0.005)
        XCTAssertEqual(advice.averages.pastAverageKg, 63.94, accuracy: 0.005)
        XCTAssertEqual(advice.target.maintenanceCalories, 3027.17, accuracy: 0.05)
        XCTAssertEqual(advice.target.phase, .cut)
        XCTAssertEqual(abs(advice.target.dailyDeficitOrSurplus), 78.67, accuracy: 0.05)
        XCTAssertEqual(advice.target.adjustedTarget, 3027)
    }

    func testMeasurementGapsMatchTheNotebookAndShrinkGoalsAreDirectionAware() throws {
        let progress = try MeasurementService(db).progress()
        XCTAssertEqual(progress.count, 14)

        let calf = try XCTUnwrap(progress.first { $0.site == "Left Calf" })
        XCTAssertEqual(calf.current, 14.0)
        XCTAssertEqual(calf.target, 15.31)
        guard case .toGain(let gain) = calf.status else { return XCTFail("Left Calf should be a gain goal") }
        XCTAssertEqual(gain, 1.31, accuracy: 0.005)

        let waist = try XCTUnwrap(progress.first { $0.site == "Waist" })
        guard case .toLose(let loss) = waist.status else { return XCTFail("Waist should be a lose goal") }
        XCTAssertEqual(loss, 2.2, accuracy: 0.005)

        let neck = try XCTUnwrap(progress.first { $0.site == "Neck" })
        XCTAssertEqual(neck.status, .atTarget)
    }

    func testVolumeMusclesComeFromTheLibraryNotTheOldLogLabels() throws {
        let muscles = try MuscleVolumeService(db).muscles()
        XCTAssertTrue(muscles.contains("Chest"))
        XCTAssertTrue(muscles.contains("Back"))
        XCTAssertFalse(muscles.contains("Legs"), "old Master Sheet label must not leak in")
        XCTAssertFalse(muscles.contains("HIIT"))
    }

    func testAllHistoryWasImported() throws {
        let count = try db.query("SELECT COUNT(*) AS n FROM set_logs").first?.int("n")
        XCTAssertEqual(count, 7141)
    }
}
