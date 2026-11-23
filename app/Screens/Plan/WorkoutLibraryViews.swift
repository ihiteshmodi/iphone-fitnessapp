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
    @State private var previewing: SavedWorkoutDetail?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep each workout plan under a name, tap any workout to preview its days and exercises, and switch back any time. Logged sets belong to exercises, so history and working weights carry over.")
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
        .sheet(isPresented: Binding(get: { previewing != nil }, set: { if !$0 { previewing = nil } })) {
            if let detail = previewing {
                SavedWorkoutDetailSheet(detail: detail) {
                    previewing = nil
                    switching = detail.workout
                }
            }
        }
        .confirmationDialog(switching.map { "Switch to \($0.name)?" } ?? "", isPresented: Binding(get: { switching != nil }, set: { if !$0 { switching = nil } }),
                            titleVisibility: .visible, presenting: switching) { workout in
            Button("Switch plan to \(workout.name)") { run { try services.savedWorkouts.use(workout.id) } }
        } message: { _ in
            Text("The workout plan is replaced from today. Save the current one first if you may want it back. Logged sets are kept.")
        }
    }

    private func openPreview(_ workout: SavedWorkout) {
        do {
            previewing = try services.savedWorkouts.detail(of: workout.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func row(_ workout: SavedWorkout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { openPreview(workout) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(workout.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                        Spacer()
                        if workout.isCurrent { Pill(text: "Current", tone: .green) } else if workout.isPreset { Pill(text: "Preset", tone: .grey) }
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.muted)
                    }
                    ForEach(Array(workout.days.enumerated()), id: \.offset) { index, day in
                        Text(WorkoutLibraryText.day(day, index: index)).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("preview-workout-\(workout.name)")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Preview") { openPreview(workout) }
                    if !workout.isCurrent {
                        Button("Use") { switching = workout }.accessibilityIdentifier("use-workout-\(workout.name)")
                    }
                    Button("Duplicate") {
                        prompt = NamePrompt(title: "Duplicate workout", text: "\(workout.name) copy") { name in
                            run { try services.savedWorkouts.copy(workout.id, as: name, on: services.clock.today()) }
                        }
                    }
                    .accessibilityIdentifier("duplicate-workout-\(workout.name)")
                    Button("Rename") {
                        prompt = NamePrompt(title: "Rename workout", text: workout.name) { name in
                            run { try services.savedWorkouts.rename(workout.id, to: name) }
                        }
                    }
                    .accessibilityIdentifier("rename-workout-\(workout.name)")
                    Button("Delete", role: .destructive) { run { try services.savedWorkouts.delete(workout.id) } }
                        .accessibilityIdentifier("delete-workout-\(workout.name)")
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .font(.system(size: 13))
            }
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
    @State private var editingRoutine: RoutineEditorTarget?
    @State private var message: String?
    @State private var errorMessage: String?

    private enum RoutineEditorTarget: Identifiable {
        case create
        case edit(Routine)
        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let r): return "edit-\(r.id)"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(addingTo.map { "Tap a routine to add its exercises to \($0.label). Exercises already there are skipped." }
                     ?? "Ready groups of exercises to pull into a workout day. Create your own here, or save a day in Edit plan.")
                    .font(.system(size: 13)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("+ New routine") { editingRoutine = .create }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("create-routine-button")
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
        .sheet(item: $editingRoutine) { target in
            switch target {
            case .create:
                RoutineEditorSheet(routine: nil) {
                    editingRoutine = nil
                    session.didChange()
                    load()
                }
            case .edit(let routine):
                RoutineEditorSheet(routine: routine) {
                    editingRoutine = nil
                    session.didChange()
                    load()
                }
            }
        }
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let day = addingTo {
                        Button("Add to \(day.label)") { add(routine, to: day) }
                            .accessibilityIdentifier("add-routine-\(routine.name)")
                    }
                    Button("Edit") { editingRoutine = .edit(routine) }
                        .accessibilityIdentifier("edit-routine-\(routine.name)")
                    Button("Duplicate") {
                        prompt = NamePrompt(title: "Duplicate routine", text: "\(routine.name) copy") { name in
                            run { try services.routines.copy(routine.id, as: name) }
                        }
                    }
                    .accessibilityIdentifier("duplicate-routine-\(routine.name)")
                    Button("Rename") {
                        prompt = NamePrompt(title: "Rename routine", text: routine.name) { name in
                            run { try services.routines.rename(routine.id, to: name) }
                        }
                    }
                    .accessibilityIdentifier("rename-routine-\(routine.name)")
                    Button("Delete", role: .destructive) { run { try services.routines.delete(routine.id) } }
                        .accessibilityIdentifier("delete-routine-\(routine.name)")
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .font(.system(size: 13))
            }
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
            muscles = try services.routines.filterMuscles()
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

// MARK: Saved workout preview

private struct SavedWorkoutDetailSheet: View {
    let detail: SavedWorkoutDetail
    let onUse: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(detail.days.count) days · \(detail.workout.exerciseCount) exercises")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.muted)
                        Spacer()
                        if detail.workout.isCurrent { Pill(text: "Current", tone: .green) }
                        else if detail.workout.isPreset { Pill(text: "Preset", tone: .grey) }
                    }
                    ForEach(detail.days) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(day.title).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                                Spacer()
                                if let weekday = PlanViewModel.weekdayShortName(day.weekday) {
                                    Pill(text: weekday, tone: .grey)
                                }
                            }
                            if !day.muscleSummary.isEmpty {
                                Text(day.muscleSummary).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.greenSoft)
                            }
                            Divider().overlay(Theme.line)
                            ForEach(day.exercises) { ex in
                                let reps = ex.minReps == ex.maxReps ? "\(ex.minReps)" : "\(ex.minReps)–\(ex.maxReps)"
                                let warmups = ex.warmupSets > 0 ? " · \(ex.warmupSets) warm-up" : ""
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name).font(.system(size: 14, weight: .medium)).foregroundColor(Theme.text)
                                        if !ex.primaryMuscles.isEmpty {
                                            Text(ex.primaryMuscles.joined(separator: ", "))
                                                .font(.system(size: 11)).foregroundColor(Theme.muted)
                                        }
                                    }
                                    Spacer()
                                    Text("\(ex.sets) × \(reps)\(warmups)")
                                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .card()
                    }
                    if !detail.workout.isCurrent {
                        Button("Use \(detail.workout.name)", action: onUse)
                            .buttonStyle(PrimaryButtonStyle())
                            .accessibilityIdentifier("preview-use-workout")
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(detail.workout.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("workout-preview-done") }
            }
        }
    }
}

