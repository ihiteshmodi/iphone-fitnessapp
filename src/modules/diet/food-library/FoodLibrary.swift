import Foundation

/// Foods, supplements and recipes, with their nutrition and price. The one place that reads and writes the `foods` tables.
public final class FoodLibrary {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    // MARK: Read

    public func food(_ id: Int) throws -> Food? {
        try db.query("SELECT * FROM foods WHERE id = ?", [.int(Int64(id))]).first.map(Self.food)
    }

    public func food(named name: String) throws -> Food? {
        try db.query("SELECT * FROM foods WHERE name = ?", [.text(name)]).first.map(Self.food)
    }

    /// Name order. `matching` is a part of the name; empty returns everything.
    public func foods(matching text: String = "", kind: FoodKind? = nil) throws -> [Food] {
        var sql = "SELECT * FROM foods WHERE name LIKE ?"
        var params: [SQLValue] = [.text("%\(text.trimmingCharacters(in: .whitespaces))%")]
        if let kind {
            sql += " AND kind = ?"
            params.append(.text(kind.rawValue))
        }
        return try db.query(sql + " ORDER BY name COLLATE NOCASE", params).map(Self.food)
    }

    public func ingredients(of recipeID: Int) throws -> [RecipeLine] {
        try db.query("SELECT food_id, quantity FROM recipe_items WHERE recipe_id = ? ORDER BY position",
                     [.int(Int64(recipeID))]).map { RecipeLine(foodID: $0.int("food_id"), quantity: $0.double("quantity")) }
    }

    /// Every food and recipe line in memory, for adding up a whole day.
    public func book() throws -> FoodBook {
        let foods = Dictionary(uniqueKeysWithValues: try db.query("SELECT * FROM foods").map { Self.food($0) }.map { ($0.id, $0) })
        var lines: [Int: [RecipeLine]] = [:]
        for row in try db.query("SELECT recipe_id, food_id, quantity FROM recipe_items ORDER BY recipe_id, position") {
            lines[row.int("recipe_id"), default: []].append(RecipeLine(foodID: row.int("food_id"), quantity: row.double("quantity")))
        }
        return FoodBook(foods: foods, lines: lines)
    }

    public func nutrition(of id: Int, quantity: Double) throws -> Nutrition { try book().nutrition(of: id, quantity: quantity) }

    public func cost(of id: Int, quantity: Double) throws -> Cost { try book().cost(of: id, quantity: quantity) }

    // MARK: Write

