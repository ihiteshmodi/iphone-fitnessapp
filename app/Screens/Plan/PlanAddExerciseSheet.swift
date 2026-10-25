import FitnessCore
import SwiftUI

/// Add exercise sheet (mockup 7): pick from the library or create a new exercise.
struct PlanAddExerciseSheet: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var browser = LibraryBrowserModel()
    @StateObject private var model: PlanAddExerciseModel
    @State private var isCreating = false

    let onAdded: () -> Void

    init(day: PlanDay, onAdded: @escaping () -> Void) {
        _model = StateObject(wrappedValue: PlanAddExerciseModel(day: day))
        self.onAdded = onAdded
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Add to \(model.day.label)").font(.system(size: 19, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                Button("Cancel") { dismiss() }.foregroundColor(Theme.green)
            }
            LibrarySearchField(text: $browser.searchText, prompt: "Search the exercise library")
            LibraryMuscleChips(muscles: browser.muscles, selection: $browser.selectedMuscle)
            List {
                Button { isCreating = true } label: {
                    HStack(spacing: 10) {
                        tick(symbol: "plus", isOn: false)
                        Text("Create a new exercise").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.green)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(Theme.green.opacity(0.10))
                .accessibilityIdentifier("create-exercise-row")

                ForEach(browser.results) { exercise in
                    Button { model.toggle(exercise) } label: { pickRow(exercise) }
                        .buttonStyle(.plain)
                        .listRowBackground(model.selected?.id == exercise.id ? Theme.green.opacity(0.10) : Theme.card)
                        .listRowSeparatorTint(Theme.line)
                        .accessibilityIdentifier("pick-exercise-row")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            if let selected = model.selected {
                selectionPanel(selected)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .screenBackground()
        .preferredColorScheme(.dark)
        .task(id: session.revision) {
            browser.bind(services)
            model.bind(services) { session.didChange() }
        }
        .sheet(isPresented: $isCreating) {
            LibraryExerciseFormView(mode: .createAndAdd(dayId: model.day.id, dayLabel: model.day.label), onSaved: onAdded)
        }
        .errorAlert($model.errorMessage)
        .errorAlert($browser.errorMessage)
    }

    private func pickRow(_ exercise: Exercise) -> some View {
        HStack(spacing: 10) {
            tick(symbol: "checkmark", isOn: model.selected?.id == exercise.id)
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name).font(.system(size: 15, weight: .medium)).foregroundColor(Theme.text)
                Text(LibraryBrowserModel.pickerDetail(of: exercise)).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func tick(symbol: String, isOn: Bool) -> some View {
        ZStack {
            Circle().fill(isOn ? Theme.green : Theme.card2)
            Circle().stroke(isOn ? Color.clear : Theme.line)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isOn ? Theme.onGreen : Theme.green)
                .opacity(isOn || symbol == "plus" ? 1 : 0)
        }
        .frame(width: 24, height: 24)
    }

    private func selectionPanel(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(exercise.name)
            PlanRepSchemeEditor(scheme: $model.scheme)
            Button("Add to \(model.day.label)") {
                if model.add() { onAdded() }
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 6)
            .accessibilityIdentifier("confirm-add-exercise-button")
        }
        .card()
    }
}
