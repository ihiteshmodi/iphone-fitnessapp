import FitnessCore
import SwiftUI

/// Choose the muscles of one exercise: pick an entire region in one tap, or set each part to none, secondary or primary.
/// The whole body stays visible so the choice can be seen as it is made.
struct MuscleEditorSheet: View {
    let exerciseName: String
    let isCustom: Bool
    let onSave: ([MuscleAssignment]) -> Void
    let onReset: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: MuscleSelection
    /// What the sheet opened with, so Save without a change does not turn automatic muscles into chosen ones.
    private let initialSelection: MuscleSelection

    init(exerciseName: String, muscles: ExerciseMuscles, onSave: @escaping ([MuscleAssignment]) -> Void, onReset: @escaping () -> Void) {
        self.exerciseName = exerciseName
        self.isCustom = muscles.isCustom
        self.onSave = onSave
        self.onReset = onReset
        let initial = MuscleSelection(assignments: muscles.assignments)
        self.initialSelection = initial
        _selection = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(exerciseName).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)

                    HStack(spacing: 6) {
                        ForEach(BodyView.allCases, id: \.self) { side in
                            MuscleFigureView(view: side, assignments: selection.assignments)
                                .frame(width: 86, height: 190)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .card()

                    ForEach(MuscleRegion.allCases) { region in regionSection(region) }

                    if isCustom {
                        Button("Reset to automatic") {
                            onReset()
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle(ghost: true))
                        .accessibilityIdentifier("muscle-reset-button")
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Muscles worked")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if isCustom || selection != initialSelection { onSave(selection.assignments) }
                        dismiss()
                    }
                    .accessibilityIdentifier("muscle-save-button")
                }
            }
        }
    }

    private func regionSection(_ region: MuscleRegion) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(region.displayName).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                let entire = selection.state(of: region) == .all
                Button(entire ? "Clear \(region.displayName.lowercased())" : "Select entire \(region.displayName.lowercased())") {
                    selection.toggleEntire(region)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.green)
                .accessibilityIdentifier("muscle-region-\(region.rawValue)")
            }
            VStack(spacing: 0) {
                ForEach(Array(region.parts.enumerated()), id: \.element) { index, part in
                    HStack(spacing: 10) {
                        Text(part.displayName).font(.system(size: 14)).foregroundColor(Theme.text)
                        Spacer(minLength: 6)
                        MuscleRoleSegments(role: Binding(get: { selection.role(of: part) }, set: { selection.setRole($0, for: part) }),
                                           partKey: part.rawValue)
                    }
                    .padding(.vertical, 8)
                    if index < region.parts.count - 1 { Divider().background(Theme.line) }
                }
            }
            .padding(.horizontal, 14)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }
}

/// None / Secondary / Primary.
private struct MuscleRoleSegments: View {
    @Binding var role: MuscleRole?
    let partKey: String

    var body: some View {
        HStack(spacing: 2) {
            segment("None", value: nil)
            segment("Secondary", value: .secondary)
            segment("Primary", value: .primary)
        }
        .padding(2)
        .background(Theme.card2)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func segment(_ title: String, value: MuscleRole?) -> some View {
        let selected = role == value
        let fill: Color = !selected || value == nil ? .clear : (value == .primary ? Theme.green : Theme.green.opacity(0.42))
        return Button { role = value } label: {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(!selected ? Theme.muted : (value == .primary ? Theme.onGreen : Theme.text))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(selected && value == nil ? Theme.card : fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("muscle-\(partKey)-\(value?.rawValue ?? "none")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
