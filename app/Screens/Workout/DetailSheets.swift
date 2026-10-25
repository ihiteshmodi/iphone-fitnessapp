import SwiftUI

struct DetailAddSetSheet: View {
    @ObservedObject var vm: ExerciseDetailViewModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var reps = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    field("Weight (kg)", text: $weight, keyboard: .decimalPad, id: "weight-field")
                    field("Reps", text: $reps, keyboard: .numberPad, id: "reps-field")
                }
                Button("Save set") {
                    if vm.logSet(weightText: weight, repsText: reps) {
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
            .navigationTitle(vm.name)
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
            weight = vm.prefillWeightText
            reps = vm.prefillRepsText
        }
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
