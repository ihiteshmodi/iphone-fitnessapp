import FitnessCore
import SwiftUI

/// Edit plan (mockup 6). `focusDayId` opens with that day expanded. The caller provides the NavigationStack.
struct EditPlanView: View {
    var focusDayId: Int? = nil

    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @StateObject private var model = PlanViewModel()
    @State private var entryBeingEdited: PlanEntry?
    @State private var addTarget: PlanDay?
    @State private var dayToDelete: PlanDay?
    @State private var routineTarget: PlanDay?
    @State private var dayToSave: PlanDay?
    @State private var routineName = ""
    @State private var showingSavedWorkouts = false
    @State private var showingRoutines = false
    @State private var showingMuscleTargets = false

    init(focusDayId: Int? = nil) {
        self.focusDayId = focusDayId
    }

    private func libraryRow(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundColor(Theme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    var body: some View {
        List {
            Section {
                Picker("Name days by", selection: Binding(get: { model.labelMode }, set: { model.setLabelMode($0) })) {
                    Text("Name by numbers").tag(DayLabelMode.number)
                    Text("Name by weekdays").tag(DayLabelMode.weekday)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("plan-day-label-mode-picker")
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                if model.labelMode == .weekday {
                    Text("Pick a weekday for each day below. A day without one keeps its number (Day 1, Day 2…).")
                        .foregroundColor(Theme.muted)
                }
            }
            // Buttons, not NavigationLinks: the list is always in edit mode for reordering, which disables links.
            Section {
                libraryRow("Saved workouts", id: "plan-saved-workouts") { showingSavedWorkouts = true }
                libraryRow("Routines", id: "plan-routines") { showingRoutines = true }
            }
            .listRowBackground(Theme.card)
            if let coverage = model.coverage {
                Section {
                    weeklyCoverageCard(coverage)
                        .listRowBackground(Theme.card)
                }
            }
            ForEach(model.days) { day in
                daySection(day)
            }
            Section {
                Button { model.addDay() } label: {
                    Text("+ Add day")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(Theme.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-day-button-plan")
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                        .background(Theme.card.clipShape(RoundedRectangle(cornerRadius: 12)))
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        // Always in edit mode so every exercise row shows its drag handle; there is no delete control because rows have no onDelete.
        .environment(\.editMode, .constant(.active))
        .navigationDestination(isPresented: $showingSavedWorkouts) { SavedWorkoutsView() }
        .navigationDestination(isPresented: $showingRoutines) { RoutinesView() }
        .screenBackground()
        .navigationTitle("Edit plan")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) {
            model.bind(services, focusDayId: focusDayId) { session.didChange() }
        }
        .sheet(item: $addTarget) { day in
            PlanAddExerciseSheet(day: day) { addTarget = nil }
        }
        .sheet(item: $entryBeingEdited) { entry in
            PlanEntryEditSheet(entry: entry, dayLabel: model.days.first { $0.id == entry.dayId }?.label ?? "this day") { scheme in
                model.updateEntry(entry, scheme: scheme)
                entryBeingEdited = nil
            } onRemove: {
                model.removeEntry(entry)
                entryBeingEdited = nil
            }
        }
        .confirmationDialog(dayToDelete.map { "Delete \($0.label)?" } ?? "Delete day?",
                            isPresented: Binding(get: { dayToDelete != nil }, set: { if !$0 { dayToDelete = nil } }),
                            titleVisibility: .visible, presenting: dayToDelete) { day in
            Button("Delete \(day.label)", role: .destructive) { model.deleteDay(day) }
        } message: { _ in
            Text("Its exercises leave the plan. Logged sets and history are kept.")
        }
        .errorAlert($model.errorMessage)
        .sheet(item: $routineTarget) { day in
            NavigationStack { RoutinesView(addingTo: day) { routineTarget = nil } }
        }
        .sheet(isPresented: $showingMuscleTargets) {
            if let coverage = model.coverage {
                MuscleSetTargetsSheet(model: model, items: coverage.weekly)
            }
        }
        .alert("Name the routine", isPresented: Binding(get: { dayToSave != nil }, set: { if !$0 { dayToSave = nil } })) {
            TextField("Name", text: $routineName).accessibilityIdentifier("routine-name-field")
            Button("Save") {
                if let day = dayToSave {
                    do {
                        try services.routines.saveDay(day.id, as: routineName)
                        session.didChange()
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
                dayToSave = nil
            }
            Button("Cancel", role: .cancel) { dayToSave = nil }
        }
    }

    @ViewBuilder
    private func daySection(_ day: PlanDay) -> some View {
        Section {
            Button { model.toggle(day) } label: { dayHeader(day) }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
                .accessibilityIdentifier("plan-day-\(day.position)")
            // With weekday naming the weekday is the main setting, so it must not hide inside a collapsed day.
            if model.labelMode == .weekday { weekdayRow(day).listRowBackground(Theme.card) }
            if model.isExpanded(day) {
                let entries = model.entries[day.id] ?? []
                ForEach(entries) { entry in
                    entryRow(entry)
                        .listRowBackground(Theme.card)
                        .listRowSeparatorTint(Theme.line)
                }
                .onMove { source, destination in model.moveEntries(in: day, from: source, to: destination) }

                Button { addTarget = day } label: {
                    Text("+ Add exercise").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .listRowBackground(Theme.card)
                .accessibilityIdentifier("add-exercise-button")

                HStack(spacing: 8) {
                    Button("+ Add routine") { routineTarget = day }
                        .accessibilityIdentifier("add-routine-button")
                    Button("Save day as routine") {
                        routineName = day.title ?? day.label
                        dayToSave = day
                    }
                    .accessibilityIdentifier("save-day-routine-button")
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .font(.system(size: 13))
                .listRowBackground(Theme.card)

                if model.labelMode == .number { weekdayRow(day).listRowBackground(Theme.card) }
                PlanDayTitleField(day: day) { model.setTitle($0, for: day) }
                    .listRowBackground(Theme.card)

                Button { dayToDelete = day } label: {
                    Text("Delete \(day.label) (history is kept)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.red)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.card)
                .accessibilityIdentifier("delete-day-button")
            }
        }
    }

    private func weeklyCoverageCard(_ coverage: PlanMuscleCoverageReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Weekly muscle coverage · all \(coverage.dayCount) days")
                    Text("\(coverage.metRequiredMusclesCount) of \(coverage.requiredMusclesCount) required muscles in target range")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(coverage.metRequiredMusclesCount == coverage.requiredMusclesCount ? Theme.green : Theme.amber)
                }
                Spacer()
                Button("Targets") { showingMuscleTargets = true }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Theme.green)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("plan-configure-muscle-targets")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(coverage.weekly) { item in
                    let tone: Pill.Tone = {
                        switch item.state {
                        case .met: return .green
                        case .optionalMet: return .grey
                        case .under: return .amber
                        case .over: return .red
                        }
                    }()
                    let mark = (item.state == .met || item.state == .optionalMet) ? " ✓" : ""
                    Pill(text: "\(item.region.displayName) \(item.plannedSets)/\(item.target.rangeLabel)\(mark)", tone: tone)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan-weekly-muscle-coverage")
    }

    private func dayHeader(_ day: PlanDay) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.label).font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text)
                Text(model.subtitle(of: day)).font(.system(size: 12)).foregroundColor(Theme.muted)
                if let muscleLine = model.dayMuscleLine(of: day) {
                    Text(muscleLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.greenSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let weekday = PlanViewModel.weekdayShortName(day.weekday) {
                Pill(text: weekday)
            }
            Image(systemName: model.isExpanded(day) ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.muted)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func entryRow(_ entry: PlanEntry) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                Text(entry.scheme.rangeText).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Spacer(minLength: 8)
            Button("Edit") { entryBeingEdited = entry }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.green)
                .buttonStyle(.borderless)
                .accessibilityIdentifier("edit-entry-button")
        }
        .padding(.vertical, 2)
    }

    private func weekdayRow(_ day: PlanDay) -> some View {
        HStack {
            Text("Weekday").font(.system(size: 15)).foregroundColor(Theme.text)
            Spacer()
            Picker("Weekday", selection: Binding(get: { day.weekday ?? 0 }, set: { model.setWeekday($0 == 0 ? nil : $0, for: day) })) {
                Text(model.labelMode == .weekday ? "Set a weekday" : "None").tag(0)
                ForEach(1...7, id: \.self) { Text(PlanViewModel.weekdayNames[$0 - 1]).tag($0) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(Theme.green)
            .accessibilityIdentifier("weekday-picker-\(day.position)")
        }
    }
}

/// Optional day title, saved when the keyboard is dismissed or the field loses focus.
private struct PlanDayTitleField: View {
    let day: PlanDay
    let onCommit: (String) -> Void

    @State private var text: String
    @FocusState private var isFocused: Bool

    init(day: PlanDay, onCommit: @escaping (String) -> Void) {
        self.day = day
        self.onCommit = onCommit
        _text = State(initialValue: day.title ?? "")
    }

    var body: some View {
        HStack {
            Text("Title").font(.system(size: 15)).foregroundColor(Theme.text)
            TextField("", text: $text, prompt: Text("Optional, e.g. Push").foregroundColor(Theme.muted))
                .multilineTextAlignment(.trailing)
                .foregroundColor(Theme.text)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit { onCommit(text) }
                .accessibilityIdentifier("day-title-field-\(day.position)")
        }
        .onChange(of: isFocused) { focused in
            if !focused { onCommit(text) }
        }
    }
}

private struct MuscleSetTargetsSheet: View {
    @ObservedObject var model: PlanViewModel
    let items: [MuscleRegionCoverage]
    @Environment(\.dismiss) private var dismiss

    private var currentItems: [MuscleRegionCoverage] {
        model.coverage?.weekly ?? items
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Default weekly hard-set range is 10–20 sets per muscle. Lower the minimum (even to 0) for smaller or optional muscles like Calves, Hips/Abductors, Glutes, Forearms, or Shins.")
                        .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    ForEach(currentItems) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.region.displayName).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                                if item.target.isCustom { Pill(text: "Custom", tone: .green) }
                                Spacer()
                                Text("Planned: \(item.plannedSets) sets")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.muted)
                                if item.target.isCustom {
                                    Button("Reset") { model.resetMuscleTarget(region: item.region) }
                                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amber)
                                        .buttonStyle(.plain)
                                }
                            }
                            HStack(spacing: 14) {
                                stepperRow(
                                    label: "Min",
                                    value: item.target.minSets,
                                    onMinus: {
                                        let next = max(0, item.target.minSets - 1)
                                        model.saveMuscleTarget(region: item.region, minSets: next, maxSets: item.target.maxSets)
                                    },
                                    onPlus: {
                                        let next = min(40, item.target.minSets + 1)
                                        let hi = max(item.target.maxSets, next)
                                        model.saveMuscleTarget(region: item.region, minSets: next, maxSets: hi)
                                    },
                                    idPrefix: "muscle-min-\(item.region.rawValue)")
                                stepperRow(
                                    label: "Max",
                                    value: item.target.maxSets,
                                    onMinus: {
                                        let next = max(0, item.target.maxSets - 1)
                                        let lo = min(item.target.minSets, next)
                                        model.saveMuscleTarget(region: item.region, minSets: lo, maxSets: next)
                                    },
                                    onPlus: {
                                        let next = min(40, item.target.maxSets + 1)
                                        model.saveMuscleTarget(region: item.region, minSets: item.target.minSets, maxSets: next)
                                    },
                                    idPrefix: "muscle-max-\(item.region.rawValue)")
                            }
                        }
                        .card()
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Weekly set targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.bold).foregroundColor(Theme.green)
                        .accessibilityIdentifier("muscle-targets-done")
                }
            }
        }
    }

    private func stepperRow(label: String, value: Int, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void, idPrefix: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundColor(Theme.muted)
            Button(action: onMinus) {
                Image(systemName: "minus.circle.fill").font(.system(size: 18)).foregroundColor(Theme.green)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(idPrefix)-minus")
            Text("\(value)")
                .font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                .frame(minWidth: 24)
            Button(action: onPlus) {
                Image(systemName: "plus.circle.fill").font(.system(size: 18)).foregroundColor(Theme.green)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("\(idPrefix)-plus")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.card2)
        .clipShape(Capsule())
    }
}
