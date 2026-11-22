import Foundation

public enum GlycemicLoadBand: String, Equatable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"

    public init(gl: Double) {
        if gl >= 20 { self = .high }
        else if gl >= 10 { self = .medium }
        else { self = .low }
    }
}

public struct MealFoodContribution: Equatable, Identifiable {
    public var id: Int { foodID }
    public let foodID: Int
    public let foodName: String
    public let quantity: Double
    public let unit: String
    /// Grams of the amino acid, or Glycemic Load points.
    public let amount: Double
    /// Share of the meal's total for this metric (0–100).
    public let percent: Double
    /// Optional glycemic index + net carbs metadata when inspecting Glycemic Load.
    public let glycemicIndex: Double?
    public let netCarbsGrams: Double?
}

public struct MealAminoRow: Equatable, Identifiable {
    public var id: String { nutrient.rawValue }
    public let nutrient: Nutrient
    public let amount: Double
    public let target: Double
    public let contributors: [MealFoodContribution]

    public var isMet: Bool { amount >= target }
    public var share: Double { target > 0 ? amount / target : 0 }
}

public struct MealProfileReport: Equatable {
    public let mealName: String
    /// True when no items in the meal are ticked yet today, so the preview shows the planned items.
    public let isPlannedPreview: Bool
    public let totalGlycemicLoad: Double
    public let glycemicBand: GlycemicLoadBand
    public let glycemicContributors: [MealFoodContribution]
    public let aminoRows: [MealAminoRow]
}

/// Evaluates a meal's Glycemic Load, per-meal Amino Acids, and food-by-food contributors (decomposing recipes to leaf foods).
public enum MealProfileEvaluator {
    public static func evaluate(meal: DietMeal, book: FoodBook) throws -> MealProfileReport {
        let eatenLines = meal.lines.filter { $0.state == .eaten }
        let activeLines: [DietLine]
        let isPreview: Bool
        if !eatenLines.isEmpty {
            activeLines = eatenLines
            isPreview = false
        } else {
            activeLines = meal.lines.filter {
                if case .offCycle = $0.state { return false }
                return true
            }
            isPreview = true
        }

        // Aggregate leaf foods across all active lines (including inside recipes)
        var leafQty: [Int: Double] = [:]
        var leafOrder: [Int] = []
        for line in activeLines {
            for leaf in try book.leafQuantities(of: line.foodID, quantity: line.quantity) {
                if leafQty[leaf.food.id] == nil { leafOrder.append(leaf.food.id) }
                leafQty[leaf.food.id, default: 0] += leaf.quantity
            }
        }
        let leaves: [(food: Food, quantity: Double)] = leafOrder.compactMap { id in
            book.food(id).map { ($0, leafQty[id] ?? 0) }
        }

        // 1. Glycemic load & contributors
        var rawGL: [(food: Food, qty: Double, gl: Double, gi: Double, netCarbs: Double)] = []
        for (food, qty) in leaves {
            let scaled = food.perBase.scaled(by: qty / food.draft.baseQuantity)
            let netCarbs = max(0, scaled.carbs - scaled.fiber)
            guard netCarbs > 0, let gi = food.draft.glycemicIndex, gi > 0 else { continue }
            let gl = gi * netCarbs / 100.0
            if gl > 0 {
                rawGL.append((food: food, qty: qty, gl: gl, gi: gi, netCarbs: netCarbs))
            }
        }
        let totalGL = rawGL.reduce(0.0) { $0 + $1.gl }
        let glContributors = rawGL
            .sorted { $0.gl == $1.gl ? $0.food.name < $1.food.name : $0.gl > $1.gl }
            .map { item in
                MealFoodContribution(
                    foodID: item.food.id,
                    foodName: item.food.name,
                    quantity: item.qty,
                    unit: item.food.unit,
                    amount: item.gl,
                    percent: totalGL > 0 ? item.gl / totalGL * 100.0 : 0,
                    glycemicIndex: item.gi,
                    netCarbsGrams: item.netCarbs)
            }

        // 2. Per-meal amino acid rows & contributors
        let aminoNutrients = Nutrient.allCases.filter { $0.group == .aminoAcids }
        let aminoRows: [MealAminoRow] = aminoNutrients.compactMap { amino in
            guard let target = amino.dailyTarget else { return nil }
            var rawItems: [(food: Food, qty: Double, grams: Double)] = []
            for (food, qty) in leaves {
                let grams = (food.draft.nutrients[amino] ?? 0) * (qty / food.draft.baseQuantity)
                if grams > 0 {
                    rawItems.append((food: food, qty: qty, grams: grams))
                }
            }
            let totalGrams = rawItems.reduce(0.0) { $0 + $1.grams }
            let contribs = rawItems
                .sorted { $0.grams == $1.grams ? $0.food.name < $1.food.name : $0.grams > $1.grams }
                .map { item in
                    MealFoodContribution(
                        foodID: item.food.id,
                        foodName: item.food.name,
                        quantity: item.qty,
                        unit: item.food.unit,
                        amount: item.grams,
                        percent: totalGrams > 0 ? item.grams / totalGrams * 100.0 : 0,
                        glycemicIndex: nil,
                        netCarbsGrams: nil)
                }
            return MealAminoRow(nutrient: amino, amount: totalGrams, target: target, contributors: contribs)
        }

        return MealProfileReport(
            mealName: meal.name,
            isPlannedPreview: isPreview,
            totalGlycemicLoad: totalGL,
            glycemicBand: GlycemicLoadBand(gl: totalGL),
            glycemicContributors: glContributors,
            aminoRows: aminoRows)
    }
}
