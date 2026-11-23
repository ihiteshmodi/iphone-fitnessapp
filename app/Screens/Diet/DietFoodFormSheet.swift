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
    @Published var glycemicIndex = ""
    @Published var notes = ""
    @Published var estimateGrams = ""
    /// Typed text per extra nutrient; empty means unknown.
    @Published var nutrientTexts: [Nutrient: String] = [:]
    @Published var omega3Form: Omega3Form?

    static let kinds: [FoodKind] = [.food, .topping, .supplement, .herb, .liquid, .packaged]
    static let units = ["g", "ml", "unit", "capsule", "piece"]

    let existing: Food?
    private let services: Services

    init(services: Services, food: Food?, suggestedName: String = "", defaultKind: FoodKind? = nil, defaultUnit: String? = nil) {
        self.services = services
        existing = food
        guard let food else {
            name = suggestedName
            if let defaultKind { kind = defaultKind }
            if let defaultUnit { choose(unit: defaultUnit) }
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
        glycemicIndex = d.glycemicIndex.map { Format.number($0) } ?? ""
        notes = d.notes ?? ""
        estimateGrams = d.estimateGrams.map { Format.number($0) } ?? ""
        nutrientTexts = d.nutrients.mapValues { Format.number($0, maxDecimals: 3) }
        omega3Form = d.omega3Form
    }

    func filledCount(_ group: NutrientGroup) -> Int {
        Nutrient.allCases.filter { $0.group == group && !(nutrientTexts[$0] ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
    }

    /// Groups that matter for this food open by default; the rest stay folded so adding a food stays quick.
    func isRelevant(_ group: NutrientGroup) -> Bool {
        if filledCount(group) > 0 { return true }
        switch group {
        case .aminoAcids: return (Format.decimal(protein) ?? 0) > 0
        case .fatTypes: return (Format.decimal(fat) ?? 0) > 0
        case .omega: return kind == .supplement && (Format.decimal(fat) ?? 0) > 0
        case .alcoholCaffeine: return false
        case .vitamins, .minerals, .compounds: return kind == .supplement
        }
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

    /// Starts from the saved food so fields this form does not show are kept.
    func draft() throws -> FoodDraft {
        var d = existing?.draft ?? FoodDraft(name: name)
        d.name = name
        d.kind = kind
        d.unit = unit
        d.baseQuantity = try number(baseQuantity, "the base quantity") ?? 100
        d.protein = try number(protein, "protein") ?? 0
        d.carbs = try number(carbs, "carbs") ?? 0
        d.fat = try number(fat, "fat") ?? 0
        d.fiber = try number(fiber, "fiber") ?? 0
        d.satFat = try number(satFat, "saturated fat") ?? 0
        d.sodium = try number(sodium, "sodium") ?? 0
        d.glycemicIndex = try number(glycemicIndex, "glycemic index")
        d.labelCalories = try number(calories, "calories")
        d.price = try number(price, "the price")
        d.packSize = try number(packSize, "the pack size")
        d.piecesPerPack = isCounted ? nil : try number(piecesPerPack, "the pieces in a pack")
        d.pieceWeight = isCounted ? nil : try number(pieceWeight, "the piece weight")
        d.recipeMakes = nil
        d.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes
        d.estimateGrams = try number(estimateGrams, "the grams for quick add")
        var nutrients: [Nutrient: Double] = [:]
        for (key, text) in nutrientTexts {
            if let value = try number(text, key.title) { nutrients[key] = value }
        }
        d.nutrients = nutrients
        d.omega3Form = omega3Form
        return d
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

    init(services: Services, food: Food?, suggestedName: String = "", defaultKind: FoodKind? = nil, defaultUnit: String? = nil,
         onSaved: @escaping (Int) -> Void) {
        _model = StateObject(wrappedValue: FoodFormModel(services: services, food: food, suggestedName: suggestedName,
                                                         defaultKind: defaultKind, defaultUnit: defaultUnit))
        self.onSaved = onSaved
    }

    private var supplementCoverageRows: [MultivitaminWhatIf.Row]? {
        guard model.kind == .supplement, let draft = try? model.draft(),
              (MultivitaminWhatIf.isMultivitamin(draft) || model.filledCount(.vitamins) + model.filledCount(.minerals) >= 2) else {
            return nil
        }
        let scale = draft.baseQuantity > 0 ? (1.0 / draft.baseQuantity) : 1.0
        let profile = NutrientProfile(values: draft.nutrients.mapValues { $0 * scale }, unknown: [])
        return MultivitaminWhatIf.rows(perTablet: profile, tablets: 1)
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
                    if let coverageRows = supplementCoverageRows {
                        supplementCoverageCard(coverageRows)
                    }
                    BodyField(label: "Notes", text: $model.notes, identifier: "food-notes-field", keyboard: .default)
                    BodyField(label: "Quick add by weight: grams one \(model.unit) stands for (optional)", text: $model.estimateGrams,
                              unit: "g", identifier: "food-estimate-grams-field")
                    FoodNutrientSections(model: model)
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
            HStack(alignment: .top, spacing: 10) {
                BodyField(label: "Sodium (mg)", text: $model.sodium, identifier: "food-sodium-field")
                BodyField(label: "Glycemic index (0–115)", text: $model.glycemicIndex, identifier: "food-gi-field")
            }
            Text(model.caloriesNote).font(.system(size: 12)).foregroundColor(Theme.muted)
        }
    }

    private func supplementCoverageCard(_ rows: [MultivitaminWhatIf.Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Daily vitamin & mineral coverage · per 1 \(model.unit)")
            Text("Every tracked vitamin and mineral is listed below — missing ones show 0 / target so gaps are immediately clear.")
                .font(.system(size: 11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            ForEach([NutrientGroup.vitamins, .minerals], id: \.self) { group in
                Text(group.rawValue).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.green).padding(.top, 4)
                ForEach(rows.filter { $0.nutrient.group == group }, id: \.nutrient) { row in
                    HStack(spacing: 6) {
                        Text(row.nutrient.title).font(.system(size: 12)).foregroundColor(Theme.text)
                        if row.isFatSoluble { Pill(text: "fat-soluble", tone: .gold) }
                        if row.isOverLimit { Pill(text: "> UL", tone: .red) }
                        Spacer()
                        if let target = row.target {
                            Text(DailyTargetRow(nutrient: row.nutrient, amount: row.amount, target: target).formattedProgress)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(row.isOverLimit ? Theme.red : (row.amount >= target ? Theme.green : (row.amount == 0 ? Theme.muted : Theme.text)))
                        } else {
                            Text("\(Format.number(row.amount, maxDecimals: 1)) \(row.nutrient.unit)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(row.isOverLimit ? Theme.red : (row.amount == 0 ? Theme.muted : Theme.text))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .card()
        .accessibilityIdentifier("food-vitamin-mineral-coverage-card")
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


/// The extra nutrients, one folding section per group. Every field is optional; blank means unknown.
struct FoodNutrientSections: View {
    @ObservedObject var model: FoodFormModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("More nutrients (optional, per \(model.baseQuantity) \(model.unit))")
            ForEach(NutrientGroup.allCases, id: \.self) { group in
                FoodNutrientGroupView(model: model, group: group)
            }
        }
    }
}

private struct FoodNutrientGroupView: View {
    @ObservedObject var model: FoodFormModel
    let group: NutrientGroup
    @State private var isOpen: Bool?

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { isOpen ?? model.isRelevant(group) }, set: { isOpen = $0 })) {
            VStack(spacing: 8) {
                ForEach(Nutrient.allCases.filter { $0.group == group }, id: \.self) { key in
                    BodyField(label: key.title, text: Binding(get: { model.nutrientTexts[key] ?? "" }, set: { model.nutrientTexts[key] = $0 }),
                              unit: key.unit, identifier: "food-nutrient-\(key.rawValue)")
                }
                if group == .omega {
                    Picker("Omega-3 form", selection: $model.omega3Form) {
                        Text("Not set").tag(Omega3Form?.none)
                        ForEach(Omega3Form.allCases, id: \.self) { Text($0.rawValue).tag(Omega3Form?.some($0)) }
                    }
                    .tint(Theme.green)
                    .accessibilityIdentifier("food-omega3-form")
                }
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Text(group.rawValue).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                Text("\(model.filledCount(group)) filled").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        .tint(Theme.green)
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityIdentifier("food-nutrients-\(group.rawValue)")
    }
}
