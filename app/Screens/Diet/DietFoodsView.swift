import FitnessCore
import SwiftUI

struct FoodRow: Identifiable {
    let food: Food
    let kcalText: String
    let costText: String
    var id: Int { food.id }
}

@MainActor
final class FoodsViewModel: ObservableObject {
    @Published var query = ""
    @Published var kind: FoodKind?
    @Published private(set) var rows: [FoodRow] = []
    @Published private(set) var totalCount = 0

    private let services: Services

    init(services: Services) { self.services = services }

    func load() {
        let book = try? services.foods.book()
        totalCount = book?.foods.count ?? 0
        let foods = (try? services.foods.foods(matching: query, kind: kind)) ?? []
        rows = foods.map { food in
            guard let book else { return FoodRow(food: food, kcalText: "", costText: "") }
            let quantity = Self.displayQuantity(food)
            let nutrition = try? book.nutrition(of: food.id, quantity: quantity)
            let cost = try? book.cost(of: food.id, quantity: quantity)
            return FoodRow(food: food, kcalText: nutrition.map { "\(Format.grouped($0.calories)) kcal" } ?? "",
                           costText: cost.map { $0.isComplete ? "\(Format.money($0)) per \(Format.number(quantity)) \(food.unit)" : "no price" } ?? "")
        }
    }

    /// The quantity a row is described for: a recipe in grams per 100 g, anything else per its base quantity.
    static func displayQuantity(_ food: Food) -> Double {
        if food.isRecipe { return food.unit == "g" || food.unit == "ml" ? 100 : 1 }
        return food.draft.baseQuantity
    }

    var countText: String { "\(totalCount) foods" }
}

/// The Foods section: search, filter by kind, tap a food to edit it or a recipe to see its ingredients.
struct DietFoodsView: View {
    @ObservedObject var model: FoodsViewModel
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var editing: Food?
    @State private var creatingFood = false
    @State private var creatingRecipe = false

    private let filters: [FoodKind?] = [nil, .food, .topping, .supplement, .herb, .liquid, .packaged, .recipe]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Search foods", text: $model.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(Theme.text)
                    .accessibilityIdentifier("foods-search-field")
                    .onChange(of: model.query) { _ in model.load() }
            }
            .padding(12)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filters, id: \.self) { kind in
                        Button(kind?.title ?? "All") { model.kind = kind; model.load() }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(model.kind == kind ? Theme.onGreen : Theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(model.kind == kind ? Theme.green : Theme.card)
                            .overlay(Capsule().stroke(Theme.line))
                            .clipShape(Capsule())
                            .accessibilityIdentifier("foods-filter-\(kind?.rawValue ?? "all")")
                    }
                }
            }

            HStack(spacing: 10) {
                Button("+ New food") { creatingFood = true }.accessibilityIdentifier("foods-new-food")
                Button("+ New recipe") { creatingRecipe = true }.accessibilityIdentifier("foods-new-recipe")
            }
            .buttonStyle(PrimaryButtonStyle(ghost: true))
            .font(.system(size: 14))

            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    if row.food.isRecipe {
                        NavigationLink { DietRecipeView(services: services, recipeID: row.food.id) } label: { rowView(row) }
                            .buttonStyle(.plain)
                    } else {
                        Button { editing = row.food } label: { rowView(row) }.buttonStyle(.plain)
                    }
                }
                if model.rows.isEmpty {
                    Text("No foods match.").font(.system(size: 13)).foregroundColor(Theme.muted).padding(12)
                }
            }
            .card(padding: 4)
        }
        .sheet(item: $editing) { food in
            DietFoodFormSheet(services: services, food: food) { _ in model.load() }
        }
        .sheet(isPresented: $creatingFood) { DietFoodFormSheet(services: services, food: nil) { _ in model.load() } }
        .sheet(isPresented: $creatingRecipe) { DietRecipeFormSheet(services: services, recipe: nil) { _ in model.load() } }
        .task(id: session.revision) { model.load() }
    }

    private func rowView(_ row: FoodRow) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.food.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    if row.food.isRecipe { Pill(text: "recipe", tone: .gold) }
                    if row.food.kind == .packaged { Pill(text: "packaged", tone: .green) }
                }
                Text(DietFoodText.summary(row.food)).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text(row.kcalText).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                Text(row.costText).font(.system(size: 11)).foregroundColor(Theme.muted)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("food-row-\(row.food.name)")
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 10) }
    }
}
