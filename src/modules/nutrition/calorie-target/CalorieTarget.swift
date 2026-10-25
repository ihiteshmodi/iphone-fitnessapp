import Foundation

/// Pure port of the notebook's `CalorieTracker.caloriesdata`: no database, no clock.
public struct CalorieTarget: Equatable {
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

    public static func calculate(currentAverageKg: Double, pastAverageKg: Double, caloriesEaten: Double,
                                 multiplier: Double = 1, rules: MacroRules) -> CalorieTarget {
        let oneLbCalories = 3500.0
        let oneLbGrams = 454.0

        let weightDiffKg = currentAverageKg - pastAverageKg
        let weeklyCalorieDiff = (oneLbCalories * weightDiffKg * 1000) / oneLbGrams
        let dailyCalorieDiff = weeklyCalorieDiff / 7
        let maintenance = caloriesEaten - dailyCalorieDiff
        let adjustedTarget = Int(pyRound(maintenance * multiplier, 0))

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
            macros: multiplier < 1 ? macros(adjustedTarget: Double(adjustedTarget), currentAverageKg: currentAverageKg, rules: rules) : nil
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
