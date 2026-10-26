import Foundation

/// Day picker and day workouts. Read-only: it never writes to the database.
public final class WorkoutService {
    private let db: Database
    private let clock: AppClock

    public init(_ db: Database, clock: AppClock) {
        self.db = db
        self.clock = clock
    }

    public func days() throws -> [PlanDay] {
        let mode = try SettingsRepository(db).load().dayLabelMode
        return try PlanReader(db: db).days().map { Self.planDay($0, mode: mode) }
    }

    public func workout(dayId: Int) throws -> Workout {
        let settings = try SettingsRepository(db).load()
        let plan = PlanReader(db: db)
        guard let dayRow = try plan.day(id: dayId) else { throw ValidationError("Day not found") }

        let history = SetHistoryReader(db: db)
        let today = clock.today()
        let exercises = try plan.entries(dayId: dayId).map { entry -> WorkoutExercise in
            let sets = ProgressSets.filter(try history.sets(exerciseId: entry.exercise.id, since: settings.historyStartDate),
                                           ignoreDeload: settings.ignoreDeloadSessions)
            let target = WorkoutTargetCalculator.target(heaviest: HeaviestSet.of(sets), minReps: entry.minReps,
                                                        maxReps: entry.maxReps, deload: settings.deload)
            let sparkline = SessionHistory.sessions(from: sets).suffix(Self.sparklineSessions).map(\.best.weightKg)
            return WorkoutExercise(
                planEntryId: entry.planEntryId, exerciseId: entry.exercise.id, name: entry.exercise.name,
                muscle: entry.exercise.muscle, instructions: entry.exercise.instructions,
                sets: entry.sets, minReps: target.minReps, plannedMinReps: entry.minReps, maxReps: target.maxReps,
                plannedMaxReps: entry.maxReps,
                workingWeight: target.workingWeight, warmup75: target.warmup75, warmup90: target.warmup90,
                recommendation: target.recommendation, repsAtMax: target.repsAtMax, dateOfMax: target.dateOfMax,
                setsLoggedToday: try history.sets(exerciseId: entry.exercise.id, on: today).count,
                sparkline: Array(sparkline))
        }
        return Workout(day: Self.planDay(dayRow, mode: settings.dayLabelMode), isDeload: settings.deload.enabled, exercises: exercises)
    }

    static let sparklineSessions = 6

    private static func planDay(_ row: PlanDayRow, mode: DayLabelMode) -> PlanDay {
        PlanDay(id: row.id, position: row.position,
                label: DayLabel.make(position: row.position, weekday: row.weekday, mode: mode),
                title: row.title, weekday: row.weekday, exerciseCount: row.exerciseCount)
    }
}
