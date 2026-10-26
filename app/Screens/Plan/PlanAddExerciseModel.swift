import FitnessCore
import Foundation

/// State of the Add exercise sheet: which library exercise is picked and its sets and rep range.
@MainActor
final class PlanAddExerciseModel: ObservableObject {
    let day: PlanDay

    @Published var selected: Exercise?
    @Published var scheme = PlanRepScheme()
    @Published var errorMessage: String?

    private var link = MoreServiceLink()

    init(day: PlanDay) { self.day = day }

    func bind(_ services: Services, notify: @escaping () -> Void) {
        link.bind(services, notify: notify)
    }

    func toggle(_ exercise: Exercise) {
        selected = selected?.id == exercise.id ? nil : exercise
    }

    /// Returns true when added, so the sheet can close.
    func add() -> Bool {
        guard let services = link.services, let selected else { return false }
        do {
            try services.planEditor.addExercise(dayId: day.id, exerciseId: selected.id,
                                                sets: scheme.sets, minReps: scheme.minReps, maxReps: scheme.maxReps,
                                                warmupSets: scheme.warmupSets)
            link.didChange()
            return true
        } catch {
            errorMessage = MoreErrorText.message(for: error)
            return false
        }
    }
}
