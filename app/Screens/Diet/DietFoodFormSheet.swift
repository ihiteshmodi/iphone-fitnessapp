import FitnessCore
import SwiftUI

@MainActor
final class FoodFormModel: ObservableObject {
    @Published var name = ""
    @Published var kind = FoodKind.food
    @Published var unit = "g"
    @Published var baseQuantity = "100"
    @Published var packSize = ""
    @Published var price = ""
    @Published var piecesPerPack = ""
    @Published var pieceWeight = ""
    @Published var calories = ""
    @Published var protein = ""
    @Published var carbs = ""
    @Published var fat = ""
    @Published var fiber = ""
    @Published var satFat = ""
    @Published var sodium = ""
    @Published var notes = ""

    static let kinds: [FoodKind] = [.food, .topping, .supplement, .herb, .liquid, .packaged]
    static let units = ["g", "ml", "unit", "capsule", "piece"]

    let existing: Food?
    private let services: Services

    init(services: Services, food: Food?, suggestedName: String = "") {
        self.services = services
        existing = food
        guard let food else {
            name = suggestedName
            return
        }
        let d = food.draft
        name = d.name
        kind = d.kind
        unit = d.unit
        baseQuantity = Format.number(d.baseQuantity)
        packSize = d.packSize.map { Format.number($0) } ?? ""
        price = d.price.map { Format.number($0) } ?? ""
        piecesPerPack = d.piecesPerPack.map { Format.number($0) } ?? ""
        pieceWeight = d.pieceWeight.map { Format.number($0) } ?? ""
        calories = d.labelCalories.map { Format.number($0) } ?? ""
        protein = d.protein == 0 ? "" : Format.number(d.protein)
        carbs = d.carbs == 0 ? "" : Format.number(d.carbs)
        fat = d.fat == 0 ? "" : Format.number(d.fat)
        fiber = d.fiber == 0 ? "" : Format.number(d.fiber)
        satFat = d.satFat == 0 ? "" : Format.number(d.satFat)
        sodium = d.sodium == 0 ? "" : Format.number(d.sodium)
        notes = d.notes ?? ""
    }

    /// Foods counted in units, capsules or pieces have no weight per piece: one of them is the piece.
    var isCounted: Bool { unit != "g" && unit != "ml" }

    func choose(unit newUnit: String) {
        unit = newUnit
        let counted = newUnit != "g" && newUnit != "ml"
        if counted && baseQuantity == "100" { baseQuantity = "1" }
        if !counted && baseQuantity == "1" { baseQuantity = "100" }
    }

    private func number(_ text: String, _ field: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        guard let value = Format.decimal(trimmed) else { throw ValidationError("Enter \(field) as a number") }
        return value
    }

    func draft() throws -> FoodDraft {
        FoodDraft(name: name, kind: kind, unit: unit, baseQuantity: try number(baseQuantity, "the base quantity") ?? 100,
                  protein: try number(protein, "protein") ?? 0, carbs: try number(carbs, "carbs") ?? 0, fat: try number(fat, "fat") ?? 0,
                  fiber: try number(fiber, "fiber") ?? 0, satFat: try number(satFat, "saturated fat") ?? 0, sodium: try number(sodium, "sodium") ?? 0,
                  labelCalories: try number(calories, "calories"), price: try number(price, "the price"), packSize: try number(packSize, "the pack size"),
                  piecesPerPack: isCounted ? nil : try number(piecesPerPack, "the pieces in a pack"),
                  pieceWeight: isCounted ? nil : try number(pieceWeight, "the piece weight"),
                  recipeMakes: nil, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes)
    }

    /// "→ 1 piece = 7.14 g · ₹1.14 a piece"
    var pieceNote: String? {
        guard let draft = try? draft(), draft.piecesPerPack != nil || draft.pieceWeight != nil else { return nil }
        let food = Food(id: 0, draft: draft)
        guard let weight = Portions.pieceWeight(of: food) else { return nil }
        var text = "→ 1 piece = \(Format.number(weight, maxDecimals: 2)) \(unit)"
        if let price = draft.price, let pack = draft.packSize { text += " · ₹\(Format.number(price / pack * weight, maxDecimals: 2)) a piece" }
        return text
    }

    /// What one piece gives, so a wrong label shows up before saving.
    var pieceCheck: String? {
        guard let draft = try? draft(), draft.baseQuantity > 0 else { return nil }
        let food = Food(id: 0, draft: draft)
        let grams = isCounted ? 1 : Portions.pieceWeight(of: food)
        guard let weight = grams else { return nil }
        let n = food.perBase.scaled(by: weight / draft.baseQuantity)
        return "\(Format.number(n.calories, maxDecimals: 0)) kcal · P \(Format.number(n.protein, maxDecimals: 1)) · C \(Format.number(n.carbs, maxDecimals: 1)) · F \(Format.number(n.fat, maxDecimals: 1))"
    }

