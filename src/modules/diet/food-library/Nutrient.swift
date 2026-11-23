import Foundation

public enum NutrientGroup: String, CaseIterable {
    case aminoAcids = "Amino acids"
    case fatTypes = "Fat types"
    case omega = "Omega-3 and omega-6"
    case alcoholCaffeine = "Alcohol and caffeine"
    case vitamins = "Vitamins"
    case minerals = "Minerals"
    case compounds = "Compounds & functional ingredients"
}

/// The nutrients tracked on top of calories, protein, carbs, fat, fiber, saturated fat and sodium.
/// Keys are stored as text, so the raw values must never change.
public enum Nutrient: String, CaseIterable, Hashable {
    case histidine, isoleucine, leucine, lysine, methionine, cystine, phenylalanine, threonine, tryptophan, tyrosine, valine
    case mufa, pufa, trans
    case epa, dha, ala, omega6
    case alcohol, caffeine
    case vitaminA = "vitamin_a", b1, b2, b3, b5, b6, b12, biotin, choline, folate
    case vitaminC = "vitamin_c", vitaminD = "vitamin_d", vitaminD3 = "vitamin_d3", vitaminE = "vitamin_e", vitaminK = "vitamin_k"
    case calcium, copper, iron, magnesium, manganese, phosphorus, potassium, selenium, zinc, boron
    case creatine, glycine, psyllium

    public var group: NutrientGroup {
        switch self {
        case .histidine, .isoleucine, .leucine, .lysine, .methionine, .cystine, .phenylalanine, .threonine, .tryptophan, .tyrosine, .valine:
            return .aminoAcids
        case .mufa, .pufa, .trans: return .fatTypes
        case .epa, .dha, .ala, .omega6: return .omega
        case .alcohol, .caffeine: return .alcoholCaffeine
        case .vitaminA, .b1, .b2, .b3, .b5, .b6, .b12, .biotin, .choline, .folate, .vitaminC, .vitaminD, .vitaminD3, .vitaminE, .vitaminK:
            return .vitamins
        case .calcium, .copper, .iron, .magnesium, .manganese, .phosphorus, .potassium, .selenium, .zinc, .boron: return .minerals
        case .creatine, .glycine, .psyllium: return .compounds
        }
    }

