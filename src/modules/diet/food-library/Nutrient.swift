import Foundation

public enum NutrientGroup: String, CaseIterable {
    case aminoAcids = "Amino acids"
    case fatTypes = "Fat types"
    case omega = "Omega-3 and omega-6"
    case alcoholCaffeine = "Alcohol and caffeine"
    case vitamins = "Vitamins"
    case minerals = "Minerals"
}

/// The nutrients tracked on top of calories, protein, carbs, fat, fiber, saturated fat and sodium.
/// Keys are stored as text, so the raw values must never change.
public enum Nutrient: String, CaseIterable, Hashable {
    case histidine, isoleucine, leucine, lysine, methionine, cystine, phenylalanine, threonine, tryptophan, tyrosine, valine
    case mufa, pufa, trans
    case epa, dha, ala, omega6
    case alcohol, caffeine
    case vitaminA = "vitamin_a", b1, b2, b3, b5, b6, b12, biotin, choline, folate
    case vitaminC = "vitamin_c", vitaminD = "vitamin_d", vitaminE = "vitamin_e", vitaminK = "vitamin_k"
    case calcium, copper, iron, magnesium, manganese, phosphorus, potassium, selenium, zinc, boron

    public var group: NutrientGroup {
        switch self {
        case .histidine, .isoleucine, .leucine, .lysine, .methionine, .cystine, .phenylalanine, .threonine, .tryptophan, .tyrosine, .valine:
            return .aminoAcids
        case .mufa, .pufa, .trans: return .fatTypes
        case .epa, .dha, .ala, .omega6: return .omega
        case .alcohol, .caffeine: return .alcoholCaffeine
        case .vitaminA, .b1, .b2, .b3, .b5, .b6, .b12, .biotin, .choline, .folate, .vitaminC, .vitaminD, .vitaminE, .vitaminK: return .vitamins
        case .calcium, .copper, .iron, .magnesium, .manganese, .phosphorus, .potassium, .selenium, .zinc, .boron: return .minerals
        }
    }

    public var unit: String {
        switch self {
        case .epa, .dha, .caffeine, .b1, .b2, .b3, .b5, .b6, .choline, .vitaminC, .vitaminE,
             .calcium, .copper, .iron, .magnesium, .manganese, .phosphorus, .potassium, .zinc, .boron:
            return "mg"
        case .vitaminA, .b12, .biotin, .folate, .vitaminD, .vitaminK, .selenium: return "mcg"
        default: return "g"
        }
    }

