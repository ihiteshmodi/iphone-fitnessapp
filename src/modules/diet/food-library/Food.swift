import Foundation

public enum FoodKind: String, CaseIterable, Equatable {
    case food, topping, supplement, herb, liquid, packaged, recipe

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// What an amount of food gives. Calories are included so callers never redo the 4/4/9 rule.
public struct Nutrition: Equatable {
    public var calories = 0.0
    public var protein = 0.0
    public var carbs = 0.0
    public var fat = 0.0
    public var fiber = 0.0
    public var satFat = 0.0
    public var sodium = 0.0

    public static let zero = Nutrition()

    public init(calories: Double = 0, protein: Double = 0, carbs: Double = 0, fat: Double = 0,
                fiber: Double = 0, satFat: Double = 0, sodium: Double = 0) {
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.satFat = satFat
        self.sodium = sodium
    }

    public static func + (lhs: Nutrition, rhs: Nutrition) -> Nutrition {
        Nutrition(calories: lhs.calories + rhs.calories, protein: lhs.protein + rhs.protein, carbs: lhs.carbs + rhs.carbs,
                  fat: lhs.fat + rhs.fat, fiber: lhs.fiber + rhs.fiber, satFat: lhs.satFat + rhs.satFat, sodium: lhs.sodium + rhs.sodium)
    }

    public func scaled(by factor: Double) -> Nutrition {
        Nutrition(calories: calories * factor, protein: protein * factor, carbs: carbs * factor, fat: fat * factor,
                  fiber: fiber * factor, satFat: satFat * factor, sodium: sodium * factor)
    }
}

/// An amount of money, with a flag for "some of it has no price yet" so a missing price never looks like zero.
public struct Cost: Equatable {
    public var amount: Double
    public var isComplete: Bool

    public init(amount: Double, isComplete: Bool) {
        self.amount = amount
        self.isComplete = isComplete
    }

    public static let free = Cost(amount: 0, isComplete: true)

    public static func + (lhs: Cost, rhs: Cost) -> Cost {
        Cost(amount: lhs.amount + rhs.amount, isComplete: lhs.isComplete && rhs.isComplete)
    }

    public func scaled(by factor: Double) -> Cost { Cost(amount: amount * factor, isComplete: isComplete) }
}

public struct RecipeLine: Equatable {
    public let foodID: Int
    public let quantity: Double

    public init(foodID: Int, quantity: Double) {
        self.foodID = foodID
        self.quantity = quantity
    }
}

/// Everything about a food that the person can edit. Nutrition is for `baseQuantity` of `unit`.
public struct FoodDraft: Equatable {
    public var name: String
    public var kind: FoodKind
    public var unit: String
    public var baseQuantity: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var fiber: Double
    public var satFat: Double
    public var sodium: Double
    public var labelCalories: Double?
    public var price: Double?
    public var packSize: Double?
    public var piecesPerPack: Double?
    public var pieceWeight: Double?
    public var recipeMakes: Double?
    public var notes: String?

    public init(name: String, kind: FoodKind = .food, unit: String = "g", baseQuantity: Double = 100,
                protein: Double = 0, carbs: Double = 0, fat: Double = 0, fiber: Double = 0, satFat: Double = 0, sodium: Double = 0,
                labelCalories: Double? = nil, price: Double? = nil, packSize: Double? = nil,
                piecesPerPack: Double? = nil, pieceWeight: Double? = nil, recipeMakes: Double? = nil, notes: String? = nil) {
        self.name = name
        self.kind = kind
        self.unit = unit
        self.baseQuantity = baseQuantity
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fiber = fiber
        self.satFat = satFat
        self.sodium = sodium
        self.labelCalories = labelCalories
        self.price = price
        self.packSize = packSize
        self.piecesPerPack = piecesPerPack
        self.pieceWeight = pieceWeight
        self.recipeMakes = recipeMakes
        self.notes = notes
    }
}

public struct Food: Equatable, Identifiable {
    public let id: Int
    public let draft: FoodDraft

    public var name: String { draft.name }
    public var kind: FoodKind { draft.kind }
    public var unit: String { draft.unit }
    public var isRecipe: Bool { draft.kind == .recipe }

    /// Nutrition for `baseQuantity` of the unit, calories included (label value, else 4 x protein + 4 x carbs + 9 x fat).
    /// Not meaningful for a recipe, whose nutrition is worked out from its ingredients.
    public var perBase: Nutrition {
        Nutrition(calories: draft.labelCalories ?? (4 * draft.protein + 4 * draft.carbs + 9 * draft.fat),
                  protein: draft.protein, carbs: draft.carbs, fat: draft.fat,
                  fiber: draft.fiber, satFat: draft.satFat, sodium: draft.sodium)
    }
}