    var caloriesNote: String {
        guard let draft = try? draft() else { return "" }
        let auto = 4 * draft.protein + 4 * draft.carbs + 9 * draft.fat
        if let typed = draft.labelCalories { return "You typed \(Format.number(typed)), so the label value is used. Leave it empty and it is worked out as 4 × protein + 4 × carbs + 9 × fat (\(Format.number(auto, maxDecimals: 0)))." }
        return "Calories are worked out as 4 × protein + 4 × carbs + 9 × fat = \(Format.number(auto, maxDecimals: 0))."
    }

    /// Saves and returns the food's id.
    func save() throws -> Int {
        let draft = try draft()
        if let existing {
            try services.foods.update(existing.id, draft)
            return existing.id
        }
        return try services.foods.add(draft)
    }

    func delete() throws {
        guard let existing else { return }
        try services.foods.delete(existing.id)
    }
}

/// New or edit food: name, kind, pack and price, and the nutrition label as it is printed.
struct DietFoodFormSheet: View {
    @StateObject private var model: FoodFormModel
    let onSaved: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AppSession
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    init(services: Services, food: Food?, suggestedName: String = "", onSaved: @escaping (Int) -> Void) {
        _model = StateObject(wrappedValue: FoodFormModel(services: services, food: food, suggestedName: suggestedName))
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BodyField(label: "Name", text: $model.name, identifier: "food-name-field", keyboard: .default)
                    kindChips
                    unitChips
                    HStack(alignment: .top, spacing: 10) {
                        BodyField(label: "Pack size", text: $model.packSize, unit: model.unit, identifier: "food-pack-field")
                        if !model.isCounted {
                            BodyField(label: "Pieces in pack", text: $model.piecesPerPack, identifier: "food-pieces-field")
                        }
                        BodyField(label: "Price", text: $model.price, unit: "₹", identifier: "food-price-field")
                    }
                    if !model.isCounted {
                        BodyField(label: "Weight of one piece (optional)", text: $model.pieceWeight, unit: model.unit, identifier: "food-piece-weight-field")
                    } else {
                        Text("Counted in \(model.unit)s: price is for the pack size above, and nutrition below is for one \(model.unit).")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    if let note = model.pieceNote { Text(note).font(.system(size: 12)).foregroundColor(Theme.green) }
                    labelSection
                    BodyField(label: "Notes", text: $model.notes, identifier: "food-notes-field", keyboard: .default)
                    if let check = model.pieceCheck { pieceCheckCard(check) }
                    Button("Save food", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("food-save-button")
                    if model.existing != nil {
                        Button("Delete food") { confirmingDelete = true }
                            .buttonStyle(BodyDestructiveButtonStyle()).accessibilityIdentifier("food-delete-button")
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(model.existing == nil ? "New food" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($errorMessage)
            .confirmationDialog("Delete this food?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete food", role: .destructive, action: delete)
            }
        }
    }

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FoodFormModel.kinds, id: \.self) { kind in chip(kind.title, selected: model.kind == kind, id: "food-kind-\(kind.rawValue)") { model.kind = kind } }
            }
        }
    }

    private var unitChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Counted in")
            HStack(spacing: 8) {
                ForEach(FoodFormModel.units, id: \.self) { unit in chip(unit, selected: model.unit == unit, id: "food-unit-\(unit)") { model.choose(unit: unit) } }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(selected ? Theme.onGreen : Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(selected ? Theme.green : Theme.card)
            .overlay(Capsule().stroke(Theme.line))
            .clipShape(Capsule())
            .accessibilityIdentifier(id)
    }

    private var labelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                SectionLabel("Nutrition label · values per")
                TextField("", text: $model.baseQuantity)
                    .keyboardType(.decimalPad)
                    .frame(width: 56)
                    .font(.system(size: 13, weight: .bold)).foregroundColor(Theme.green)
                    .accessibilityIdentifier("food-base-field")
                Text(model.unit).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            HStack(alignment: .top, spacing: 10) {
                BodyField(label: "Calories", text: $model.calories, identifier: "food-calories-field")
                BodyField(label: "Protein", text: $model.protein, identifier: "food-protein-field")
                BodyField(label: "Carbs", text: $model.carbs, identifier: "food-carbs-field")
            }
            HStack(alignment: .top, spacing: 10) {
                BodyField(label: "Fat", text: $model.fat, identifier: "food-fat-field")
                BodyField(label: "Fiber", text: $model.fiber, identifier: "food-fiber-field")
                BodyField(label: "Sat fat", text: $model.satFat, identifier: "food-satfat-field")
            }
            BodyField(label: "Sodium (mg)", text: $model.sodium, identifier: "food-sodium-field")
            Text(model.caloriesNote).font(.system(size: 12)).foregroundColor(Theme.muted)
        }
    }

    private func pieceCheckCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            SectionLabel(model.isCounted ? "Check: one \(model.unit)" : "Check: one piece")
            Text(text).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
        }
        .card()
    }

    private func save() {
        do {
            let id = try model.save()
            session.didChange()
            onSaved(id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try model.delete()
            session.didChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
