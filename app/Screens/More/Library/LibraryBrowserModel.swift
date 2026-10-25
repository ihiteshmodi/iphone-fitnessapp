import FitnessCore
import Foundation

/// Search text, muscle filter and results shared by the Library and the Add exercise sheet.
@MainActor
final class LibraryBrowserModel: ObservableObject {
    @Published var searchText = "" { didSet { reload() } }
    @Published var selectedMuscle: String? = nil { didSet { reload() } }
    @Published private(set) var muscles: [String] = []
    @Published private(set) var results: [Exercise] = []
    @Published private(set) var totalCount = 0
    @Published var errorMessage: String?

    private var link = MoreServiceLink()

    func bind(_ services: Services) {
        link.bind(services) {}
        reload()
    }

    func reload() {
        guard let services = link.services else { return }
        do {
            muscles = try services.library.muscles()
            results = try services.library.search(searchText, muscle: selectedMuscle)
            totalCount = try services.library.all().count
        } catch {
            errorMessage = MoreErrorText.message(for: error)
        }
    }

    /// Picker wording: "Chest · has how-to".
    static func pickerDetail(of exercise: Exercise) -> String {
        let howTo = hasHowTo(exercise) ? "has how-to" : "no how-to yet"
        return [exercise.muscle, howTo].compactMap { $0 }.joined(separator: " · ")
    }

    /// Library wording: "Chest · how-to added".
    static func libraryDetail(of exercise: Exercise) -> String {
        let howTo = hasHowTo(exercise) ? "how-to added" : "no how-to"
        return [exercise.muscle, howTo].compactMap { $0 }.joined(separator: " · ")
    }

    private static func hasHowTo(_ exercise: Exercise) -> Bool {
        exercise.instructions?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
