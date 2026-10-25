import FitnessCore
import Foundation

enum LibraryFormMode {
    case create
    case edit(Exercise)
    /// Creates the exercise and puts it on the day in one step.
    case createAndAdd(dayId: Int, dayLabel: String)
}

@MainActor
final class LibraryExerciseFormModel: ObservableObject {
    let mode: LibraryFormMode

    @Published var name = ""
    @Published var instructions = ""
    @Published var selectedMuscle: String?
    @Published var isNewMuscle = false
    @Published var newMuscle = ""
    @Published var scheme = PlanRepScheme()
    @Published private(set) var muscles: [String] = []
    @Published var errorMessage: String?

    private var link = MoreServiceLink()

    init(mode: LibraryFormMode) {
        self.mode = mode
        if case .edit(let exercise) = mode {
            name = exercise.name
            instructions = exercise.instructions ?? ""
            selectedMuscle = exercise.muscle
        }
    }

    func bind(_ services: Services, notify: @escaping () -> Void) {
        link.bind(services, notify: notify)
        muscles = (try? services.library.muscles()) ?? []
    }

    var title: String {
        if case .edit = mode { return "Edit exercise" }
        return "New exercise"
    }

    var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var addToDayLabel: String? {
        if case .createAndAdd(_, let label) = mode { return label }
        return nil
    }

    var saveButtonTitle: String {
        if let label = addToDayLabel { return "Save and add to \(label)" }
        return "Save exercise"
    }

    func chooseMuscle(_ muscle: String) {
        isNewMuscle = false
        selectedMuscle = selectedMuscle == muscle ? nil : muscle
    }

    func chooseNewMuscle() {
        isNewMuscle.toggle()
        if isNewMuscle { selectedMuscle = nil }
    }

    /// A typed muscle that matches an existing one ignoring case reuses it, so charts do not split "Chest" and "chest".
    private var resolvedMuscle: String? {
        guard isNewMuscle else { return selectedMuscle }
        let typed = newMuscle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return nil }
        return muscles.first { $0.caseInsensitiveCompare(typed) == .orderedSame } ?? typed
    }

    /// Returns true when saved, so the view can dismiss.
    func save() -> Bool {
        guard let services = link.services else { return false }
        do {
            switch mode {
            case .create:
                try services.library.add(name: name, muscle: resolvedMuscle, instructions: instructions)
            case .edit(let exercise):
                try services.library.update(id: exercise.id, name: name, muscle: resolvedMuscle, instructions: instructions)
            case .createAndAdd(let dayId, _):
                try services.planEditor.createExerciseAndAdd(dayId: dayId, name: name, muscle: resolvedMuscle, instructions: instructions,
                                                             sets: scheme.sets, minReps: scheme.minReps, maxReps: scheme.maxReps)
            }
            link.didChange()
            return true
        } catch {
            errorMessage = MoreErrorText.message(for: error)
            return false
        }
    }

    func delete() -> Bool {
        guard case .edit(let exercise) = mode, let services = link.services else { return false }
        do {
            try services.library.delete(id: exercise.id)
            link.didChange()
            return true
        } catch {
            errorMessage = MoreErrorText.message(for: error)
            return false
        }
    }
}
