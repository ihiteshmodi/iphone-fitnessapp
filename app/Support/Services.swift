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
    let foods: FoodLibrary
    let dietPlans: DietPlanService
    let dietDays: DietDayService
    let dietRules: DietSettings
    let breaks: BreakModeService
    let savedDiets: SavedDietService
    let savedWorkouts: SavedWorkoutService
    let routines: RoutineService
    let insights: InsightService
    let checkIn: CheckInService
    let refeeds: RefeedService

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
        foods = FoodLibrary(db)
        dietPlans = DietPlanService(db)
        dietDays = DietDayService(db)
        dietRules = DietSettings(db)
        breaks = BreakModeService(db)
        savedDiets = SavedDietService(db)
        savedWorkouts = SavedWorkoutService(db)
        routines = RoutineService(db)
        insights = InsightService(db, daily: NutritionRules.daily + CheckInRules.daily + TrainingRules.daily,
                                  setup: NutritionRules.setup + TrainingRules.setup + RefeedRules.setup)
        checkIn = CheckInService(db)
        refeeds = RefeedService(db)
    }
}
