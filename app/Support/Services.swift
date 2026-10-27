import FitnessCore
import Foundation

/// Every service the screens need, built once per open database (the composition root for the app).
final class Services: ObservableObject {
    let db: Database
    let clock: AppClock
    let workout: WorkoutService
    let detail: ExerciseDetailService
    let planEditor: PlanEditor
    let library: ExerciseRepository
    let logSets: LogSets
    let formChecks: FormChecks
    let logBody: LogBodyMetrics
    let calories: CalorieService
    let nutrition: NutritionSettings
    let measurements: MeasurementService
    let volume: MuscleVolumeService
    let settings: SettingsRepository
    let muscles: ExerciseMuscleService

    init(db: Database, clock: AppClock) {
        self.db = db
        self.clock = clock
        workout = WorkoutService(db, clock: clock)
        detail = ExerciseDetailService(db, clock: clock)
        planEditor = PlanEditor(db)
        library = ExerciseRepository(db)
        logSets = LogSets(db, clock: clock)
        formChecks = FormChecks(db)
        logBody = LogBodyMetrics(db)
        calories = CalorieService(db)
        nutrition = NutritionSettings(db)
        measurements = MeasurementService(db, clock: clock)
        volume = MuscleVolumeService(db)
        settings = SettingsRepository(db)
        muscles = ExerciseMuscleService(db)
    }
}
