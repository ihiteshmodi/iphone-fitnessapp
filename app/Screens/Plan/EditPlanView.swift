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

    init(focusDayId: Int? = nil) {
        self.focusDayId = focusDayId
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
        .screenBackground()
        .navigationTitle("Edit plan")
        .navigationBarTitleDisplayMode(.large)
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

    private func dayHeader(_ day: PlanDay) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(day.label).font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text)
                Text(model.subtitle(of: day)).font(.system(size: 12)).foregroundColor(Theme.muted)
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
