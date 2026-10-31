import Foundation

public enum DietItemState: Equatable {
    /// Ticked for this day: it counts.
    case eaten
    /// Not ticked (yet): it does not count.
    case notEaten
    /// The item's cycle is off today; `backOn` is the next day it is taken.
    case offCycle(backOn: ISODate?)
}

public struct DietLine: Equatable, Identifiable {
    public let meal: String
    public let foodID: Int
    public let name: String
    public let unit: String
    public let quantity: Double
    public let state: DietItemState
    /// What the line would give if eaten; the day's totals only count lines that are `.eaten`.
    public let nutrition: Nutrition
    public let cost: Cost
    /// Where the item is in its cycle; nil for an item taken every day.
    public let cycle: CycleState?
    public var id: String { "\(meal)|\(foodID)" }
}

/// How much of a meal is ticked, for its checkbox.
public enum MealTickState: Equatable {
    case none
    case some
    case all
}

public struct DietMeal: Equatable {
    public let name: String
    public let lines: [DietLine]

    private var tickable: [DietLine] { lines.filter { if case .offCycle = $0.state { return false } else { return true } } }

    public var eatenCalories: Double { lines.filter { $0.state == .eaten }.reduce(0) { $0 + $1.nutrition.calories } }
    /// What the meal would give with everything that is on today ticked.
    public var plannedCalories: Double { tickable.reduce(0) { $0 + $1.nutrition.calories } }
    /// False when every item is off its cycle today, so there is nothing to tick.
    public var canTick: Bool { !tickable.isEmpty }

    public var tickState: MealTickState {
        let ticked = tickable.filter { $0.state == .eaten }.count
        if ticked == 0 { return .none }
        return ticked == tickable.count ? .all : .some
    }
}

public struct DietExtra: Equatable, Identifiable {
    public let id: Int
    public let foodID: Int
    public let name: String
    public let unit: String
    public let amount: Double
    public let pieces: Double?
    public let nutrition: Nutrition
    public let cost: Cost
}

public struct DietDay: Equatable {
    public let date: ISODate
    public let hasPlan: Bool
    public let meals: [DietMeal]
    public let extras: [DietExtra]
    /// What the plan's items that are on today would give if all were ticked, before extras.
    public let planned: Nutrition
    /// Items that are on today, and how many of them are ticked.
    public let plannedCount: Int
    public let eatenCount: Int
    /// The ticked items alone.
    public let eatenNutrition: Nutrition
    public let extrasNutrition: Nutrition
    /// Ticked plan items plus extras: what the day counts as.
    public let total: Nutrition
    public let cost: Cost
    public let targets: DietTargets
}

/// An extra as the edit sheet reopens it: the food, the day, and the amount in the mode it is easiest to change.
public struct ExtraEntry: Equatable, Identifiable {
    public let id: Int
    public let foodID: Int
    public let date: ISODate
    public let mode: PortionMode
    public let value: Double
}

public struct ExtrasSummary: Equatable {
    public let days: Int
    public let nutrition: Nutrition
    public let cost: Cost
}

public struct RecentExtra: Equatable {
    public let foodID: Int
    public let name: String
    public let amount: Double
    public let pieces: Double?
}

public enum FatLimitSource: Equatable {
    case shareOfCalories
    case weightCap
}

/// A day measured against the protein minimum and the fat limit.
public struct DietTargets: Equatable {
    public let proteinMinimumGrams: Double
    public let proteinMet: Bool
    public let proteinShortBy: Double
    public let fatLimitGrams: Double
    public let fatLimitSource: FatLimitSource
    public let weightCapGrams: Double?
    public let fatOver: Bool

    private static let poundsPerKilogram = 2.2

    /// The fat limit is the smaller of the share of the day's calories and the cap from body weight (when weight is known).
    public static func evaluate(calories: Double, protein: Double, fat: Double, rules: DietRules, averageWeightKg: Double?) -> DietTargets {
        let share = rules.fatPercentOfCalories / 100 * calories / 9
        let cap = averageWeightKg.map { $0 * poundsPerKilogram * rules.fatCeilingGramsPerPound }
        let useCap = cap.map { $0 < share } ?? false
        let limit = useCap ? cap! : share
        return DietTargets(proteinMinimumGrams: rules.proteinMinimumGrams, proteinMet: protein >= rules.proteinMinimumGrams,
                           proteinShortBy: max(0, rules.proteinMinimumGrams - protein), fatLimitGrams: limit,
                           fatLimitSource: useCap ? .weightCap : .shareOfCalories, weightCapGrams: cap, fatOver: fat > limit)
    }
}
