import Foundation

public struct PlanItem: Equatable, Identifiable {
    public let id: Int
    public let meal: String
    public let foodID: Int
    public let quantity: Double
    public let cycle: CycleRule
}

public struct PlanMeal: Equatable {
    public let name: String
    public let items: [PlanItem]
}

/// The plan that applies from `effectiveFrom` onward, until a newer plan starts.
public struct DietPlan: Equatable {
    public let effectiveFrom: ISODate
    public let items: [PlanItem]

    /// Meals in the order they first appear, each with its items in order.
    public var meals: [PlanMeal] {
        var names: [String] = []
        for item in items where !names.contains(item.meal) { names.append(item.meal) }
        return names.map { name in PlanMeal(name: name, items: items.filter { $0.meal == name }) }
    }
}

/// Reads and edits the dated diet plans. A change starts on a chosen date: it copies the plan in force and edits the copy,
/// so earlier days keep the plan they had.
public final class DietPlanService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    // MARK: Read

    /// Start dates, newest first.
    public func startDates() throws -> [ISODate] {
        try db.query("SELECT effective_from FROM diet_plans ORDER BY effective_from DESC").compactMap { ISODate($0.text("effective_from")) }
    }

    public func plan(inForceOn date: ISODate) throws -> DietPlan? {
        guard let start = try db.query("SELECT effective_from FROM diet_plans WHERE effective_from <= ? ORDER BY effective_from DESC LIMIT 1",
                                       [.text(date.string)]).first,
              let from = ISODate(start.text("effective_from")) else { return nil }
        return DietPlan(effectiveFrom: from, items: try items(of: from))
    }

    /// The weekdays (1 = Monday) the workout plan trains on. Empty when the workout days have no weekday set.
    public func trainingWeekdays() throws -> Set<Int> {
        Set(try db.query("SELECT weekday FROM plan_days WHERE weekday IS NOT NULL").map { $0.int("weekday") })
    }

    // MARK: Edit from a date

    public func addItem(foodID: Int, quantity: Double, meal: String, cycle: CycleRule = .daily, from date: ISODate) throws {
        let meal = meal.trimmingCharacters(in: .whitespaces)
        guard quantity.isFinite, quantity > 0 else { throw ValidationError("Enter a quantity above 0") }
        guard !meal.isEmpty else { throw ValidationError("Give the meal a name") }
        guard let food = try db.query("SELECT name FROM foods WHERE id = ?", [.int(Int64(foodID))]).first else {
            throw ValidationError("That food is not in the library")
        }
        try db.transaction {
            try ensurePlan(from: date)
            guard try find(meal: meal, foodID: foodID, in: date) == nil else { throw ValidationError("\(food.text("name")) is already in \(meal)") }
            try insert(foodID: foodID, quantity: quantity, meal: meal, cycle: cycle, into: date)
        }
    }

    /// Changes the quantity, the cycle and/or the meal of the item identified by its meal and food.
    public func changeItem(meal: String, foodID: Int, from date: ISODate, quantity: Double? = nil, cycle: CycleRule? = nil, moveTo newMeal: String? = nil) throws {
        if let quantity { guard quantity.isFinite, quantity > 0 else { throw ValidationError("Enter a quantity above 0") } }
        let target = newMeal?.trimmingCharacters(in: .whitespaces)
        if let target { guard !target.isEmpty else { throw ValidationError("Give the meal a name") } }
        try db.transaction {
            try ensurePlan(from: date)
            guard let id = try find(meal: meal, foodID: foodID, in: date) else { throw ValidationError("That item is not in the plan") }
            if let quantity {
                try db.execute("UPDATE diet_plan_items SET quantity = ? WHERE id = ?", [.double(quantity), .int(Int64(id))])
            }
            if let cycle {
                let c = cycle.columns
                try db.execute("""
                    UPDATE diet_plan_items SET cycle_mode = ?, cycle_on = ?, cycle_off = ?, cycle_start = ?, cycle_weekdays = ? WHERE id = ?
                    """, [.text(c.mode), .optional(c.on), .optional(c.off), .optional(c.start), .optional(c.weekdays), .int(Int64(id))])
            }
            if let target, target != meal {
                if try find(meal: target, foodID: foodID, in: date) != nil {
                    throw ValidationError("That food is already in \(target)")
                }
                let position = try nextPosition(in: date)
                try db.execute("UPDATE diet_plan_items SET meal = ?, position = ? WHERE id = ?", [.text(target), .int(Int64(position)), .int(Int64(id))])
            }
        }
    }

    public func removeItem(meal: String, foodID: Int, from date: ISODate) throws {
        try db.transaction {
            try ensurePlan(from: date)
            guard let id = try find(meal: meal, foodID: foodID, in: date) else { throw ValidationError("That item is not in the plan") }
            try db.execute("DELETE FROM diet_plan_items WHERE id = ?", [.int(Int64(id))])
        }
    }

    /// Deletes the plan that starts on this date, so the one before it applies again.
    public func removePlan(startingOn date: ISODate) throws {
        try db.execute("DELETE FROM diet_plans WHERE effective_from = ?", [.text(date.string)])
    }

    // MARK: Private

    private func items(of from: ISODate) throws -> [PlanItem] {
        try db.query("SELECT * FROM diet_plan_items WHERE plan_from = ? ORDER BY position, id", [.text(from.string)]).compactMap { row in
            let columns = CycleColumns(mode: row.text("cycle_mode"), on: row.optionalInt("cycle_on"), off: row.optionalInt("cycle_off"),
                                       start: row.optionalText("cycle_start"), weekdays: row.optionalInt("cycle_weekdays"))
            guard let cycle = try? CycleRule(columns: columns) else { return nil }
            return PlanItem(id: row.int("id"), meal: row.text("meal"), foodID: row.int("food_id"), quantity: row.double("quantity"), cycle: cycle)
        }
    }

    /// Makes sure a plan starts on `date`: a copy of the plan in force then, or an empty one.
    private func ensurePlan(from date: ISODate) throws {
        guard try db.query("SELECT 1 FROM diet_plans WHERE effective_from = ?", [.text(date.string)]).isEmpty else { return }
        let source = try plan(inForceOn: date)
        try db.execute("INSERT INTO diet_plans (effective_from) VALUES (?)", [.text(date.string)])
        guard let source else { return }
        try db.execute("""
            INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity, cycle_mode, cycle_on, cycle_off, cycle_start, cycle_weekdays)
            SELECT ?, meal, position, food_id, quantity, cycle_mode, cycle_on, cycle_off, cycle_start, cycle_weekdays
            FROM diet_plan_items WHERE plan_from = ? ORDER BY position, id
            """, [.text(date.string), .text(source.effectiveFrom.string)])
    }

    private func find(meal: String, foodID: Int, in plan: ISODate) throws -> Int? {
        try db.query("SELECT id FROM diet_plan_items WHERE plan_from = ? AND meal = ? AND food_id = ?",
                     [.text(plan.string), .text(meal), .int(Int64(foodID))]).first?.int("id")
    }

    private func nextPosition(in plan: ISODate) throws -> Int {
        (try db.query("SELECT MAX(position) AS top FROM diet_plan_items WHERE plan_from = ?", [.text(plan.string)]).first?.optionalInt("top") ?? 0) + 1
    }

    private func insert(foodID: Int, quantity: Double, meal: String, cycle: CycleRule, into plan: ISODate) throws {
        let c = cycle.columns
        try db.execute("""
            INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity, cycle_mode, cycle_on, cycle_off, cycle_start, cycle_weekdays)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(plan.string), .text(meal), .int(Int64(try nextPosition(in: plan))), .int(Int64(foodID)), .double(quantity),
                  .text(c.mode), .optional(c.on), .optional(c.off), .optional(c.start), .optional(c.weekdays)])
    }
}
