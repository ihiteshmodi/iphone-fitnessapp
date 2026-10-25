import XCTest
@testable import FitnessCore

/// Scenarios from deload-mode.feature about the "ignore deload sessions" switch.
final class IgnoreDeloadSessionsTests: XCTestCase {
    private var db: Database!
    private var planned: PlannedExercise!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        planned = try PlannedExercise.make(db, name: "Chest Dips Machine", minReps: 6, maxReps: 10)
    }

    private func setIgnore(_ on: Bool) throws { try SettingsRepository(db).setIgnoreDeloadSessions(on) }

    private func detail() throws -> ExerciseDetail {
        try ExerciseDetailService(db, clock: planningClock()).detail(exerciseId: planned.exerciseId, dayId: planned.dayId)
    }

    private func workoutExercise() throws -> WorkoutExercise {
        try XCTUnwrap(try WorkoutService(db, clock: planningClock()).workout(dayId: planned.dayId).exercises.first)
    }

    private func set(_ day: String, _ weight: Double, _ reps: Int, deload: Bool = false) throws {
        try db.addSet(exercise: planned.exerciseId, on: day, weight: weight, reps: reps, deload: deload)
    }

    // MARK: the switch itself

    func testIgnoringDeloadIsOnByDefault() throws {
        XCTAssertTrue(try SettingsRepository(db).load().ignoreDeloadSessions)
    }

    func testTheSwitchRoundTripsAndDoesNotTouchOtherSettings() throws {
        let settings = SettingsRepository(db)
        try settings.setIgnoreDeloadSessions(false)
        let loaded = try settings.load()
        XCTAssertFalse(loaded.ignoreDeloadSessions)
        XCTAssertFalse(loaded.deload.enabled)
        XCTAssertEqual(loaded.deload.repsMultiplier, 0.75)
        XCTAssertEqual(loaded.historyStartDate, date("2026-08-31"))
    }

    // MARK: tagging at log time

    func testSetsLoggedWhileDeloadIsOnAreTaggedAndOthersAreNot() throws {
        let log = LogSets(db)
        let normal = try log.logSet(.existing(id: planned.exerciseId), weightKg: 54, reps: 9, on: planningToday)
        try SettingsRepository(db).setDeloadEnabled(true)
        let deload = try log.logSet(.existing(id: planned.exerciseId), weightKg: 40, reps: 6, on: planningToday)

        let flags = try db.query("SELECT id, is_deload FROM set_logs ORDER BY id").map { ($0.int("id"), $0.int("is_deload")) }
        XCTAssertEqual(flags.map(\.0), [normal, deload])
        XCTAssertEqual(flags.map(\.1), [0, 1])
    }

    // MARK: switch ON: deload sessions are ignored for progress

    func testIgnoredDeloadSessionDoesNotChangeTheTrend() throws {
        try set("2026-09-10", 45, 10)
        try set("2026-09-20", 46.5, 10)
        try set("2026-10-01", 48, 10)
        try set("2026-10-15", 30, 10, deload: true)
        try setIgnore(true)

        let detail = try detail()

        XCTAssertEqual(detail.trend.status, .improving)
        XCTAssertEqual(detail.sessions.map(\.date), [date("2026-09-10"), date("2026-09-20"), date("2026-10-01")])
    }

    func testCountedDeloadSessionShowsUpInTheTrend() throws {
        try set("2026-09-10", 45, 10)
        try set("2026-09-20", 46.5, 10)
        try set("2026-10-01", 48, 10)
        try set("2026-10-15", 30, 10, deload: true)
        try setIgnore(false)

        let detail = try detail()

        XCTAssertEqual(detail.trend.status, .declining)
        XCTAssertEqual(detail.sessions.count, 4)
    }

    func testLastSessionAndAimSkipTheDeloadSessionWhenIgnored() throws {
        try set("2026-10-10", 54, 9)
        try set("2026-10-15", 40, 6, deload: true)
        try setIgnore(true)

        let detail = try detail()

        XCTAssertEqual(detail.lastSession?.date, date("2026-10-10"))
        XCTAssertEqual(detail.target.workingWeight, 54)
        XCTAssertTrue(detail.aim.contains("beat 9"), detail.aim)
    }

    func testLastSessionIsTheDeloadSessionWhenCounted() throws {
        try set("2026-10-10", 54, 9)
        try set("2026-10-15", 40, 6, deload: true)
        try setIgnore(false)

        XCTAssertEqual(try detail().lastSession?.date, date("2026-10-15"))
    }

    func testAnExerciseWithOnlyDeloadSetsHasNoHistoryWhenIgnored() throws {
        try set("2026-10-15", 40, 6, deload: true)
        try setIgnore(true)

        let exercise = try workoutExercise()

        XCTAssertNil(exercise.workingWeight)
        XCTAssertEqual(exercise.recommendation, .noHistory)
        XCTAssertFalse(try detail().hasHistory)
    }

    func testAnExerciseWithOnlyDeloadSetsUsesThemWhenCounted() throws {
        try set("2026-10-15", 40, 6, deload: true)
        try setIgnore(false)

        XCTAssertEqual(try workoutExercise().workingWeight, 40)
    }

    func testSparklineSkipsDeloadSessionsWhenIgnored() throws {
        try set("2026-10-01", 50, 10)
        try set("2026-10-15", 30, 10, deload: true)

        try setIgnore(true)
        XCTAssertEqual(try workoutExercise().sparkline, [50])

        try setIgnore(false)
        XCTAssertEqual(try workoutExercise().sparkline, [50, 30])
    }

    func testVolumeSkipsDeloadSetsWhenIgnored() throws {
        try set("2026-10-01", 45, 10)
        try set("2026-10-15", 30, 10, deload: true)

        try setIgnore(true)
        XCTAssertEqual(try volumeSeries().map(\.volume), [450])

        try setIgnore(false)
        XCTAssertEqual(try volumeSeries().map(\.volume), [450, 300])
    }

    private func volumeSeries() throws -> [VolumePoint] {
        let series = try MuscleVolumeService(db).series(muscle: "Chest")
        return try XCTUnwrap(series.first).points
    }

    // MARK: always visible, whatever the switch says

    func testTodaysDeloadSetsStillShowAndCountOnTheCard() throws {
        try set(planningToday.string, 40, 6, deload: true)
        try setIgnore(true)

        let detail = try detail()

        XCTAssertEqual(detail.todaySets.count, 1)
        XCTAssertTrue(detail.todaySets[0].isDeload)
        XCTAssertEqual(try workoutExercise().setsLoggedToday, 1)
    }

    func testHistoryListKeepsDeloadSessionsMarkedAsDeload() throws {
        try set("2026-10-10", 54, 9)
        try set("2026-10-15", 40, 6, deload: true)
        try setIgnore(true)

        let history = try detail().history

        XCTAssertEqual(history.map(\.date), [date("2026-10-15"), date("2026-10-10")])
        XCTAssertTrue(history[0].sets[0].isDeload)
        XCTAssertFalse(history[1].sets[0].isDeload)
    }
}
