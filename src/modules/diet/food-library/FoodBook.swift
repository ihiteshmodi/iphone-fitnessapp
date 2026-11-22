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

    /// Extra nutrients of `quantity` of the food's own unit; a recipe adds up its ingredients like `nutrition`.
    public func profile(of id: Int, quantity: Double) throws -> NutrientProfile {
        try profile(of: id, quantity: quantity, visiting: [])
    }

    public func glycemicLoad(of id: Int, quantity: Double) throws -> Double {
        try glycemicLoad(of: id, quantity: quantity, visiting: [])
    }

    /// Decomposes a food or nested recipe into leaf non-recipe foods with their scaled quantities.
    public func leafQuantities(of id: Int, quantity: Double) throws -> [(food: Food, quantity: Double)] {
        var bucket: [Int: Double] = [:]
        var order: [Int] = []
        try collectLeaves(of: id, quantity: quantity, visiting: [], bucket: &bucket, order: &order)
        return order.compactMap { fid in foods[fid].map { ($0, bucket[fid] ?? 0) } }
    }

    private func collectLeaves(of id: Int, quantity: Double, visiting: Set<Int>,
                               bucket: inout [Int: Double], order: inout [Int]) throws {
        guard let food = foods[id] else { throw ValidationError("That food is not in the library") }
        if !food.isRecipe {
            if bucket[id] == nil { order.append(id) }
            bucket[id, default: 0] += quantity
            return
        }
        guard !visiting.contains(id) else { throw ValidationError("A recipe cannot contain itself") }
        let factor = quantity / (food.draft.recipeMakes ?? 1)
        for line in lines[id] ?? [] {
            try collectLeaves(of: line.foodID, quantity: line.quantity * factor, visiting: visiting.union([id]),
                              bucket: &bucket, order: &order)
        }
    }

    private func glycemicLoad(of id: Int, quantity: Double, visiting: Set<Int>) throws -> Double {
        guard let food = foods[id] else { throw ValidationError("That food is not in the library") }
        if !food.isRecipe {
            let scaled = food.perBase.scaled(by: quantity / food.draft.baseQuantity)
            let netCarbs = max(0, scaled.carbs - scaled.fiber)
            guard netCarbs > 0, let gi = food.draft.glycemicIndex else { return 0 }
            return gi * netCarbs / 100.0
        }
        guard !visiting.contains(id) else { throw ValidationError("A recipe cannot contain itself") }
        let batch = try (lines[id] ?? []).reduce(0.0) {
            $0 + (try glycemicLoad(of: $1.foodID, quantity: $1.quantity, visiting: visiting.union([id])))
        }
        return batch * (quantity / (food.draft.recipeMakes ?? 1))
    }

    private func profile(of id: Int, quantity: Double, visiting: Set<Int>) throws -> NutrientProfile {
        guard let food = foods[id] else { throw ValidationError("That food is not in the library") }
        guard food.isRecipe else { return NutrientProfile.of(food.draft.nutrients).scaled(by: quantity / food.draft.baseQuantity) }
        guard !visiting.contains(id) else { throw ValidationError("A recipe cannot contain itself") }
        let batch = try (lines[id] ?? []).reduce(NutrientProfile.empty) {
            $0 + (try profile(of: $1.foodID, quantity: $1.quantity, visiting: visiting.union([id])))
        }
        return batch.scaled(by: quantity / (food.draft.recipeMakes ?? 1))
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
