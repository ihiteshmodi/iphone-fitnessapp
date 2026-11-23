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

public struct DailyTargetContributor: Equatable, Identifiable {
    public let id: String
    public let sourceLabel: String
    public let foodID: Int
    public let foodName: String
    public let quantity: Double
    public let unit: String
    public let amount: Double
    public let vitaminDIU: Double?
    public let percent: Double
}

public struct DailyTargetBreakdownRow: Equatable, Identifiable {
    public var id: String { row.nutrient.rawValue }
    public let row: DailyTargetRow
    public let contributors: [DailyTargetContributor]
}

public struct DailyTargetsBreakdownReport: Equatable {
    public let isPlannedMode: Bool
    public let fiberAmount: Double
    public let fiberTarget: Double
    public let fiberContributors: [DailyTargetContributor]
    public let nutrientRows: [DailyTargetBreakdownRow]
}

public struct RecipeNutritionReport: Equatable {
    public let mealProfile: MealProfileReport
    public let dailyTargets: DailyTargetsBreakdownReport
}

/// Evaluates a meal's Glycemic Load, per-meal Amino Acids, and food-by-food contributors (decomposing recipes to leaf foods).
public enum MealProfileEvaluator {
    public static func evaluate(meal: DietMeal, book: FoodBook, forcePlanned: Bool = false) throws -> MealProfileReport {
        let eatenLines = meal.lines.filter { $0.state == .eaten }
        let activeLines: [DietLine]
        let isPreview: Bool
        if !forcePlanned && !eatenLines.isEmpty {
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
        return evaluateLeaves(name: meal.name, isPlannedPreview: isPreview, leaves: leaves)
    }

    static func evaluateLeaves(name: String, isPlannedPreview: Bool, leaves: [(food: Food, quantity: Double)]) -> MealProfileReport {
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
            mealName: name,
            isPlannedPreview: isPlannedPreview,
            totalGlycemicLoad: totalGL,
            glycemicBand: GlycemicLoadBand(gl: totalGL),
            glycemicContributors: glContributors,
            aminoRows: aminoRows)
    }
}

/// Evaluates Fiber, Vitamins, Minerals, Omegas, and Compounds with food/meal contributors sorted descending,
/// for Today (eaten), Diet Plan (planned), or a standalone Recipe.
public enum DailyTargetsBreakdownEvaluator {
    private struct ScopedLeaf {
        let sourceLabel: String
        let food: Food
        var quantity: Double
    }

    public static func evaluate(day: DietDay, book: FoodBook, plannedMode: Bool = false) throws -> DailyTargetsBreakdownReport {
        var scoped: [ScopedLeaf] = []
        var indexByKey: [String: Int] = [:]

        func appendLeaf(source: String, food: Food, qty: Double) {
            guard qty > 0 else { return }
            let key = "\(source)|\(food.id)"
            if let idx = indexByKey[key] {
                scoped[idx].quantity += qty
            } else {
                indexByKey[key] = scoped.count
                scoped.append(ScopedLeaf(sourceLabel: source, food: food, quantity: qty))
            }
        }

        for meal in day.meals {
            let lines: [DietLine]
            if plannedMode {
                lines = meal.lines.filter {
                    if case .offCycle = $0.state { return false }
                    return true
                }
            } else {
                lines = meal.lines.filter { $0.state == .eaten }
            }
            for line in lines {
                for leaf in try book.leafQuantities(of: line.foodID, quantity: line.quantity) {
                    appendLeaf(source: meal.name, food: leaf.food, qty: leaf.quantity)
                }
            }
        }

        if !plannedMode {
            for extra in day.extras {
                for leaf in try book.leafQuantities(of: extra.foodID, quantity: extra.amount) {
                    appendLeaf(source: "Extras", food: leaf.food, qty: leaf.quantity)
                }
            }
        }

        let profile = plannedMode ? day.plannedProfile : day.eatenProfile
        let baseNutrition = plannedMode ? day.planned : day.total
        let fiberTarget = max(Nutrient.fiberDailyTarget, baseNutrition.calories / 1000.0 * 14.0)
        return buildTargetsReport(
            isPlannedMode: plannedMode,
            scoped: scoped,
            profile: profile,
            fiberAmount: baseNutrition.fiber,
            fiberTarget: fiberTarget)
    }

