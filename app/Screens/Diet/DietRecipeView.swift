import FitnessCore
import SwiftUI

struct RecipeLineRow: Identifiable {
    let line: RecipeLine
    let name: String
    let unit: String
    var id: Int { line.foodID }
}

@MainActor
final class RecipeViewModel: ObservableObject {
    @Published private(set) var recipe: Food?
    @Published private(set) var lines: [RecipeLineRow] = []
    @Published private(set) var perUnit = Nutrition.zero
    @Published private(set) var perUnitCost = Cost.free
    @Published private(set) var usedInPlan: [String] = []
    @Published var errorMessage: String?

    let recipeID: Int
    private let services: Services

    init(services: Services, recipeID: Int) {
        self.services = services
        self.recipeID = recipeID
    }

    func load() {
        do {
            recipe = try services.foods.food(recipeID)
            guard let recipe else { return }
            lines = try services.foods.ingredients(of: recipeID).compactMap { line in
                try services.foods.food(line.foodID).map { RecipeLineRow(line: line, name: $0.name, unit: $0.unit) }
            }
            let quantity = displayQuantity
            perUnit = try services.foods.nutrition(of: recipeID, quantity: quantity)
            perUnitCost = try services.foods.cost(of: recipeID, quantity: quantity)
            let today = services.clock.today()
            usedInPlan = (try services.dietPlans.plan(inForceOn: today)?.items ?? []).filter { $0.foodID == recipeID }.map {
                "\($0.meal): \(Format.amount($0.quantity, unit: recipe.unit))"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The amount the totals are shown for: 100 g or 100 ml of a batch recipe, otherwise one piece or unit.
    var displayQuantity: Double { recipe.map { $0.unit == "g" || $0.unit == "ml" ? 100 : 1 } ?? 1 }

    var displayTitle: String {
        guard let recipe else { return "" }
        return "\(Format.amount(displayQuantity, unit: recipe.unit)) makes"
    }

    var makesText: String {
        guard let recipe else { return "" }
        return "Makes \(Format.amount(recipe.draft.recipeMakes ?? 1, unit: recipe.unit))"
    }

    var totalWeightText: String? {
        let weighed = lines.filter { $0.unit == "g" || $0.unit == "ml" }
        guard !weighed.isEmpty else { return nil }
        return Format.number(weighed.reduce(0) { $0 + $1.line.quantity }, maxDecimals: 2)
    }

    func save(_ line: RecipeLine) {
        var all = lines.map(\.line).filter { $0.foodID != line.foodID }
        all.append(line)
        apply(all)
    }

    func remove(foodID: Int) { apply(lines.map(\.line).filter { $0.foodID != foodID }) }

    func deleteRecipe() throws { try services.foods.delete(recipeID) }

    private func apply(_ all: [RecipeLine]) {
        do {
            try services.foods.setIngredients(of: recipeID, all)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A recipe: what one piece (or 100 g) makes, and its ingredients with their quantities.
struct DietRecipeView: View {
    @StateObject private var model: RecipeViewModel
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var editingLine: RecipeLine?
    @State private var addingIngredient = false
    @State private var editingRecipe = false
    @State private var confirmingDelete = false

    init(services: Services, recipeID: Int) {
        _model = StateObject(wrappedValue: RecipeViewModel(services: services, recipeID: recipeID))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let recipe = model.recipe {
                    HStack {
                        BodyHeader(caption: "Recipe", title: recipe.name)
                        Button("Edit") { editingRecipe = true }.font(.system(size: 14, weight: .semibold))
                            .accessibilityIdentifier("recipe-edit-button")
                    }
                    totalsCard(recipe)
                    ingredientsCard(recipe)
                    if !model.usedInPlan.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel("Used in your plan")
                            ForEach(model.usedInPlan, id: \.self) { Text($0).font(.system(size: 14)).foregroundColor(Theme.text) }
                        }
                        .card()
                    }
                    Text("Change an ingredient's price or nutrition in Foods and every recipe that uses it updates. A recipe can be one piece or a whole batch: list everything you cooked and set how much it makes; the app divides for you.")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                    Button("Delete recipe") { confirmingDelete = true }
                        .buttonStyle(BodyDestructiveButtonStyle()).accessibilityIdentifier("recipe-delete-button")
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) { model.load() }
        .errorAlert($model.errorMessage)
        .sheet(item: $editingLine) { line in
            DietIngredientSheet(services: services, recipeID: model.recipeID, existing: line,
                                onSave: { saved in model.save(saved) }, onRemove: { model.remove(foodID: line.foodID) })
        }
        .sheet(isPresented: $addingIngredient) {
            DietIngredientSheet(services: services, recipeID: model.recipeID, existing: nil,
                                onSave: { saved in model.save(saved) }, onRemove: nil)
        }
        .sheet(isPresented: $editingRecipe) {
            DietRecipeFormSheet(services: services, recipe: model.recipe) { _ in session.didChange() }
        }
        .confirmationDialog("Delete this recipe?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete recipe", role: .destructive) {
                do {
                    try model.deleteRecipe()
                    session.didChange()
                    dismiss()
                } catch {
                    model.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func totalsCard(_ recipe: Food) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(model.displayTitle)
            Text("\(Format.grouped(model.perUnit.calories)) kcal").font(.system(size: 26, weight: .heavy)).foregroundColor(Theme.text)
                .accessibilityIdentifier("recipe-calories")
            HStack(spacing: 8) {
                stat(Format.number(model.perUnit.protein, maxDecimals: 1) + " g", "protein")
                stat(Format.number(model.perUnit.carbs, maxDecimals: 1) + " g", "carbs")
                stat(Format.number(model.perUnit.fat, maxDecimals: 1) + " g", "fat")
                stat(Format.money(model.perUnitCost), "cost")
            }
            Text(model.makesText).font(.system(size: 12)).foregroundColor(Theme.muted)
        }
        .card()
    }

    private func stat(_ value: String, _ name: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text).minimumScaleFactor(0.7).lineLimit(1)
            Text(name).font(.system(size: 10)).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func ingredientsCard(_ recipe: Food) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Ingredients")
                Spacer()
                Button("+ Add") { addingIngredient = true }.font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("recipe-add-ingredient")
            }
            .padding(.bottom, 4)
            ForEach(model.lines) { row in
                Button { editingLine = row.line } label: {
                    HStack {
                        Text(row.name).font(.system(size: 14)).foregroundColor(Theme.text)
                        Spacer()
                        Text(Format.amount(row.line.quantity, unit: row.unit)).font(.system(size: 14)).foregroundColor(Theme.muted)
                    }
                    .padding(.vertical, 9).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("recipe-line-\(row.name)")
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            if let weight = model.totalWeightText {
                HStack {
                    Text("Total weight").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    Text(weight).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                }
                .padding(.top, 9)
            }
        }
        .card()
    }
}

extension RecipeLine: Identifiable {
    public var id: Int { foodID }
}

/// Add or change one ingredient of a recipe.
struct DietIngredientSheet: View {
    let services: Services
    let recipeID: Int
    let existing: RecipeLine?
    let onSave: (RecipeLine) -> Void
    let onRemove: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Food?
    @State private var quantity = ""
    @State private var results: [Food] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let selected {
                        Text(selected.name).font(.system(size: 18, weight: .bold)).foregroundColor(Theme.text)
                        BodyField(label: "Quantity", text: $quantity, unit: selected.unit, identifier: "ingredient-quantity-field")
                        Button("Save ingredient", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("ingredient-save-button")
                        if existing != nil, let onRemove {
                            Button("Remove from recipe") { onRemove(); dismiss() }.buttonStyle(BodyDestructiveButtonStyle())
                                .accessibilityIdentifier("ingredient-remove-button")
                        }
                    } else {
                        TextField("Search foods", text: $query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(12).background(Theme.card)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("ingredient-search-field")
                            .onChange(of: query) { _ in
                                results = ((try? services.foods.foods(matching: query)) ?? []).filter { $0.id != recipeID }.prefix(8).map { $0 }
                            }
                        ForEach(results) { food in
                            Button { selected = food; quantity = "" } label: {
                                Text(food.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                            }
                            .accessibilityIdentifier("ingredient-result-\(food.name)")
                        }
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(existing == nil ? "Add ingredient" : "Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($errorMessage)
        }
        .onAppear {
            guard let existing, selected == nil else { return }
            selected = try? services.foods.food(existing.foodID)
            quantity = Format.number(existing.quantity)
        }
    }

    private func save() {
        guard let selected else { return }
        guard let value = Format.decimal(quantity), value > 0 else {
            errorMessage = "Enter a quantity above 0"
            return
        }
        onSave(RecipeLine(foodID: selected.id, quantity: value))
        dismiss()
    }
}

/// Name, what it is counted in, and how much one batch makes.
struct DietRecipeFormSheet: View {
    let services: Services
    let recipe: Food?
    let onSaved: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var unit = "piece"
    @State private var makes = "1"
    @State private var notes = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BodyField(label: "Name", text: $name, identifier: "recipe-name-field", keyboard: .default)
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("Counted in")
                        HStack(spacing: 8) {
                            ForEach(["piece", "unit", "g", "ml"], id: \.self) { option in
                                Button(option) { unit = option }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(unit == option ? Theme.onGreen : Theme.muted)
                                    .padding(.horizontal, 12).padding(.vertical, 8)
                                    .background(unit == option ? Theme.green : Theme.card)
                                    .overlay(Capsule().stroke(Theme.line))
                                    .clipShape(Capsule())
                                    .accessibilityIdentifier("recipe-unit-\(option)")
                            }
                        }
                    }
                    BodyField(label: "Makes (all the ingredients together)", text: $makes, unit: unit, identifier: "recipe-makes-field")
                    BodyField(label: "Notes", text: $notes, identifier: "recipe-notes-field", keyboard: .default)
                    Button("Save recipe", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("recipe-save-button")
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(recipe == nil ? "New recipe" : "Edit recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($errorMessage)
        }
        .onAppear {
            guard let recipe, name.isEmpty else { return }
            name = recipe.name
            unit = recipe.unit
            makes = Format.number(recipe.draft.recipeMakes ?? 1)
            notes = recipe.draft.notes ?? ""
        }
    }

    private func save() {
        do {
            guard let makesValue = Format.decimal(makes) else { throw ValidationError("Enter how much it makes as a number") }
            var draft = recipe?.draft ?? FoodDraft(name: name, kind: .recipe, unit: unit, baseQuantity: 1)
            draft.name = name
            draft.unit = unit
            draft.baseQuantity = 1
            draft.recipeMakes = makesValue
            draft.notes = notes.isEmpty ? nil : notes
            let id: Int
            if let recipe {
                try services.foods.update(recipe.id, draft)
                id = recipe.id
            } else {
                id = try services.foods.add(draft)
            }
            onSaved(id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
