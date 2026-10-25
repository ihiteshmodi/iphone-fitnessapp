import SwiftUI

/// New / edit exercise form (mockup 8). Presented as a sheet by the Library and the Add exercise sheet.
struct LibraryExerciseFormView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: LibraryExerciseFormModel
    @FocusState private var focusedField: Field?
    @State private var confirmDelete = false

    private enum Field { case name, newMuscle, instructions }

    let onSaved: () -> Void

    init(mode: LibraryFormMode, onSaved: @escaping () -> Void = {}) {
        _model = StateObject(wrappedValue: LibraryExerciseFormModel(mode: mode))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    nameField
                    muscleField
                    instructionsField
                    Text("The muscle decides which volume chart this exercise appears in. Instructions show on the exercise screen and can be edited any time.")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                    if let label = model.addToDayLabel {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("Add to \(label)")
                            PlanRepSchemeEditor(scheme: $model.scheme)
                        }
                        .card()
                    }
                    Button(model.saveButtonTitle, action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("save-exercise-button")
                    if model.isEditing {
                        Button("Delete exercise") { confirmDelete = true }
                            .font(.system(size: 14))
                            .foregroundColor(Theme.red)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                            .accessibilityIdentifier("delete-exercise-button")
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .screenBackground()
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("save-exercise-toolbar-button") }
            }
        }
        .task(id: session.revision) { model.bind(services) { session.didChange() } }
        .errorAlert($model.errorMessage)
        .confirmationDialog("Delete this exercise?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete exercise", role: .destructive) {
                if model.delete() { finish() }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() {
        if model.save() { finish() }
    }

    private func finish() {
        onSaved()
        dismiss()
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Name")
            TextField("", text: $model.name, prompt: Text("Exercise name").foregroundColor(Theme.muted))
                .focused($focusedField, equals: .name)
                .submitLabel(.done)
                .onSubmit { focusedField = nil }
                .font(.system(size: 17))
                .foregroundColor(Theme.text)
                .accessibilityIdentifier("exercise-name-field")
        }
        .card()
    }

    private var muscleField: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Muscle")
            LibraryFlowLayout(spacing: 8) {
                ForEach(model.muscles, id: \.self) { muscle in
                    LibraryChip(title: muscle, isOn: !model.isNewMuscle && model.selectedMuscle == muscle) { model.chooseMuscle(muscle) }
                }
                LibraryChip(title: "+ New", isOn: model.isNewMuscle) {
                    model.chooseNewMuscle()
                    if model.isNewMuscle { focusedField = .newMuscle }
                }
                .accessibilityIdentifier("new-muscle-chip")
            }
            if model.isNewMuscle {
                TextField("", text: $model.newMuscle, prompt: Text("New muscle, e.g. Forearms").foregroundColor(Theme.muted))
                    .focused($focusedField, equals: .newMuscle)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .foregroundColor(Theme.text)
                    .padding(10)
                    .background(Theme.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("new-muscle-field")
            }
        }
        .card()
    }

    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("How to (instructions)")
            TextField("", text: $model.instructions, prompt: Text("Optional").foregroundColor(Theme.muted), axis: .vertical)
                .lineLimit(3...8)
                .focused($focusedField, equals: .instructions)
                .font(.system(size: 15))
                .foregroundColor(Theme.text)
                .accessibilityIdentifier("exercise-instructions-field")
        }
        .card()
    }
}

/// Wraps chips onto new lines (iOS 16 Layout protocol).
struct LibraryFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.maxWidth, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        for (index, frame) in rows.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], height: CGFloat, maxWidth: CGFloat) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxWidth = max(maxWidth, x - spacing)
        }
        return (frames, y + rowHeight, maxWidth)
    }
}
