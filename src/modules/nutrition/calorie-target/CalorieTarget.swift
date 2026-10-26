import Foundation

public enum EnergyBalance: String, Equatable {
    case deficit = "Deficit"
    case maintenance = "Maintenance"
    case surplus = "Surplus"
}

/// What the multiplier says the lifter is aiming for.
public enum PlannedMode: String, Equatable {
    case cut = "Cut"
    case maintain = "Maintain"
    case bulk = "Bulk"

    public init(multiplier: Double) {
        if multiplier < 1 { self = .cut } else if multiplier > 1 { self = .bulk } else { self = .maintain }
    }
}

/// Pure port of the notebook's `CalorieTracker.caloriesdata`: no database, no clock.
public struct CalorieTarget: Equatable {
    /// A weight change worth less than this many calories a day is treated as holding weight.
    public static let maintenanceBandKcal = 100.0

    public enum Phase: String, Equatable {
        case cut = "Cut"
        case maintenanceOrBulk = "Maintenance / Bulk"
    }

    public struct Macros: Equatable {
        public let proteinGrams: Double
        public let proteinCalories: Double
        public let fatGrams: Double
        public let fatCalories: Double
        public let carbsGrams: Double
        public let carbsCalories: Double
    }

    public let currentAverageKg: Double
    public let pastAverageKg: Double
    public let caloriesEaten: Double
    public let multiplier: Double
    /// Rounded to 2 decimals for display.
    public let maintenanceCalories: Double
    public let phase: Phase
    /// Size of the daily surplus (phase is bulk) or deficit (phase is cut), 2 decimals.
    public let dailyDeficitOrSurplus: Double
    /// Whole calories per day to eat from now on.
    public let adjustedTarget: Int
    /// What the notebook prints as "Surplus"/"Deficit": calories eaten minus the new target.
    public let currentVersusTarget: Double
    /// Only present when the multiplier is below 1 (a cut).
    public let macros: Macros?
    /// What the weight trend says happened: calories a day above (+) or below (-) maintenance, whole calories.
    public let dailyBalanceKcal: Double
    public let balance: EnergyBalance
    public let plannedMode: PlannedMode

    public static func calculate(currentAverageKg: Double, pastAverageKg: Double, caloriesEaten: Double,
                                 multiplier: Double = 1, rules: MacroRules) -> CalorieTarget {
        let oneLbCalories = 3500.0
        let oneLbGrams = 454.0

        let weightDiffKg = currentAverageKg - pastAverageKg
        let weeklyCalorieDiff = (oneLbCalories * weightDiffKg * 1000) / oneLbGrams
        let dailyCalorieDiff = weeklyCalorieDiff / 7
        let maintenance = caloriesEaten - dailyCalorieDiff
        let adjustedTarget = Int(pyRound(maintenance * multiplier, 0))
        let dailyBalance = pyRound(dailyCalorieDiff, 0)
        let balance: EnergyBalance = abs(dailyCalorieDiff) <= maintenanceBandKcal ? .maintenance : (dailyCalorieDiff > 0 ? .surplus : .deficit)

        return CalorieTarget(
            currentAverageKg: currentAverageKg,
            pastAverageKg: pastAverageKg,
            caloriesEaten: caloriesEaten,
            multiplier: multiplier,
            maintenanceCalories: pyRound(maintenance, 2),
            phase: weightDiffKg > 0 ? .maintenanceOrBulk : .cut,
            dailyDeficitOrSurplus: pyRound(abs(dailyCalorieDiff), 2),
            adjustedTarget: adjustedTarget,
            currentVersusTarget: pyRound(caloriesEaten - Double(adjustedTarget), 2),
            macros: multiplier < 1 ? macros(adjustedTarget: Double(adjustedTarget), currentAverageKg: currentAverageKg, rules: rules) : nil,
            dailyBalanceKcal: dailyBalance == 0 ? 0 : dailyBalance,
            balance: balance,
            plannedMode: PlannedMode(multiplier: multiplier)
        )
    }

    private static func macros(adjustedTarget: Double, currentAverageKg: Double, rules: MacroRules) -> Macros {
        let proteinGrams = pyRound((currentAverageKg * 2.2) * rules.proteinGramsPerLb, 2)
        let proteinCalories = pyRound(proteinGrams * 4, 2)
        let fatCalories = pyRound(adjustedTarget * rules.fatPercent / 100, 2)
        let fatGrams = pyRound(fatCalories / 9, 2)
        let carbsCalories = pyRound(adjustedTarget - (proteinCalories + fatCalories), 2)
        let carbsGrams = pyRound(carbsCalories / 4, 2)
        return Macros(proteinGrams: proteinGrams, proteinCalories: proteinCalories, fatGrams: fatGrams,
                      fatCalories: fatCalories, carbsGrams: carbsGrams, carbsCalories: carbsCalories)
    }
}
