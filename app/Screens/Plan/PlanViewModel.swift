import FitnessCore
import Foundation

/// A planned exercise as the editor shows it: stored sets and rep range, never the deload-scaled targets.
struct PlanEntry: Identifiable, Equatable {
    let id: Int
    let dayId: Int
    let name: String
    var scheme: PlanRepScheme
}

/// Loads the plan and applies edits. Views only call these methods.
@MainActor
final class PlanViewModel: ObservableObject {
    static let weekdayShortNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let weekdayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    @Published private(set) var days: [PlanDay] = []
    @Published private(set) var entries: [Int: [PlanEntry]] = [:]
    @Published private(set) var labelMode: DayLabelMode = .number
    @Published var expanded: Set<Int> = []
    @Published var errorMessage: String?

    private var link = MoreServiceLink()
    private var focusApplied = false

    func bind(_ services: Services, focusDayId: Int?, notify: @escaping () -> Void) {
        link.bind(services, notify: notify)
        if !focusApplied, let focusDayId {
            expanded.insert(focusDayId)
        }
        focusApplied = true
        load()
    }

    func load() {
        guard let services = link.services else { return }
        do {
            let settings = try services.settings.load()
            labelMode = settings.dayLabelMode
            days = try services.workout.days()
            expanded.formIntersection(Set(days.map(\.id)))
            var loaded: [Int: [PlanEntry]] = [:]
            for day in days where expanded.contains(day.id) {
                loaded[day.id] = try Self.entries(of: day, services: services)
            }
            entries = loaded
        } catch {
            errorMessage = MoreErrorText.message(for: error)
        }
    }

    /// The plan screen always shows the stored values, even while deload is on.
    private static func entries(of day: PlanDay, services: Services) throws -> [PlanEntry] {
        try services.workout.workout(dayId: day.id).exercises.map { exercise in
            PlanEntry(id: exercise.planEntryId, dayId: day.id, name: exercise.name,
                      scheme: PlanRepScheme(sets: exercise.sets, minReps: exercise.plannedMinReps, maxReps: exercise.maxReps))
        }
    }

    func isExpanded(_ day: PlanDay) -> Bool { expanded.contains(day.id) }

    func toggle(_ day: PlanDay) {
        if expanded.contains(day.id) { expanded.remove(day.id) } else { expanded.insert(day.id) }
        load()
    }

    func subtitle(of day: PlanDay) -> String {
        let count = day.exerciseCount == 1 ? "1 exercise" : "\(day.exerciseCount) exercises"
        guard let title = day.title, !title.isEmpty else { return count }
        return "\(title) · \(count)"
    }

    static func weekdayShortName(_ weekday: Int?) -> String? {
        guard let weekday, (1...7).contains(weekday) else { return nil }
        return weekdayShortNames[weekday - 1]
    }

    // MARK: Actions

    func setLabelMode(_ mode: DayLabelMode) {
        perform { try $0.settings.setDayLabelMode(mode) }
    }

    func addDay() {
        perform { services in
            let id = try services.planEditor.addDay()
            expanded.insert(id)
        }
    }

    func deleteDay(_ day: PlanDay) {
        perform { try $0.planEditor.deleteDay(id: day.id) }
    }

    func setWeekday(_ weekday: Int?, for day: PlanDay) {
        perform { try $0.planEditor.setWeekday(dayId: day.id, weekday: weekday) }
    }

    func setTitle(_ title: String, for day: PlanDay) {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != (day.title ?? "") else { return }
        perform { try $0.planEditor.setTitle(dayId: day.id, title: cleaned) }
    }

    func updateEntry(_ entry: PlanEntry, scheme: PlanRepScheme) {
        perform { try $0.planEditor.updateEntry(entryId: entry.id, sets: scheme.sets, minReps: scheme.minReps, maxReps: scheme.maxReps) }
    }

    func removeEntry(_ entry: PlanEntry) {
        perform { try $0.planEditor.removeEntry(entryId: entry.id) }
    }

    /// `source` and `destination` come from SwiftUI's onMove: destination is an index in the list before the move.
    func moveEntries(in day: PlanDay, from source: IndexSet, to destination: Int) {
        guard var list = entries[day.id], let from = source.first, from < list.count else { return }
        let entry = list[from]
        let finalIndex = destination > from ? destination - 1 : destination
        guard finalIndex != from else { return }
        list.move(fromOffsets: source, toOffset: destination)
        entries[day.id] = list
        perform { try $0.planEditor.moveEntry(entryId: entry.id, toPosition: finalIndex + 1) }
    }

    private func perform(_ work: (Services) throws -> Void) {
        guard let services = link.services else { return }
        do {
            try work(services)
            link.didChange()
        } catch {
            errorMessage = MoreErrorText.message(for: error)
        }
        load()
    }
}