    public var unit: String {
        switch self {
        case .epa, .dha, .caffeine, .b1, .b2, .b3, .b5, .b6, .choline, .vitaminC, .vitaminE,
             .calcium, .copper, .iron, .magnesium, .manganese, .phosphorus, .potassium, .zinc, .boron:
            return "mg"
        case .vitaminA, .b12, .biotin, .folate, .vitaminD, .vitaminK, .selenium: return "mcg"
        case .vitaminD3: return "IU"
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
        case .vitaminD3: return "Vitamin D3"
        case .vitaminE: return "Vitamin E"
        case .vitaminK: return "Vitamin K"
        case .creatine: return "Creatine monohydrate"
        case .glycine: return "Glycine"
        case .psyllium: return "Psyllium husk"
        case .b1, .b2, .b3, .b5, .b6, .b12: return rawValue.uppercased()
        default: return rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }

    /// Daily targets shown in the Meridian app (USDA/FatSecret reference intakes, adult male), in `unit`.
    /// Nutrients with no target (fat types, EPA and DHA, ALA, omega-6, alcohol, caffeine) return nil; their rules live elsewhere.
    /// Omega-6 is left out because the vault gives no amount or ratio for it.
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
        case .creatine: return 3
        case .glycine: return 3
        case .psyllium: return 5
        default: return nil
        }
    }

    /// Recommended daily dose window for functional compounds (from the vault's supplement chapters).
    public var recommendedRange: ClosedRange<Double>? {
        switch self {
        case .creatine: return 3.0...5.0
        case .glycine: return 3.0...5.0
        case .psyllium: return 5.0...10.0
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
    public static let vitaminDIUPerMcg = 40.0

    public var values: [Nutrient: Double]
    public var unknown: Set<Nutrient>

    public init(values: [Nutrient: Double] = [:], unknown: Set<Nutrient> = []) {
        self.values = values
        self.unknown = unknown
    }

    public static let empty = NutrientProfile()

    public subscript(_ nutrient: Nutrient) -> Double? { values[nutrient] }

    /// Combined Vitamin D in mcg (`vitamin_d` + `vitamin_d3 / 40`), so D and D3 share one fat-soluble pool.
    public var totalVitaminDMcg: Double {
        (values[.vitaminD] ?? 0) + (values[.vitaminD3] ?? 0) / Self.vitaminDIUPerMcg
    }

    /// Combined Vitamin D in IU (`totalVitaminDMcg × 40`).
    public var totalVitaminDIU: Double {
        totalVitaminDMcg * Self.vitaminDIUPerMcg
    }

    public func effectiveAmount(of nutrient: Nutrient) -> Double? {
        if nutrient == .vitaminD {
            guard values[.vitaminD] != nil || values[.vitaminD3] != nil else { return nil }
            return totalVitaminDMcg
        }
        return values[nutrient]
    }

    public static func + (lhs: NutrientProfile, rhs: NutrientProfile) -> NutrientProfile {
        NutrientProfile(values: lhs.values.merging(rhs.values, uniquingKeysWith: +), unknown: lhs.unknown.union(rhs.unknown))
    }

    public func scaled(by factor: Double) -> NutrientProfile {
        NutrientProfile(values: values.mapValues { $0 * factor }, unknown: unknown)
    }

    /// A food's own values: what it has is known, the rest unknown. Entering `vitamin_d3` counts as knowing its Vitamin D.
    static func of(_ known: [Nutrient: Double]) -> NutrientProfile {
        var missing = Set(Nutrient.allCases).subtracting(known.keys)
        if known[.vitaminD3] != nil { missing.remove(.vitaminD) }
        return NutrientProfile(values: known, unknown: missing)
    }
}

/// A nutrient that has a daily target, against what was eaten. `amount` is nil when it is unknown.
public struct DailyTargetRow: Equatable {
    public let nutrient: Nutrient
    public let amount: Double?
    public let target: Double

    public init(nutrient: Nutrient, amount: Double?, target: Double) {
        self.nutrient = nutrient
        self.amount = amount
        self.target = target
    }

    public var share: Double? { amount.map { $0 / target } }
    public var isMet: Bool { (amount ?? 0) >= target }

    public var formattedProgress: String {
        let current = amount ?? 0
        if nutrient == .vitaminD {
            let iu = Int((current * NutrientProfile.vitaminDIUPerMcg).rounded())
            let targetIU = Int((target * NutrientProfile.vitaminDIUPerMcg).rounded())
            return "\(Self.clean(current)) mcg (\(Self.groupedInt(iu)) IU) / \(Self.clean(target)) mcg (\(Self.groupedInt(targetIU)) IU)"
        }
        if let range = nutrient.recommendedRange {
            return "\(Self.clean(current)) / \(Self.clean(range.lowerBound))–\(Self.clean(range.upperBound)) \(nutrient.unit)"
        }
        return "\(Self.clean(current)) / \(Self.clean(target)) \(nutrient.unit)"
    }

    private static func clean(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }

    private static func groupedInt(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

public enum DailyTargetReport {
    /// Every nutrient with a target, in the order of `Nutrient.allCases`. Unknown means at least one food had no value.
    public static func rows(_ profile: NutrientProfile) -> [DailyTargetRow] {
        Nutrient.allCases.compactMap { nutrient in
            nutrient.dailyTarget.map { target in
                let val = profile.effectiveAmount(of: nutrient) ?? 0
                let isUnknown = profile.unknown.contains(nutrient) && val < target
                return DailyTargetRow(nutrient: nutrient, amount: isUnknown ? nil : val, target: target)
            }
        }
    }

    /// Whole-day targets for DailyTargetsView: excludes amino acids (which are per-meal) and shows 0 instead of nil/unknown.
    public static func dailyRows(_ profile: NutrientProfile) -> [DailyTargetRow] {
        Nutrient.allCases.compactMap { nutrient in
            guard nutrient.group != .aminoAcids, let target = nutrient.dailyTarget else { return nil }
            return DailyTargetRow(nutrient: nutrient, amount: profile.effectiveAmount(of: nutrient) ?? 0, target: target)
        }
    }
}

extension Nutrient {
    /// Vitamins A, D, D3, E and K are stored in the body, so too much builds up rather than leaving in urine.
    public var isFatSoluble: Bool { [.vitaminA, .vitaminD, .vitaminD3, .vitaminE, .vitaminK].contains(self) }

    /// Daily upper limits as the vault states them, in `unit`. Nil where none is given or the vault gives two
    /// different values (see `upperLimitNote`); those are settled with bloodwork in Blood Labs.
    public var upperLimit: Double? {
        switch self {
        case .vitaminA: return 3000
        case .vitaminD: return 100
        case .vitaminD3: return 4000
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
        case .vitaminD, .vitaminD3: return "100 mcg (4,000 IU) combined Vitamin D + D3"
        default: return nil
        }
    }
}
