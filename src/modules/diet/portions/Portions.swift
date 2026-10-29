import Foundation

/// How an amount of food is typed in.
public enum PortionInput: Equatable {
    case pieces(Double)
    /// An amount in the food's own unit (grams for a packet).
    case amount(Double)
    case shareOfPack(Double)
}

/// An amount in the food's own unit, with the number of pieces it is when that is known.
public struct Portion: Equatable {
    public let amount: Double
    public let pieces: Double?
}

/// Turns "4 biscuits" or "half the pack" into the amount nutrition is worked out from. Pure; nothing is stored.
public enum Portions {
    private static let weightUnits: Set<String> = ["g", "ml"]

    /// What one piece weighs: the weight typed in, else the pack divided by the pieces in it.
    public static func pieceWeight(of food: Food) -> Double? {
        if let typed = food.draft.pieceWeight { return typed }
        guard let pack = food.draft.packSize, let pieces = food.draft.piecesPerPack else { return nil }
        return pack / pieces
    }

    public static func portion(of food: Food, _ input: PortionInput) throws -> Portion {
        let value: Double
        switch input {
        case .pieces(let n), .amount(let n), .shareOfPack(let n): value = n
        }
        guard value.isFinite, value > 0 else { throw ValidationError("Enter an amount above 0") }

        switch input {
        case .amount:
            return Portion(amount: value, pieces: pieces(in: value, of: food))
        case .pieces:
            if let weight = pieceWeight(of: food) { return Portion(amount: value * weight, pieces: value) }
            guard !weightUnits.contains(food.draft.unit) else { throw ValidationError("\(food.name) has no piece size") }
            return Portion(amount: value, pieces: value)
        case .shareOfPack:
            guard let pack = food.draft.packSize else { throw ValidationError("\(food.name) has no pack size") }
            return Portion(amount: value * pack, pieces: pieces(in: value * pack, of: food))
        }
    }

    /// How many pieces an amount is, when the food has a piece size or is counted in pieces itself.
    public static func pieces(in amount: Double, of food: Food) -> Double? {
        if let weight = pieceWeight(of: food) { return amount / weight }
        return weightUnits.contains(food.draft.unit) ? nil : amount
    }

    // MARK: Entry modes

    /// The ways an amount of this food can be typed. A food counted in pieces already is its own count, so it offers just that.
    public static func modes(for food: Food) -> [PortionMode] {
        guard weightUnits.contains(food.draft.unit) else { return [.amount] }
        var modes: [PortionMode] = []
        if pieceWeight(of: food) != nil { modes.append(.pieces) }
        modes.append(.amount)
        if food.draft.packSize != nil { modes.append(.shareOfPack) }
        return modes
    }

    public static func defaultValue(_ mode: PortionMode, for food: Food) -> Double {
        switch mode {
        case .pieces: return 1
        case .amount: return weightUnits.contains(food.draft.unit) ? 30 : 1
        case .shareOfPack: return 0.25
        }
    }

    public static func step(_ mode: PortionMode, for food: Food) -> Double {
        switch mode {
        case .pieces: return 1
        case .amount: return weightUnits.contains(food.draft.unit) ? 5 : 1
        case .shareOfPack: return 0.25
        }
    }

    public static func input(_ mode: PortionMode, _ value: Double) -> PortionInput {
        switch mode {
        case .pieces: return .pieces(value)
        case .amount: return .amount(value)
        case .shareOfPack: return .shareOfPack(value)
        }
    }
}

public enum PortionMode: Equatable {
    case pieces
    case amount
    case shareOfPack
}
