import Foundation

/// Adds up what was eaten on a day: the plan in force (ticked items, items that are on their cycle) plus extras,
/// measured against the diet rules. Nutrition and cost are always worked out from the current foods.
public final class DietDayService {
    private let db: Database
    private let library: FoodLibrary
    private let plans: DietPlanService
    private let settings: DietSettings

    public init(_ db: Database) {
        self.db = db
        library = FoodLibrary(db)
        plans = DietPlanService(db)
        settings = DietSettings(db)
    }

    // MARK: Read

    public func day(_ date: ISODate) throws -> DietDay {
        let book = try library.book()
        let plan = try plans.plan(inForceOn: date)
        let training = try plans.trainingWeekdays()
        let skipped = Set(try db.query("SELECT meal, food_id FROM diet_day_skips WHERE day = ?", [.text(date.string)]).map { "\($0.text("meal"))|\($0.int("food_id"))" })

        var meals: [DietMeal] = []
        for meal in plan?.meals ?? [] {
            let lines = try meal.items.map { item -> DietLine in
                let food = try require(book.food(item.foodID))
                let cycle = item.cycle.state(on: date, trainingWeekdays: training)
                let state: DietItemState = !cycle.isOn ? .offCycle(backOn: cycle.nextChange)
                    : skipped.contains("\(item.meal)|\(item.foodID)") ? .skipped : .eaten
                return DietLine(meal: item.meal, foodID: item.foodID, name: food.name, unit: food.unit, quantity: item.quantity, state: state,
                                nutrition: try book.nutrition(of: item.foodID, quantity: item.quantity),
                                cost: try book.cost(of: item.foodID, quantity: item.quantity),
                                cycle: item.cycle == .daily ? nil : cycle)
            }
            meals.append(DietMeal(name: meal.name, lines: lines))
        }

        let extras = try extras(on: date, book: book)
        let lines = meals.flatMap(\.lines)
        let eaten = lines.filter { $0.state == .eaten }
        let skippedLines = lines.filter { $0.state == .skipped }
        let isOn = lines.filter { if case .offCycle = $0.state { return false } else { return true } }

        let extrasNutrition = extras.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let total = eaten.reduce(extrasNutrition) { $0 + $1.nutrition }
        let targets = DietTargets.evaluate(calories: total.calories, protein: total.protein, fat: total.fat,
                                           rules: try settings.load(), averageWeightKg: try averageWeightKg(on: date))
        return DietDay(date: date, hasPlan: plan != nil, meals: meals, extras: extras,
                       planned: isOn.reduce(Nutrition.zero) { $0 + $1.nutrition },
                       skipped: skippedLines.reduce(Nutrition.zero) { $0 + $1.nutrition }, skippedCount: skippedLines.count,
                       extrasNutrition: extrasNutrition, total: total,
                       cost: (eaten.map(\.cost) + extras.map(\.cost)).reduce(Cost.free, +), targets: targets)
    }

    /// Extras eaten in the `days` days ending at `end`; `days` in the result counts the days that have any.
    public func extrasSummary(endingOn end: ISODate, days count: Int) throws -> ExtrasSummary {
        let book = try library.book()
        let rows = try db.query("SELECT day, food_id, amount FROM diet_extras WHERE day BETWEEN ? AND ?",
                                [.text(end.adding(days: -(count - 1)).string), .text(end.string)])
        var nutrition = Nutrition.zero
        var cost = Cost.free
        for row in rows {
            nutrition = nutrition + (try book.nutrition(of: row.int("food_id"), quantity: row.double("amount")))
            cost = cost + (try book.cost(of: row.int("food_id"), quantity: row.double("amount")))
        }
        return ExtrasSummary(days: Set(rows.map { $0.text("day") }).count, nutrition: nutrition, cost: cost)
    }

