import Foundation

public struct SavedDiet: Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let savedOn: ISODate
    public let meals: [PlanMeal]
    /// Every item at its full quantity, cycles ignored: what the diet gives on a day everything is on.
    public let nutrition: Nutrition
    /// True when the plan in force on the day asked about has exactly these items.
    public let isInForce: Bool

    public var mealCount: Int { meals.count }
    public var itemCount: Int { meals.reduce(0) { $0 + $1.items.count } }
}

/// Whole diets kept under a name. Using one copies it into the plan from a date, like any other plan change.
public final class SavedDietService {
    private let db: Database
    private let plans: DietPlanService
    private let library: FoodLibrary

    public init(_ db: Database) {
        self.db = db
        plans = DietPlanService(db)
        library = FoodLibrary(db)
    }

    /// By name.
    public func all(inForceOn day: ISODate) throws -> [SavedDiet] {
        let current = try plans.plan(inForceOn: day).map { Self.signature($0.items) }
        let book = try library.book()
        return try db.query("SELECT id, name, saved_on FROM saved_diets ORDER BY name COLLATE NOCASE").compactMap { row in
            guard let savedOn = ISODate(row.text("saved_on")) else { return nil }
            let items = try self.items(of: row.int("id"))
            let nutrition = try items.reduce(Nutrition.zero) { $0 + (try book.nutrition(of: $1.foodID, quantity: $1.quantity)) }
            return SavedDiet(id: row.int("id"), name: row.text("name"), savedOn: savedOn,
                             meals: DietPlan(effectiveFrom: savedOn, items: items).meals, nutrition: nutrition,
                             isInForce: current == Self.signature(items))
        }
    }

    @discardableResult
    public func saveCurrent(as name: String, on day: ISODate) throws -> Int {
        let name = try validName(name, except: nil)
        guard let plan = try plans.plan(inForceOn: day), !plan.items.isEmpty else {
            throw ValidationError("There is no diet plan on that day to save")
        }
        return try db.transaction {
            try db.execute("INSERT INTO saved_diets (name, saved_on) VALUES (?, ?)", [.text(name), .text(day.string)])
            let id = db.lastInsertRowID
            for (index, item) in plan.items.enumerated() {
                let c = item.cycle.columns
                try db.execute("""
                    INSERT INTO saved_diet_items (diet_id, meal, position, food_id, quantity, cycle_mode, cycle_on, cycle_off, cycle_start, cycle_weekdays)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [.int(Int64(id)), .text(item.meal), .int(Int64(index + 1)), .int(Int64(item.foodID)), .double(item.quantity),
                          .text(c.mode), .optional(c.on), .optional(c.off), .optional(c.start), .optional(c.weekdays)])
            }
            return id
        }
    }

    /// The plan from `day` becomes this diet; earlier days keep theirs.
    public func use(_ id: Int, from day: ISODate) throws {
        guard try !db.query("SELECT 1 FROM saved_diets WHERE id = ?", [.int(Int64(id))]).isEmpty else {
            throw ValidationError("That saved diet is no longer there")
        }
        try db.transaction {
            try db.execute("INSERT OR IGNORE INTO diet_plans (effective_from) VALUES (?)", [.text(day.string)])
            try db.execute("DELETE FROM diet_plan_items WHERE plan_from = ?", [.text(day.string)])
            try db.execute("""
                INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity, cycle_mode, cycle_on, cycle_off, cycle_start, cycle_weekdays)
                SELECT ?, meal, position, food_id, quantity, cycle_mode, cycle_on, cycle_off, cycle_start, cycle_weekdays
                FROM saved_diet_items WHERE diet_id = ? ORDER BY position
                """, [.text(day.string), .int(Int64(id))])
        }
    }

    public func rename(_ id: Int, to name: String) throws {
        let name = try validName(name, except: id)
        try db.execute("UPDATE saved_diets SET name = ? WHERE id = ?", [.text(name), .int(Int64(id))])
    }

    public func delete(_ id: Int) throws {
        try db.execute("DELETE FROM saved_diets WHERE id = ?", [.int(Int64(id))])
    }

    // MARK: Private

    private func validName(_ name: String, except id: Int?) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw ValidationError("Give the diet a name") }
        if let clash = try db.query("SELECT id FROM saved_diets WHERE name = ? COLLATE NOCASE", [.text(trimmed)]).first, clash.int("id") != id {
            throw ValidationError("A saved diet with that name already exists")
        }
        return trimmed
    }

    private func items(of id: Int) throws -> [PlanItem] {
        try db.query("SELECT rowid, * FROM saved_diet_items WHERE diet_id = ? ORDER BY position", [.int(Int64(id))]).compactMap { row in
            let columns = CycleColumns(mode: row.text("cycle_mode"), on: row.optionalInt("cycle_on"), off: row.optionalInt("cycle_off"),
                                       start: row.optionalText("cycle_start"), weekdays: row.optionalInt("cycle_weekdays"))
            guard let cycle = try? CycleRule(columns: columns) else { return nil }
            return PlanItem(id: row.int("rowid"), meal: row.text("meal"), foodID: row.int("food_id"), quantity: row.double("quantity"), cycle: cycle)
        }
    }

    private static func signature(_ items: [PlanItem]) -> [String] {
        items.map { item in
            let c = item.cycle.columns
            return "\(item.meal)|\(item.foodID)|\(item.quantity)|\(c.mode)|\(c.on ?? 0)|\(c.off ?? 0)|\(c.start ?? "")|\(c.weekdays ?? 0)"
        }
    }
}