    public var title: String {
        switch self {
        case .mufa: return "Monounsaturated (MUFA)"
        case .pufa: return "Polyunsaturated (PUFA)"
        case .trans: return "Trans fat"
        case .epa: return "EPA"
        case .dha: return "DHA"
        case .ala: return "ALA (plant omega-3)"
        case .omega6: return "Omega-6"
        case .vitaminA: return "Vitamin A"
        case .vitaminC: return "Vitamin C"
        case .vitaminD: return "Vitamin D"
        case .vitaminE: return "Vitamin E"
        case .vitaminK: return "Vitamin K"
        case .b1, .b2, .b3, .b5, .b6, .b12: return rawValue.uppercased()
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Daily targets shown in the Meridian app (USDA/FatSecret reference intakes, adult male), in `unit`.
    /// Nutrients with no target (fat types, EPA and DHA, ALA, alcohol, caffeine) return nil; their rules live elsewhere.
    public var dailyTarget: Double? {
        switch self {
        case .histidine: return 1
        case .isoleucine: return 1.3
        case .leucine: return 2.9
        case .lysine: return 2.7
        case .methionine: return 1.3
        case .cystine: return 0.6
        case .phenylalanine: return 2.3
        case .threonine: return 1.4
        case .tryptophan: return 0.4
        case .tyrosine: return 1.4
        case .valine: return 1.7
        case .omega6: return 17
        case .vitaminA: return 900
        case .b1: return 1.2
        case .b2: return 1.3
        case .b3: return 16
        case .b5: return 5
        case .b6: return 1.3
        case .b12: return 2.4
        case .biotin: return 30
        case .choline: return 550
        case .folate: return 400
        case .vitaminC: return 90
        case .vitaminD: return 20
        case .vitaminE: return 15
        case .vitaminK: return 120
        case .calcium: return 1000
        case .copper: return 0.9
        case .iron: return 18
        case .magnesium: return 420
        case .manganese: return 2.3
        case .phosphorus: return 700
        case .potassium: return 2600
        case .selenium: return 55
        case .zinc: return 11
        default: return nil
        }
    }

    /// Fiber is a column of its own; its daily reference sits here with the others.
    public static let fiberDailyTarget = 28.0
    public static let omega3DailyTargetGrams = 1.6
}

public enum Omega3Form: String, CaseIterable, Equatable {
    case reEsterifiedTriglyceride = "rTG"
    case triglyceride = "TG"
    case ethylEster = "EE"
    case algae
    case unknown
}

/// Amounts of the extra nutrients in a portion. A nutrient that one of the foods has no value for is `unknown`
/// (its sum covers only the foods that do), so a missing value is never read as 0.
public struct NutrientProfile: Equatable {
    public var values: [Nutrient: Double]
    public var unknown: Set<Nutrient>

    public init(values: [Nutrient: Double] = [:], unknown: Set<Nutrient> = []) {
        self.values = values
        self.unknown = unknown
    }

    public static let empty = NutrientProfile()

    public subscript(_ nutrient: Nutrient) -> Double? { values[nutrient] }

    public static func + (lhs: NutrientProfile, rhs: NutrientProfile) -> NutrientProfile {
        NutrientProfile(values: lhs.values.merging(rhs.values, uniquingKeysWith: +), unknown: lhs.unknown.union(rhs.unknown))
    }

    public func scaled(by factor: Double) -> NutrientProfile {
        NutrientProfile(values: values.mapValues { $0 * factor }, unknown: unknown)
    }

    /// A food's own values: what it has is known, the rest unknown.
    static func of(_ known: [Nutrient: Double]) -> NutrientProfile {
        NutrientProfile(values: known, unknown: Set(Nutrient.allCases).subtracting(known.keys))
    }
}

/// A nutrient that has a daily target, against what was eaten. `amount` is nil when it is unknown.
public struct DailyTargetRow: Equatable {
    public let nutrient: Nutrient
    public let amount: Double?
    public let target: Double

    public var share: Double? { amount.map { $0 / target } }
    public var isMet: Bool { (amount ?? 0) >= target }
}

public enum DailyTargetReport {
    /// Every nutrient with a target, in the order of `Nutrient.allCases`. Unknown means at least one food had no value.
    public static func rows(_ profile: NutrientProfile) -> [DailyTargetRow] {
        Nutrient.allCases.compactMap { nutrient in
            nutrient.dailyTarget.map { target in
                DailyTargetRow(nutrient: nutrient, amount: profile.unknown.contains(nutrient) && (profile[nutrient] ?? 0) < target ? nil : (profile[nutrient] ?? 0),
                               target: target)
            }
        }
    }
}

extension Nutrient {
    /// Vitamins A, D, E and K are stored in the body, so too much builds up rather than leaving in urine.
    public var isFatSoluble: Bool { [.vitaminA, .vitaminD, .vitaminE, .vitaminK].contains(self) }

    /// Daily upper limits as the vault states them, in `unit`. Nil where none is given or the vault gives two
    /// different values (see `upperLimitNote`); those are settled with bloodwork in Blood Labs.
    public var upperLimit: Double? {
        switch self {
        case .vitaminA: return 3000
        case .vitaminD: return 100
        case .vitaminE: return 1000
        case .vitaminC: return 2000
        case .b3: return 35
        case .folate: return 1000
        case .magnesium: return 350
        case .zinc: return 40
        case .copper: return 10
        case .iron: return 45
        case .selenium: return 400
        case .manganese: return 11
        case .boron: return 20
        default: return nil
        }
    }

    public var upperLimitNote: String? {
        switch self {
        case .b6: return "100 mg (US) or 12 mg (EU)"
        case .magnesium: return "350 mg from supplements"
        case .iron: return "45 mg from supplements"
        case .folate: return "1,000 mcg of folic acid"
        case .vitaminA: return "3,000 mcg of preformed vitamin A"
        default: return nil
        }
    }
}