    /// The last amount eaten of each food, newest first, so a usual extra is one tap.
    public func recentExtras(limit: Int = 5) throws -> [RecentExtra] {
        try db.query("""
            SELECT e.food_id, f.name, e.amount, e.pieces FROM diet_extras e JOIN foods f ON f.id = e.food_id
            WHERE e.id = (SELECT MAX(id) FROM diet_extras WHERE food_id = e.food_id)
            ORDER BY e.id DESC LIMIT ?
            """, [.int(Int64(limit))]).map {
            RecentExtra(foodID: $0.int("food_id"), name: $0.text("name"), amount: $0.double("amount"), pieces: $0.optionalDouble("pieces"))
        }
    }

    // MARK: Write

    /// Unticking records that the item was not eaten on this day; ticking it again removes that record.
    public func setEaten(_ eaten: Bool, meal: String, foodID: Int, on date: ISODate) throws {
        guard try plans.plan(inForceOn: date)?.items.contains(where: { $0.meal == meal && $0.foodID == foodID }) == true else {
            throw ValidationError("That item is not in the plan")
        }
        if eaten {
            try db.execute("DELETE FROM diet_day_skips WHERE day = ? AND meal = ? AND food_id = ?", [.text(date.string), .text(meal), .int(Int64(foodID))])
        } else {
            try db.execute("INSERT OR IGNORE INTO diet_day_skips (day, meal, food_id) VALUES (?, ?, ?)", [.text(date.string), .text(meal), .int(Int64(foodID))])
        }
    }

    @discardableResult
    public func addExtra(foodID: Int, _ input: PortionInput, on date: ISODate) throws -> Int {
        guard let food = try library.food(foodID) else { throw ValidationError("That food is not in the library") }
        let portion = try Portions.portion(of: food, input)
        try db.execute("INSERT INTO diet_extras (day, food_id, amount, pieces) VALUES (?, ?, ?, ?)",
                       [.text(date.string), .int(Int64(foodID)), .double(portion.amount), .optional(portion.pieces)])
        return db.lastInsertRowID
    }

    public func updateExtra(_ id: Int, _ input: PortionInput) throws {
        guard let row = try db.query("SELECT food_id FROM diet_extras WHERE id = ?", [.int(Int64(id))]).first,
              let food = try library.food(row.int("food_id")) else { throw ValidationError("That extra is no longer there") }
        let portion = try Portions.portion(of: food, input)
        try db.execute("UPDATE diet_extras SET amount = ?, pieces = ? WHERE id = ?", [.double(portion.amount), .optional(portion.pieces), .int(Int64(id))])
    }

    public func removeExtra(_ id: Int) throws {
        try db.execute("DELETE FROM diet_extras WHERE id = ?", [.int(Int64(id))])
    }

    // MARK: Private

    private func extras(on date: ISODate, book: FoodBook) throws -> [DietExtra] {
        try db.query("SELECT id, food_id, amount, pieces FROM diet_extras WHERE day = ? ORDER BY id", [.text(date.string)]).map { row in
            let food = try require(book.food(row.int("food_id")))
            return DietExtra(id: row.int("id"), foodID: food.id, name: food.name, unit: food.unit, amount: row.double("amount"),
                             pieces: row.optionalDouble("pieces"),
                             nutrition: try book.nutrition(of: food.id, quantity: row.double("amount")),
                             cost: try book.cost(of: food.id, quantity: row.double("amount")))
        }
    }

    /// The mean of the 7 days of weigh-ins ending at the newest weigh-in on or before the day.
    private func averageWeightKg(on date: ISODate) throws -> Double? {
        guard let latest = try db.query("SELECT MAX(measured_on) AS latest FROM body_weights WHERE measured_on <= ?", [.text(date.string)]).first?
            .optionalText("latest"), let end = ISODate(latest) else { return nil }
        return try db.query("SELECT AVG(weight_kg) AS average FROM body_weights WHERE measured_on BETWEEN ? AND ?",
                            [.text(end.adding(days: -6).string), .text(end.string)]).first?.optionalDouble("average")
    }

    private func require(_ food: Food?) throws -> Food {
        guard let food else { throw ValidationError("That food is not in the library") }
        return food
    }
}
