import FitnessCore
import SwiftUI

/// A set that is already logged and is being corrected.
struct EditableSet: Identifiable, Equatable {
    let id: Int
    let weightKg: Double
    let reps: Int
    let date: ISODate
}

/// Adds a set (any day up to today) or, when `editing` is given, corrects one that is already logged.
struct DetailAddSetSheet: View {
    @ObservedObject var vm: ExerciseDetailViewModel
    var editing: EditableSet?
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var reps = ""
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    field("Weight (kg)", text: $weight, keyboard: .decimalPad, id: "weight-field")
                    field("Reps", text: $reps, keyboard: .numberPad, id: "reps-field")
                }
                HStack {
                    SectionLabel("Date")
                    Spacer()
                    DatePicker("Date", selection: $date, in: ...BodyDates.date(from: vm.today), displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityIdentifier("date-picker")
                }
                Button(editing == nil ? "Save set" : "Save changes") {
                    if save() {
                        onSaved()
                        dismiss()
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("save-set-button")
                Spacer()
            }
            .padding(16)
            .screenBackground()
            .navigationTitle(editing == nil ? vm.name : "Edit set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
                }
            }
            .errorAlert($vm.errorMessage)
        }
        .presentationDetents([.medium])
        .onAppear {
            if let editing {
                weight = Format.number(editing.weightKg)
                reps = String(editing.reps)
                date = BodyDates.date(from: editing.date)
            } else {
                weight = vm.prefillWeightText
                reps = vm.prefillRepsText
                date = BodyDates.date(from: vm.today)
            }
        }
    }

    private func save() -> Bool {
        let day = BodyDates.day(from: date)
        if let editing {
            return vm.updateSet(id: editing.id, weightText: weight, repsText: reps, on: day)
        }
        return vm.logSet(weightText: weight, repsText: reps, on: day)
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            TextField("", text: text)
                .keyboardType(keyboard)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(Theme.text)
                .padding(12)
                .background(Theme.card2)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier(id)
        }
    }
}

struct DetailHowToEditor: View {
    @ObservedObject var vm: ExerciseDetailViewModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .foregroundColor(Theme.text)
                .padding(10)
                .background(Theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(16)
                .accessibilityIdentifier("howto-editor")
                .screenBackground()
                .navigationTitle("How to")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if vm.saveInstructions(text) {
                                onSaved()
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("save-howto-button")
                    }
                }
                .errorAlert($vm.errorMessage)
        }
        .onAppear { text = vm.instructions }
    }
}
