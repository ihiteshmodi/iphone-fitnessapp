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
                HStack(alignment: .top, spacing: 10) {
                    NumberStepperField(title: "Weight", unit: "kg", text: $weight, step: 2.5, minimum: 0, decimals: true,
                                       hint: "steps of 2.5 kg", identifier: "weight-field")
                    NumberStepperField(title: "Reps", unit: nil, text: $reps, step: 1, minimum: 1, decimals: false,
                                       hint: vm.repRangeHint, identifier: "reps-field")
                }
                Text("Tap a number to type it. Reps are not limited to the rep range.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
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
}

/// A number with − and + around it. Tapping the number opens the keyboard, so typing still works.
struct NumberStepperField: View {
    let title: String
    let unit: String?
    @Binding var text: String
    let step: Double
    let minimum: Double
    let decimals: Bool
    let hint: String
    let identifier: String

    var body: some View {
        VStack(spacing: 8) {
            SectionLabel(title)
            HStack(spacing: 6) {
                stepButton("minus", delta: -step, label: "Decrease \(title.lowercased())", suffix: "minus")
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        TextField("", text: $text)
                            .keyboardType(decimals ? .decimalPad : .numberPad)
                            .multilineTextAlignment(.center)
                            .font(.system(size: 28, weight: .heavy))
                            .foregroundColor(Theme.text)
                            .minimumScaleFactor(0.6)
                            .accessibilityIdentifier(identifier)
                            // Tapping the number selects it, so typing replaces it without any backspacing.
                            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { note in
                                DispatchQueue.main.async { (note.object as? UITextField)?.selectAll(nil) }
                            }
                        if let unit { Text(unit).font(.system(size: 12)).foregroundColor(Theme.muted) }
                    }
                    Rectangle().fill(Theme.line).frame(height: 2).padding(.horizontal, 6)
                }
                stepButton("plus", delta: step, label: "Increase \(title.lowercased())", suffix: "plus")
            }
            Text(hint).font(.system(size: 10.5)).foregroundColor(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Theme.card2)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stepButton(_ symbol: String, delta: Double, label: String, suffix: String) -> some View {
        Button { nudge(by: delta) } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Theme.green)
                .frame(width: 38, height: 44)
                .background(Color(hex: 0x202824))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("\(identifier)-\(suffix)")
    }

    private func nudge(by delta: Double) {
        let current = Format.decimal(text) ?? 0
        let next = max(minimum, ((current + delta) * 100).rounded() / 100)
        text = Format.number(next)
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
