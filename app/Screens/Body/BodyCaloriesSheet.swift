import FitnessCore
import SwiftUI

/// Sheet from screen 11: calories eaten, goal multiplier and macro rules.
struct BodyCaloriesSheet: View {
    let model: BodyViewModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var calories = ""
    @State private var multiplier = "1"
    @State private var protein = ""
    @State private var fat = ""
    @State private var errorMessage: String?
    @State private var prepared = false

    private static let presets: [(name: String, value: Double)] = [("Cut", 0.85), ("Maintain", 1.0), ("Bulk", 1.1)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BodyField(label: "Calories eaten per day (this week)", text: $calories, unit: "kcal", identifier: "calories-field")
                    multiplierSection
                    HStack(alignment: .top, spacing: 12) {
                        BodyField(label: "Protein g per lb", text: $protein, identifier: "protein-field")
                        BodyField(label: "Fat % of calories", text: $fat, identifier: "fat-field")
                    }
                    previewCard
                    Text("Carbs fill what is left. Macros are shown when the multiplier is below 1 (cutting), as in your notebook.")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Calories and macro rules")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold).accessibilityIdentifier("sheet-save-button")
                }
            }
            .errorAlert($errorMessage)
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            calories = model.initialCaloriesText
            multiplier = model.initialMultiplierText
            protein = model.initialProteinText
            fat = model.initialFatText
        }
    }

    private var multiplierSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Goal multiplier")
            HStack(spacing: 6) {
                ForEach(Self.presets, id: \.name) { preset in
                    let selected = Format.decimal(multiplier) == preset.value
                    Button("\(preset.name) \(Format.fixed(preset.value))") { multiplier = Format.number(preset.value) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(selected ? Theme.onGreen : Theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(selected ? Theme.green : Theme.card2)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("multiplier-\(preset.name.lowercased())")
                }
            }
            BodyField(label: "Or type your own", text: $multiplier, identifier: "multiplier-field")
        }
    }

    @ViewBuilder
    private var previewCard: some View {
        if let target = model.preview(caloriesText: calories, multiplierText: multiplier) {
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Preview")
                Text("Maintenance \(BodyNumbers.grouped(target.maintenanceCalories.rounded())) kcal · \(target.phase.rawValue)")
                    .font(.system(size: 14)).foregroundColor(Theme.text)
                Text("New target \(BodyNumbers.grouped(Double(target.adjustedTarget))) kcal")
                    .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.green)
            }
            .card()
        }
    }

    private func save() {
        do {
            try model.saveCalorieSettings(caloriesText: calories, multiplierText: multiplier, proteinText: protein, fatText: fat)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