    @discardableResult
    public func add(_ draft: FoodDraft) throws -> Int {
        try validate(draft)
        try requireUniqueName(draft.name, except: nil)
        try db.execute("""
            INSERT INTO foods (name, kind, unit, base_qty, protein, carbs, fat, fiber, sat_fat, sodium, label_calories,
                               price, pack_size, pieces_per_pack, piece_weight, recipe_makes, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, Self.values(draft))
        return db.lastInsertRowID
    }

    public func update(_ id: Int, _ draft: FoodDraft) throws {
        try validate(draft)
        try requireUniqueName(draft.name, except: id)
        try db.execute("""
            UPDATE foods SET name = ?, kind = ?, unit = ?, base_qty = ?, protein = ?, carbs = ?, fat = ?, fiber = ?, sat_fat = ?,
                             sodium = ?, label_calories = ?, price = ?, pack_size = ?, pieces_per_pack = ?, piece_weight = ?,
                             recipe_makes = ?, notes = ?
            WHERE id = ?
            """, Self.values(draft) + [.int(Int64(id))])
    }

    public func delete(_ id: Int) throws {
        guard let food = try food(id) else { return }
        let used = try db.query("""
            SELECT (SELECT COUNT(*) FROM recipe_items WHERE food_id = ?1)
                 + (SELECT COUNT(*) FROM diet_plan_items WHERE food_id = ?1)
                 + (SELECT COUNT(*) FROM diet_extras WHERE food_id = ?1) AS n
            """, [.int(Int64(id))]).first?.int("n") ?? 0
        guard used == 0 else { throw ValidationError("\(food.name) is used by a recipe, a plan or a logged day") }
        try db.execute("DELETE FROM foods WHERE id = ?", [.int(Int64(id))])
    }

    /// Replaces the ingredients of a recipe, in the order given.
    public func setIngredients(of recipeID: Int, _ lines: [RecipeLine]) throws {
        guard let recipe = try food(recipeID), recipe.isRecipe else { throw ValidationError("Only a recipe has ingredients") }
        guard lines.allSatisfy({ $0.quantity.isFinite && $0.quantity > 0 }) else { throw ValidationError("Enter a quantity above 0") }
        guard Set(lines.map(\.foodID)).count == lines.count else { throw ValidationError("An ingredient is listed twice") }
        let book = try book()
        for line in lines {
            guard book.food(line.foodID) != nil else { throw ValidationError("That food is not in the library") }
            guard !Self.reaches(recipeID, from: line.foodID, in: book) else { throw ValidationError("A recipe cannot contain itself") }
        }
        try db.transaction {
            try db.execute("DELETE FROM recipe_items WHERE recipe_id = ?", [.int(Int64(recipeID))])
            for (index, line) in lines.enumerated() {
                try db.execute("INSERT INTO recipe_items (recipe_id, food_id, position, quantity) VALUES (?, ?, ?, ?)",
                               [.int(Int64(recipeID)), .int(Int64(line.foodID)), .int(Int64(index + 1)), .double(line.quantity)])
            }
        }
    }

    // MARK: Private

    /// True when `target` is `start` itself or sits anywhere inside the recipe `start`.
    private static func reaches(_ target: Int, from start: Int, in book: FoodBook) -> Bool {
        guard start != target else { return true }
        return (book.lines[start] ?? []).contains { reaches(target, from: $0.foodID, in: book) }
    }

    private func validate(_ draft: FoodDraft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespaces).isEmpty else { throw ValidationError("Give the food a name") }
        guard draft.baseQuantity.isFinite, draft.baseQuantity > 0 else { throw ValidationError("Nutrition must be per a quantity above 0") }
        let nutrients = [draft.protein, draft.carbs, draft.fat, draft.fiber, draft.satFat, draft.sodium] + [draft.labelCalories].compactMap { $0 }
        guard nutrients.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw ValidationError("Nutrition cannot be negative") }
        if let price = draft.price { guard price.isFinite, price >= 0 else { throw ValidationError("Price cannot be negative") } }
        for size in [draft.packSize, draft.piecesPerPack, draft.pieceWeight, draft.recipeMakes].compactMap({ $0 }) {
            guard size.isFinite, size > 0 else { throw ValidationError("Sizes must be above 0") }
        }
    }

    private func requireUniqueName(_ name: String, except id: Int?) throws {
        let clash = try db.query("SELECT id FROM foods WHERE name = ?", [.text(name.trimmingCharacters(in: .whitespaces))]).first
        if let clash, clash.int("id") != id { throw ValidationError("A food with that name already exists") }
    }

    private static func values(_ draft: FoodDraft) -> [SQLValue] {
        [.text(draft.name.trimmingCharacters(in: .whitespaces)), .text(draft.kind.rawValue), .text(draft.unit), .double(draft.baseQuantity),
         .double(draft.protein), .double(draft.carbs), .double(draft.fat), .double(draft.fiber), .double(draft.satFat), .double(draft.sodium),
         .optional(draft.labelCalories), .optional(draft.price), .optional(draft.packSize), .optional(draft.piecesPerPack),
         .optional(draft.pieceWeight), .optional(draft.recipeMakes), .optional(draft.notes)]
    }

    private static func food(_ row: Row) -> Food {
        Food(id: row.int("id"), draft: FoodDraft(
            name: row.text("name"), kind: FoodKind(rawValue: row.text("kind")) ?? .food, unit: row.text("unit"),
            baseQuantity: row.double("base_qty"), protein: row.double("protein"), carbs: row.double("carbs"), fat: row.double("fat"),
            fiber: row.double("fiber"), satFat: row.double("sat_fat"), sodium: row.double("sodium"),
            labelCalories: row.optionalDouble("label_calories"), price: row.optionalDouble("price"), packSize: row.optionalDouble("pack_size"),
            piecesPerPack: row.optionalDouble("pieces_per_pack"), pieceWeight: row.optionalDouble("piece_weight"),
            recipeMakes: row.optionalDouble("recipe_makes"), notes: row.optionalText("notes")))
    }
}
