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
    /// Extra nutrients the line would give if eaten.
    public var profile = NutrientProfile.empty
    public var kind: FoodKind = .food
    public var glycemicLoad: Double = 0
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
    public var ateAt: String? = nil

    private var tickable: [DietLine] { lines.filter { if case .offCycle = $0.state { return false } else { return true } } }

    public var eatenCalories: Double { lines.filter { $0.state == .eaten }.reduce(0) { $0 + $1.nutrition.calories } }
    /// What the ticked items give, protein included; for per-meal rules such as leucine.
    public var eatenNutrition: Nutrition { lines.filter { $0.state == .eaten }.reduce(Nutrition.zero) { $0 + $1.nutrition } }
    public var eatenProfile: NutrientProfile { lines.filter { $0.state == .eaten }.reduce(NutrientProfile.empty) { $0 + $1.profile } }
    /// The meal as planned with everything on today ticked: for checking the plan itself.
    public var plannedNutrition: Nutrition { tickable.reduce(Nutrition.zero) { $0 + $1.nutrition } }
    public var plannedProfile: NutrientProfile { tickable.reduce(NutrientProfile.empty) { $0 + $1.profile } }
    /// What the meal would give with everything that is on today ticked.
    public var plannedCalories: Double { tickable.reduce(0) { $0 + $1.nutrition.calories } }
    public var eatenGlycemicLoad: Double { lines.filter { $0.state == .eaten }.reduce(0) { $0 + $1.glycemicLoad } }
    public var plannedGlycemicLoad: Double { tickable.reduce(0) { $0 + $1.glycemicLoad } }
    /// False when every item is off its cycle today, so there is nothing to tick.
    public var canTick: Bool { !tickable.isEmpty }

    /// True on real food meals (e.g. Brunch, Dinner); false on supplement/electrolyte-only slots (e.g. Morning Psyllium, During workout salts).
    public var isRealMeal: Bool {
        let netCarbs = max(0, plannedNutrition.carbs - plannedNutrition.fiber)
        if plannedNutrition.protein >= 5 || netCarbs >= 5 { return true }
        return tickable.contains { $0.kind != .supplement && $0.kind != .herb && $0.kind != .liquid && $0.nutrition.calories >= 25 }
    }

    public var tickState: MealTickState {
        let ticked = tickable.filter { $0.state == .eaten }.count
        if ticked == 0 { return .none }
        return ticked == tickable.count ? .all : .some
    }
}

public enum ExtraTime: String, CaseIterable, Equatable {
    case morning, noon, evening, night

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// What the person adds to an extra on top of the food and amount: all optional.
public struct ExtraDetails: Equatable {
    public var label: String?
    public var time: ExtraTime?
    public var ateAt: String?
    public var note: String?

    public init(label: String? = nil, time: ExtraTime? = nil, ateAt: String? = nil, note: String? = nil) {
        self.label = Self.clean(label)
        self.time = time
        self.ateAt = Self.clean(ateAt)
        self.note = Self.clean(note)
    }

    private static func clean(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
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
    public var details = ExtraDetails()
    public var profile = NutrientProfile.empty

    /// The extra's own name when it has one (street food logged against a preset), else the food's.
    public var displayName: String { details.label ?? name }
    public var ateAt: String? { details.ateAt }
}

/// A planned meal on a past day with nothing ticked and no answer yet.
public struct UnconfirmedMeal: Equatable, Hashable {
    public let date: ISODate
    public let meal: String
}

public struct ExtraGroup: Equatable {
    public let time: ExtraTime?
    public let extras: [DietExtra]
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
    /// The planned day against the same rules: the fat range to aim for before the day is eaten.
    public let planTargets: DietTargets

    /// Extra nutrients of what counts today: ticked items plus extras.
    public var eatenProfile: NutrientProfile {
        meals.reduce(NutrientProfile.empty) { $0 + $1.eatenProfile } + extras.reduce(NutrientProfile.empty) { $0 + $1.profile }
    }

    /// Extra nutrients across all active planned meals on this day (ignoring tick state).
    public var plannedProfile: NutrientProfile {
        meals.reduce(NutrientProfile.empty) { $0 + $1.plannedProfile }
    }

    /// Morning, noon, evening, night, then extras with no time; empty groups left out.
    public var extrasByTime: [ExtraGroup] {
        (ExtraTime.allCases.map(Optional.some) + [nil]).compactMap { time in
            let matching = extras.filter { $0.details.time == time }
            return matching.isEmpty ? nil : ExtraGroup(time: time, extras: matching)
        }
    }
}

/// An extra as the edit sheet reopens it: the food, the day, and the amount in the mode it is easiest to change.
public struct ExtraEntry: Equatable, Identifiable {
    public let id: Int
    public let foodID: Int
    public let date: ISODate
    public let mode: PortionMode
    public let value: Double
    public var details = ExtraDetails()
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

public enum FatMinimumSource: Equatable {
    case shareOfCalories
    case bodyWeight
}

/// A day measured against the protein minimum and the fat range.
public struct DietTargets: Equatable {
    public let proteinMinimumGrams: Double
    public let proteinMet: Bool
    public let proteinShortBy: Double
    /// The bottom of the range: the larger of the lowest share of calories and the floor from body weight.
    public let fatMinimumGrams: Double
    public let fatMinimumSource: FatMinimumSource
    public let fatMaximumGrams: Double
    /// Floor from the 7-day average weight; nil without weigh-ins.
    public let fatFloorGrams: Double?
    public let fatUnder: Bool
    public let fatOver: Bool

    public static func evaluate(calories: Double, protein: Double, fat: Double, rules: DietRules, averageWeightKg: Double?) -> DietTargets {
        let share = rules.fatMinPercent / 100 * calories / 9
        let floor = averageWeightKg.map { $0 * rules.fatFloorGramsPerKg }
        let floorWins = floor.map { $0 > share } ?? false
        let minimum = floorWins ? floor! : share
        let maximum = max(rules.fatMaxPercent / 100 * calories / 9, minimum)
        return DietTargets(proteinMinimumGrams: rules.proteinMinimumGrams, proteinMet: protein >= rules.proteinMinimumGrams,
                           proteinShortBy: max(0, rules.proteinMinimumGrams - protein),
                           fatMinimumGrams: minimum, fatMinimumSource: floorWins ? .bodyWeight : .shareOfCalories,
                           fatMaximumGrams: maximum, fatFloorGrams: floor, fatUnder: fat < minimum, fatOver: fat > maximum)
    }
}
