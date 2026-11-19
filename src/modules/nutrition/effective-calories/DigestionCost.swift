import Foundation

/// Calories used just to digest a day's food (the thermic effect of food), by macro. The vault gives ranges
/// (protein 20-30 %, carbs 5-10 %, fat 0-3 %, no figure for alcohol); the owner chose the middle of each.
public struct DigestionCost: Equatable {
    public static let proteinShare = 0.25
    public static let carbShare = 0.075
    public static let fatShare = 0.015
    public static let alcoholShare = 0.0

    public let protein: Double
    public let carbs: Double
    public let fat: Double
    public let alcohol: Double

    /// From grams.
    public init(protein: Double, carbs: Double, fat: Double, alcohol: Double) {
        self.protein = protein * 4 * Self.proteinShare
        self.carbs = carbs * 4 * Self.carbShare
        self.fat = fat * 9 * Self.fatShare
        self.alcohol = alcohol * 7 * Self.alcoholShare
    }

    /// From calories already worked out per macro (averages of several days).
    public init(byCalories protein: Double, carbs: Double, fat: Double, alcohol: Double) {
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.alcohol = alcohol
    }

    public init(_ nutrition: Nutrition, alcoholGrams: Double = 0) {
        self.init(protein: nutrition.protein, carbs: nutrition.carbs, fat: nutrition.fat, alcohol: alcoholGrams)
    }

    public var total: Double { protein + carbs + fat + alcohol }

    public func effective(of calories: Double) -> Double { calories - total }
}

/// Effective calories over several days: the mean, the digestion share, and the cost of a typical day with macros.
public struct EffectiveCalories: Equatable {
    public let average: Double
    public let share: Double
    public let typicalDayCost: DigestionCost
}
