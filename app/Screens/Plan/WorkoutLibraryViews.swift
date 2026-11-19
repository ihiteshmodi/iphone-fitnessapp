import FitnessCore
import SwiftUI

/// Words shared by the saved-workout and routine screens.
@MainActor
enum WorkoutLibraryText {
    static func entry(_ entry: RoutineEntry, services: Services) -> String {
        let name = (try? services.library.exercise(id: entry.exerciseID))??.name ?? "Exercise"
        let reps = entry.minReps == entry.maxReps ? "\(entry.minReps)" : "\(entry.minReps)-\(entry.maxReps)"
        return "\(name) · \(entry.sets) × \(reps)"
    }

    static func day(_ day: SavedWorkoutDayDraft, index: Int) -> String {
        let weekday = PlanViewModel.weekdayShortName(day.weekday).map { "\($0) · " } ?? ""
        return "\(weekday)\(day.title ?? "Day \(index + 1)") · \(day.entries.count) exercises"
    }
}

/// A name typed into an alert, for saving or renaming.
private struct NamePrompt: Identifiable {
    let id = UUID()
    let title: String
    var text: String
    let action: (String) -> Void
}

// MARK: Saved workouts

struct SavedWorkoutsView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var workouts: [SavedWorkout] = []
    @State private var prompt: NamePrompt?
    @State private var switching: SavedWorkout?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep each workout plan under a name and switch back any time. Logged sets belong to exercises, so history and working weights carry over.")
                    .font(.system(size: 13)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Save the current workout") {
                    prompt = NamePrompt(title: "Name this workout", text: "") { name in
                        run { try services.savedWorkouts.saveCurrent(as: name, on: services.clock.today()) }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("save-current-workout")
                ForEach(workouts) { workout in row(workout) }
                if workouts.isEmpty { Text("No saved workouts yet.").font(.system(size: 13)).foregroundColor(Theme.muted).card() }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Saved workouts")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) { load() }
        .errorAlert($errorMessage)
        .namePrompt($prompt)
        .confirmationDialog(switching.map { "Switch to \($0.name)?" } ?? "", isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }),
                            titleVisibility: .visible, presenting: switching) { workout in
            Button("Switch plan to \(workout.name)") { run { try services.savedWorkouts.use(workout.id) } }
        } message: { _ in
            Text("The workout plan is replaced from today. Save the current one first if you may want it back. Logged sets are kept.")
        }
    }

    private func row(_ workout: SavedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(workout.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                if workout.isCurrent { Pill(text: "Current", tone: .green) } else if workout.isPreset { Pill(text: "Preset", tone: .grey) }
            }
            ForEach(Array(workout.days.enumerated()), id: \.offset) { index, day in
                Text(WorkoutLibraryText.day(day, index: index)).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            HStack(spacing: 8) {
                if !workout.isCurrent {
                    Button("Use") { switching = workout }.accessibilityIdentifier("use-workout-\(workout.name)")
                }
                Button("Copy") {
                    prompt = NamePrompt(title: "Name the copy", text: "\(workout.name) copy") { name in
                        run { try services.savedWorkouts.copy(workout.id, as: name, on: services.clock.today()) }
                    }
                }
                if !workout.isPreset {
                    Button("Rename") {
                        prompt = NamePrompt(title: "Rename workout", text: workout.name) { name in
                            run { try services.savedWorkouts.rename(workout.id, to: name) }
                        }
                    }
                    Button("Delete", role: .destructive) { run { try services.savedWorkouts.delete(workout.id) } }
                }
            }
            .buttonStyle(PrimaryButtonStyle(ghost: true))
            .font(.system(size: 13))
        }
        .card(highlighted: workout.isCurrent)
    }

    private func load() {
        do { workouts = try services.savedWorkouts.all() } catch { errorMessage = error.localizedDescription }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            session.didChange()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: Routines

struct RoutinesView: View {
    /// When set, tapping a routine adds it to this day.
    var addingTo: PlanDay? = nil
    var onAdded: (() -> Void)? = nil

    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var routines: [Routine] = []
    @State private var muscles: [String] = []
    @State private var muscle: String?
    @State private var prompt: NamePrompt?
    @State private var message: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(addingTo.map { "Tap a routine to add its exercises to \($0.label). Exercises already there are skipped." }
                     ?? "Ready groups of exercises to pull into a workout day. Make your own from a day in Edit plan (Save day as routine).")
                    .font(.system(size: 13)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        chip("All", selected: muscle == nil) { muscle = nil; load() }
                        ForEach(muscles, id: \.self) { name in chip(name, selected: muscle == name) { muscle = name; load() } }
                    }
                }
                ForEach(routines) { routine in row(routine) }
                if routines.isEmpty { Text("No routines here yet.").font(.system(size: 13)).foregroundColor(Theme.muted).card() }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(addingTo == nil ? "Routines" : "Add a routine")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) { load() }
        .errorAlert($errorMessage)
        .namePrompt($prompt)
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) { if addingTo != nil { onAdded?() } }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(selected ? Theme.onGreen : Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(selected ? Theme.green : Theme.card)
            .clipShape(Capsule())
            .accessibilityIdentifier("routine-muscle-\(title)")
    }

    private func row(_ routine: Routine) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(routine.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                if routine.isPreset { Pill(text: "Preset", tone: .grey) }
            }
            ForEach(Array(routine.entries.enumerated()), id: \.offset) { _, entry in
                Text(WorkoutLibraryText.entry(entry, services: services)).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            HStack(spacing: 8) {
                if let day = addingTo {
                    Button("Add to \(day.label)") { add(routine, to: day) }
                        .accessibilityIdentifier("add-routine-\(routine.name)")
                }
                Button("Copy") {
                    prompt = NamePrompt(title: "Name the copy", text: "\(routine.name) copy") { name in
                        run { try services.routines.copy(routine.id, as: name) }
                    }
                }
                if !routine.isPreset {
                    Button("Rename") {
                        prompt = NamePrompt(title: "Rename routine", text: routine.name) { name in
                            run { try services.routines.rename(routine.id, to: name) }
                        }
                    }
                    Button("Delete", role: .destructive) { run { try services.routines.delete(routine.id) } }
                }
            }
            .buttonStyle(PrimaryButtonStyle(ghost: true))
            .font(.system(size: 13))
        }
        .card()
    }

    private func add(_ routine: Routine, to day: PlanDay) {
        do {
            let skipped = try services.routines.add(routine.id, toDay: day.id)
            session.didChange()
            message = skipped.isEmpty ? "Added \(routine.name) to \(day.label)." : "Added to \(day.label). Already there, so skipped: \(skipped.joined(separator: ", "))."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() {
        do {
            routines = try services.routines.all(muscle: muscle)
            muscles = try services.library.muscles()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func run(_ action: () throws -> Void) {
        do {
            try action()
            session.didChange()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension View {
    func namePrompt(_ prompt: Binding<NamePrompt?>) -> some View {
        alert(prompt.wrappedValue?.title ?? "", isPresented: Binding(get: { prompt.wrappedValue != nil }, set: { if !$0 { prompt.wrappedValue = nil } })) {
            TextField("Name", text: Binding(get: { prompt.wrappedValue?.text ?? "" }, set: { prompt.wrappedValue?.text = $0 }))
                .accessibilityIdentifier("library-name-field")
            Button("Save") {
                if let current = prompt.wrappedValue { current.action(current.text) }
                prompt.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { prompt.wrappedValue = nil }
        }
    }
}

/// Loads the coach presets bundled with the app (made by tools/meridian-presets), once.
struct CoachPresetsCard: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var status: String?

    static var bundledFile: URL? { Bundle.main.url(forResource: "meridian-presets", withExtension: "json") }

    var body: some View {
        if let url = Self.bundledFile {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Coach presets")
                Text("Meridian coach routines and workouts, read-only. Use them as they are or copy and change them.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Load coach presets") { load(url) }
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .accessibilityIdentifier("load-coach-presets")
                if let status { Text(status).font(.system(size: 12)).foregroundColor(Theme.green) }
            }
            .card()
        }
    }

    private func load(_ url: URL) {
        do {
            let result = try PresetImporter(services.db).load(try Data(contentsOf: url))
            status = result.routines + result.workouts == 0 ? "Already loaded." : "Added \(result.routines) routines and \(result.workouts) workouts."
            session.didChange()
        } catch {
            status = error.localizedDescription
        }
    }
}


/// Applies the nutrient values the owner approved, bundled as output/nutrient-values.csv (personal data, never committed).
struct NutrientDataCard: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var status: String?

    static var bundledFile: URL? { Bundle.main.url(forResource: "nutrient-values", withExtension: "csv") }

    var body: some View {
        if let url = Self.bundledFile {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Nutrient data")
                Text("Amino acids, fat types, omega, vitamins and minerals for your foods, as approved. Applying again only overwrites those values.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Apply nutrient data") { apply(url) }
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .accessibilityIdentifier("apply-nutrient-data")
                if let status { Text(status).font(.system(size: 12)).foregroundColor(Theme.green) }
            }
            .card()
        }
    }

    private func apply(_ url: URL) {
        do {
            let result = try NutrientImporter(services.db).apply(try String(contentsOf: url, encoding: .utf8))
            let missing = result.missingFoods.isEmpty ? "" : " Not found: \(result.missingFoods.joined(separator: ", "))."
            status = "Applied \(result.applied) values.\(missing)"
            session.didChange()
        } catch {
            status = error.localizedDescription
        }
    }
}
