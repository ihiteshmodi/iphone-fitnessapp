import Foundation

/// An in-memory snapshot of the food library. Days are added up from it so a whole screen reads the database once.
public struct FoodBook {
    public let foods: [Int: Food]
    public let lines: [Int: [RecipeLine]]

    public init(foods: [Int: Food], lines: [Int: [RecipeLine]]) {
        self.foods = foods
        self.lines = lines
    }

    public func food(_ id: Int) -> Food? { foods[id] }

    /// Nutrition of `quantity` of the food's own unit. A recipe is its ingredients added up and divided by what it makes.
    public func nutrition(of id: Int, quantity: Double) throws -> Nutrition {
        try nutrition(of: id, quantity: quantity, visiting: [])
    }

    public func cost(of id: Int, quantity: Double) throws -> Cost {
        try cost(of: id, quantity: quantity, visiting: [])
    }

    private func nutrition(of id: Int, quantity: Double, visiting: Set<Int>) throws -> Nutrition {
        guard let food = foods[id] else { throw ValidationError("That food is not in the library") }
        guard food.isRecipe else { return food.perBase.scaled(by: quantity / food.draft.baseQuantity) }
        guard !visiting.contains(id) else { throw ValidationError("A recipe cannot contain itself") }
        let batch = try (lines[id] ?? []).reduce(Nutrition.zero) {
            $0 + (try nutrition(of: $1.foodID, quantity: $1.quantity, visiting: visiting.union([id])))
        }
        return batch.scaled(by: quantity / (food.draft.recipeMakes ?? 1))
    }

    private func cost(of id: Int, quantity: Double, visiting: Set<Int>) throws -> Cost {
        guard let food = foods[id] else { throw ValidationError("That food is not in the library") }
        guard food.isRecipe else {
            guard let price = food.draft.price, let pack = food.draft.packSize else { return Cost(amount: 0, isComplete: false) }
            return Cost(amount: price / pack * quantity, isComplete: true)
        }
        guard !visiting.contains(id) else { throw ValidationError("A recipe cannot contain itself") }
        let batch = try (lines[id] ?? []).reduce(Cost.free) {
            $0 + (try cost(of: $1.foodID, quantity: $1.quantity, visiting: visiting.union([id])))
        }
        return batch.scaled(by: quantity / (food.draft.recipeMakes ?? 1))
    }
}