// MARK: Create & edit routine

private struct RoutineDraftItem: Identifiable, Equatable {
    let id = UUID()
    let exerciseID: Int
    let name: String
    var scheme: PlanRepScheme
}

private struct RoutineEditorSheet: View {
    let routine: Routine?
    let onSaved: () -> Void

    @EnvironmentObject private var services: Services
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var items: [RoutineDraftItem] = []
    @State private var pickingExercise = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BodyField(label: "Routine name", text: $name, identifier: "routine-editor-name-field", keyboard: .default)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionLabel("Exercises (\(items.count))")
                            Spacer()
                            Button("+ Add exercise") { pickingExercise = true }
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.green)
                                .accessibilityIdentifier("routine-editor-add-exercise")
                        }
                        if items.isEmpty {
                            Text("No exercises added yet. Tap + Add exercise to build this routine.")
                                .font(.system(size: 13)).foregroundColor(Theme.muted)
                                .padding(.vertical, 6)
                        }
                        ForEach($items) { $item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.name).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                                    Spacer()
                                    Button(role: .destructive) {
                                        items.removeAll { $0.id == item.id }
                                    } label: {
                                        Image(systemName: "trash").font(.system(size: 13)).foregroundColor(Theme.red)
                                    }
                                    .buttonStyle(.plain)
                                }
                                PlanRepSchemeEditor(scheme: $item.scheme)
                            }
                            .padding(10)
                            .background(Theme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .card()
                    Button(routine == nil ? "Create routine" : "Save routine", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("routine-editor-save")
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).foregroundColor(Theme.green)
                        .accessibilityIdentifier("routine-editor-top-save")
                }
            }
            .onAppear(perform: loadExisting)
            .sheet(isPresented: $pickingExercise) {
                RoutineExercisePickerSheet { exercise, scheme in
                    if !items.contains(where: { $0.exerciseID == exercise.id }) {
                        items.append(RoutineDraftItem(exerciseID: exercise.id, name: exercise.name, scheme: scheme))
                    }
                    pickingExercise = false
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func loadExisting() {
        guard let routine, items.isEmpty, name.isEmpty else { return }
        name = routine.name
        items = routine.entries.map { entry in
            let exName = (try? services.library.exercise(id: entry.exerciseID))?.name ?? "Exercise"
            return RoutineDraftItem(
                exerciseID: entry.exerciseID,
                name: exName,
                scheme: PlanRepScheme(sets: entry.sets, warmupSets: entry.warmupSets, minReps: entry.minReps, maxReps: entry.maxReps))
        }
    }

    private func save() {
        let entries = items.map {
            RoutineEntry(exerciseID: $0.exerciseID, sets: $0.scheme.sets, minReps: $0.scheme.minReps,
                         maxReps: $0.scheme.maxReps, warmupSets: $0.scheme.warmupSets)
        }
        do {
            if let routine {
                if name.trimmingCharacters(in: .whitespaces) != routine.name {
                    try services.routines.rename(routine.id, to: name)
                }
                try services.routines.setEntries(routine.id, entries)
            } else {
                _ = try services.routines.create(name, entries: entries)
            }
            onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RoutineExercisePickerSheet: View {
    let onPicked: (Exercise, PlanRepScheme) -> Void

    @EnvironmentObject private var services: Services
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = LibraryBrowserModel()
    @State private var selected: Exercise?
    @State private var scheme = PlanRepScheme()

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Add exercise").font(.system(size: 19, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                Button("Cancel") { dismiss() }.foregroundColor(Theme.green)
            }
            LibrarySearchField(text: $browser.searchText, prompt: "Search the exercise library")
            LibraryMuscleChips(muscles: browser.muscles, selection: $browser.selectedMuscle)
            List {
                ForEach(browser.results) { exercise in
                    Button {
                        selected = selected?.id == exercise.id ? nil : exercise
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected?.id == exercise.id ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selected?.id == exercise.id ? Theme.green : Theme.muted)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(exercise.name).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                                Text(LibraryBrowserModel.pickerDetail(of: exercise)).font(.system(size: 12)).foregroundColor(Theme.muted)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(selected?.id == exercise.id ? Theme.green.opacity(0.10) : Theme.card)
                    .listRowSeparatorTint(Theme.line)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel(selected.name)
                    PlanRepSchemeEditor(scheme: $scheme)
                    Button("Add to routine") { onPicked(selected, scheme) }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.top, 6)
                        .accessibilityIdentifier("confirm-routine-exercise")
                }
                .card()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .screenBackground()
        .preferredColorScheme(.dark)
        .task { browser.bind(services) }
    }
}
