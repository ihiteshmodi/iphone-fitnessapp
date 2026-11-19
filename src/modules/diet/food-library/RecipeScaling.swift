import Foundation

/// Cooking a recipe for a different amount than it was saved for. Pure; nothing is stored.
public enum RecipeScaling {
    public static func cook(_ lines: [RecipeLine], makes: Double, for amount: Double) throws -> [RecipeLine] {
        guard amount.isFinite, amount > 0 else { throw ValidationError("Cook for an amount above 0") }
        guard makes.isFinite, makes > 0 else { throw ValidationError("The recipe must make an amount above 0") }
        return lines.map { RecipeLine(foodID: $0.foodID, quantity: $0.quantity * amount / makes) }
    }
}