    public static func evaluateRecipe(recipeID: Int, quantity: Double, book: FoodBook) throws -> RecipeNutritionReport {
        let recipeName = book.food(recipeID)?.name ?? "Recipe"
        let leaves = try book.leafQuantities(of: recipeID, quantity: quantity)
        let mealProfile = MealProfileEvaluator.evaluateLeaves(name: recipeName, isPlannedPreview: false, leaves: leaves)

        let scoped = leaves.map { ScopedLeaf(sourceLabel: "Ingredient", food: $0.food, quantity: $0.quantity) }
        let profile = try book.profile(of: recipeID, quantity: quantity)
        let nutrition = try book.nutrition(of: recipeID, quantity: quantity)
        let fiberTarget = max(Nutrient.fiberDailyTarget, nutrition.calories / 1000.0 * 14.0)
        let targets = buildTargetsReport(
            isPlannedMode: false,
            scoped: scoped,
            profile: profile,
            fiberAmount: nutrition.fiber,
            fiberTarget: fiberTarget)
        return RecipeNutritionReport(mealProfile: mealProfile, dailyTargets: targets)
    }

    private static func buildTargetsReport(isPlannedMode: Bool, scoped: [ScopedLeaf], profile: NutrientProfile,
                                           fiberAmount: Double, fiberTarget: Double) -> DailyTargetsBreakdownReport {
        var rawFiber: [(leaf: ScopedLeaf, grams: Double)] = []
        for item in scoped {
            let g = item.food.perBase.fiber * (item.quantity / item.food.draft.baseQuantity)
            if g > 0 { rawFiber.append((item, g)) }
        }
        let fiberSum = rawFiber.reduce(0.0) { $0 + $1.grams }
        let fiberContribs = rawFiber
            .sorted { $0.grams == $1.grams ? $0.leaf.food.name < $1.leaf.food.name : $0.grams > $1.grams }
            .map { entry in
                DailyTargetContributor(
                    id: "\(entry.leaf.sourceLabel)|\(entry.leaf.food.id)",
                    sourceLabel: entry.leaf.sourceLabel,
                    foodID: entry.leaf.food.id,
                    foodName: entry.leaf.food.name,
                    quantity: entry.leaf.quantity,
                    unit: entry.leaf.food.unit,
                    amount: entry.grams,
                    vitaminDIU: nil,
                    percent: fiberSum > 0 ? entry.grams / fiberSum * 100.0 : 0)
            }

        let baseRows = DailyTargetReport.dailyRows(profile)
        let nutrientRows: [DailyTargetBreakdownRow] = baseRows.map { row in
            var rawItems: [(leaf: ScopedLeaf, val: Double, iu: Double?)] = []
            for item in scoped {
                let scale = item.quantity / item.food.draft.baseQuantity
                let val: Double
                let iu: Double?
                if row.nutrient == .vitaminD {
                    let mcg = (item.food.draft.nutrients[.vitaminD] ?? 0) * scale
                    let d3IU = (item.food.draft.nutrients[.vitaminD3] ?? 0) * scale
                    val = mcg + d3IU / NutrientProfile.vitaminDIUPerMcg
                    iu = val > 0 ? val * NutrientProfile.vitaminDIUPerMcg : nil
                } else {
                    val = (item.food.draft.nutrients[row.nutrient] ?? 0) * scale
                    iu = nil
                }
                if val > 0 {
                    rawItems.append((item, val, iu))
                }
            }
            let sum = rawItems.reduce(0.0) { $0 + $1.val }
            let contribs = rawItems
                .sorted { $0.val == $1.val ? $0.leaf.food.name < $1.leaf.food.name : $0.val > $1.val }
                .map { entry in
                    DailyTargetContributor(
                        id: "\(entry.leaf.sourceLabel)|\(entry.leaf.food.id)",
                        sourceLabel: entry.leaf.sourceLabel,
                        foodID: entry.leaf.food.id,
                        foodName: entry.leaf.food.name,
                        quantity: entry.leaf.quantity,
                        unit: entry.leaf.food.unit,
                        amount: entry.val,
                        vitaminDIU: entry.iu,
                        percent: sum > 0 ? entry.val / sum * 100.0 : 0)
                }
            return DailyTargetBreakdownRow(row: row, contributors: contribs)
        }

        return DailyTargetsBreakdownReport(
            isPlannedMode: isPlannedMode,
            fiberAmount: fiberAmount,
            fiberTarget: fiberTarget,
            fiberContributors: fiberContribs,
            nutrientRows: nutrientRows)
    }
}
