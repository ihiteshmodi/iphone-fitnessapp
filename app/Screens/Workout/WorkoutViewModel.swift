import FitnessCore
import Foundation

/// Loads the day picker and the selected day's workout; the views only render what is published here.
@MainActor
final class WorkoutViewModel: ObservableObject {
    @Published private(set) var days: [PlanDay] = []
    @Published private(set) var selectedDayId: Int?
    @Published private(set) var workout: Workout?
    @Published var errorMessage: String?
    /// Kept only while the app is open: a fresh launch always starts on All.
    @Published var filter: WorkoutFilter = .all

    private let services: Services

    init(services: Services) {
        self.services = services
    }

    /// Falls back to the first day when the remembered one no longer exists.
    func reload(preferredDayId: Int) {
        do {
            days = try services.workout.days()
            let resolved = days.first(where: { $0.id == preferredDayId }) ?? days.first
            selectedDayId = resolved?.id
            workout = try resolved.map { try services.workout.workout(dayId: $0.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns the new day's id so the screen can select it.
    func addDay() -> Int? {
        do {
            return try services.planEditor.addDay()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: Header

    private static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "Sunday, 25 Oct"
    var dateCaption: String {
        let today = services.clock.today()
        return "\(Self.weekdayNames[today.weekday - 1]), \(Format.shortDate(today))"
    }

    // MARK: Hero

    var exercises: [WorkoutExercise] { workout?.exercises ?? [] }
    var visibleExercises: [WorkoutExercise] { workout?.exercises(filter) ?? [] }
    var remainingCount: Int { workout?.remainingCount ?? 0 }
    var isAllDone: Bool { workout?.isAllDone ?? false }
    var isDeload: Bool { workout?.isDeload ?? false }
    var dayLabel: String { workout?.day.label ?? "" }

    var hasTitle: Bool { !(workout?.day.title ?? "").isEmpty }

    var heroTitle: String {
        guard let day = workout?.day else { return "" }
        if let title = day.title, !title.isEmpty { return title }
        return day.label
    }

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }

    var exercisesDone: Int { exercises.filter(\.isDone).count }

    var toProgressCount: Int {
        exercises.filter { $0.recommendation == .increaseWeight || $0.recommendation == .increaseReps }.count
    }

    /// Exercises whose last session was a PR to act on.
    var prCount: Int {
        exercises.filter { if case .pr(_, _, _, _, let isToday) = $0.progression { return !isToday }; return false }.count
    }

    /// Counts partial exercises too, so the ring moves after every logged set.
    var ringProgress: Double {
        guard totalSets > 0 else { return 0 }
        let logged = exercises.reduce(0) { $0 + min($1.setsLoggedToday, $1.sets) }
        return Double(logged) / Double(totalSets)
    }

    var ringLabel: String { "\(exercisesDone)/\(exercises.count)" }

    // MARK: Cards

    func meta(_ exercise: WorkoutExercise) -> String {
        let reps = "\(Format.number(exercise.minReps))–\(Format.number(exercise.maxReps))"
        let target = "\(exercise.sets) × \(reps)"
        guard let muscle = exercise.muscle, !muscle.isEmpty else { return target }
        return "\(muscle) · \(target)"
    }

    func ringProgress(_ exercise: WorkoutExercise) -> Double {
        exercise.sets > 0 ? Double(exercise.setsLoggedToday) / Double(exercise.sets) : 0
    }

    func ringLabel(_ exercise: WorkoutExercise) -> String { "\(exercise.setsLoggedToday)/\(exercise.sets)" }

    struct Badge: Equatable {
        enum Tone { case green, amber, grey, gold }
        let text: String
        let tone: Tone
    }

    func badge(_ exercise: WorkoutExercise) -> Badge {
        if isDeload { return Badge(text: "Deload", tone: .amber) }
        switch exercise.progression {
        case .pr(let next, _, _, _, _): return Badge(text: "★ Go to \(Format.number(next))", tone: .gold)
        case .repeatForCleanReps: return Badge(text: "Same weight, clean", tone: .amber)
        case .none: break
        }
        switch exercise.recommendation {
        case .increaseWeight: return Badge(text: "Increase weight", tone: .green)
        case .increaseReps: return Badge(text: "Increase reps", tone: .green)
        case .bringToMaintenance: return Badge(text: "Maintenance", tone: .amber)
        case .noHistory, .none: return Badge(text: "No history", tone: .grey)
        }
    }
}
