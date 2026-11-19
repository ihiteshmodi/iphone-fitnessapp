import FitnessCore
import SwiftUI

@MainActor
final class QuickAddModel: ObservableObject {
    enum Kind: String, CaseIterable { case byWeight = "By weight", calories = "Calories only" }

    @Published var kind = Kind.byWeight
    @Published var name = ""
    @Published var presetID: Int?
    @Published var gramsText = "30"
    @Published var caloriesText = ""
    @Published var time: ExtraTime? = ExtraTimeGuess.now()
    @Published var note = ""
    @Published private(set) var presets: [Food] = []

    let date: ISODate
    private let services: Services

    init(services: Services, date: ISODate) {
        self.services = services
        self.date = date
        presets = (try? services.foods.estimatePresets()) ?? []
        presetID = presets.first?.id
        if presets.isEmpty { kind = .calories }
    }

    var preset: Food? { presets.first { $0.id == presetID } }

    /// "3 batches · 300 kcal · C 23.1 · F 23.1 g" for the grams typed.
    var weightPreview: String? {
        guard let preset, let grams = Format.decimal(gramsText), grams > 0, let perUnit = preset.draft.estimateGrams,
              let n = try? services.foods.nutrition(of: preset.id, quantity: grams / perUnit * preset.draft.baseQuantity) else { return nil }
        let units = grams / perUnit
        return "\(Format.number(units, maxDecimals: 2)) \(preset.unit)\(units == 1 ? "" : "s") · \(Format.grouped(n.calories)) kcal · P \(Format.number(n.protein, maxDecimals: 1)) · C \(Format.number(n.carbs, maxDecimals: 1)) · F \(Format.number(n.fat, maxDecimals: 1)) g"
    }

    func save() throws {
        let details = ExtraDetails(label: name, time: time, note: note)
        switch kind {
        case .byWeight:
            guard let presetID else { throw ValidationError("Choose a preset first") }
            guard let grams = Format.decimal(gramsText) else { throw ValidationError("Enter the grams as a number") }
            try services.dietDays.quickAddByWeight(presetID: presetID, grams: grams, on: date, details: details)
        case .calories:
            guard let calories = Format.decimal(caloriesText) else { throw ValidationError("Enter the calories as a number") }
            try services.dietDays.quickAddCalories(calories, on: date, details: details)
        }
    }
}

/// For food with no label: weigh it and log it against a preset, or type the calories.
struct QuickAddExtraSheet: View {
    @StateObject private var model: QuickAddModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    init(services: Services, date: ISODate, onSaved: @escaping () -> Void) {
        _model = StateObject(wrappedValue: QuickAddModel(services: services, date: date))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Kind", selection: $model.kind) {
                        ForEach(QuickAddModel.Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("quick-add-kind")
                    BodyField(label: "What was it (optional)", text: $model.name, identifier: "quick-add-name", keyboard: .default)
                    switch model.kind {
                    case .byWeight: weightSection
                    case .calories:
                        BodyField(label: "Calories", text: $model.caloriesText, unit: "kcal", identifier: "quick-add-calories")
                    }
                    ExtraDetailsFields(time: $model.time, note: $model.note)
                    Button("Add to \(Format.shortDate(model.date))", action: save)
                        .buttonStyle(PrimaryButtonStyle())
                        .accessibilityIdentifier("quick-add-save")
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($errorMessage)
        }
    }

    @ViewBuilder
    private var weightSection: some View {
        if model.presets.isEmpty {
            Text("No preset yet. In Foods, open a food and fill in \"grams one unit stands for\" to use it here.")
                .font(.system(size: 13)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
        } else {
            SectionLabel("Preset")
            ForEach(model.presets) { preset in
                Button { model.presetID = preset.id } label: {
                    HStack {
                        Text(preset.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        Text(DietFoodText.summary(preset)).font(.system(size: 11)).foregroundColor(Theme.muted)
                        Image(systemName: model.presetID == preset.id ? "checkmark.circle.fill" : "circle").foregroundColor(Theme.green)
                    }
                    .padding(10)
                    .background(Theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("quick-add-preset-\(preset.name)")
            }
            BodyField(label: "Weight", text: $model.gramsText, unit: "g", identifier: "quick-add-grams")
            if let preview = model.weightPreview {
                Text(preview).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                    .accessibilityIdentifier("quick-add-preview")
            }
        }
    }

    private func save() {
        do {
            try model.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
