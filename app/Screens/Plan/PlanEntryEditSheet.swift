import SwiftUI

/// Change sets and rep range of one planned exercise, or take it off the day.
struct PlanEntryEditSheet: View {
    let entry: PlanEntry
    let dayLabel: String
    let onSave: (PlanRepScheme) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scheme: PlanRepScheme
    @State private var confirmRemove = false

    init(entry: PlanEntry, dayLabel: String, onSave: @escaping (PlanRepScheme) -> Void, onRemove: @escaping () -> Void) {
        self.entry = entry
        self.dayLabel = dayLabel
        self.onSave = onSave
        self.onRemove = onRemove
        _scheme = State(initialValue: entry.scheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button("Cancel") { dismiss() }.foregroundColor(Theme.green)
                Spacer()
                Text(entry.name).font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text).lineLimit(1)
                Spacer()
                Button("Save") { onSave(scheme) }
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.green)
                    .accessibilityIdentifier("save-entry-button")
            }
            PlanRepSchemeEditor(scheme: $scheme).card()
            Button("Remove from \(dayLabel)") { confirmRemove = true }
                .font(.system(size: 14))
                .foregroundColor(Theme.red)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("remove-entry-button")
            Text("Logged sets and history are kept.")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
        }
        .padding(16)
        .screenBackground()
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
        .confirmationDialog("Remove \(entry.name) from \(dayLabel)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }
}
