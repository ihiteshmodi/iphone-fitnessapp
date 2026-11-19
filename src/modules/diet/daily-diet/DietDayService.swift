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
        let ticked = Set(try db.query("SELECT meal, food_id FROM diet_day_ticks WHERE day = ?", [.text(date.string)]).map { "\($0.text("meal"))|\($0.int("food_id"))" })

        var meals: [DietMeal] = []
        for meal in plan?.meals ?? [] {
            let lines = try meal.items.map { item -> DietLine in
                let food = try require(book.food(item.foodID))
                let cycle = item.cycle.state(on: date, trainingWeekdays: training)
                let state: DietItemState = !cycle.isOn ? .offCycle(backOn: cycle.nextChange)
                    : ticked.contains("\(item.meal)|\(item.foodID)") ? .eaten : .notEaten
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
        let isOn = lines.filter { if case .offCycle = $0.state { return false } else { return true } }

        let extrasNutrition = extras.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let eatenNutrition = eaten.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let total = eatenNutrition + extrasNutrition
        let targets = DietTargets.evaluate(calories: total.calories, protein: total.protein, fat: total.fat,
                                           rules: try settings.load(), averageWeightKg: try averageWeightKg(on: date))
        return DietDay(date: date, hasPlan: plan != nil, meals: meals, extras: extras,
                       planned: isOn.reduce(Nutrition.zero) { $0 + $1.nutrition },
                       plannedCount: isOn.count, eatenCount: eaten.count, eatenNutrition: eatenNutrition,
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

    /// Ticking records that the item was eaten on this day; unticking removes that record.
    public func setEaten(_ eaten: Bool, meal: String, foodID: Int, on date: ISODate) throws {
        guard try plans.plan(inForceOn: date)?.items.contains(where: { $0.meal == meal && $0.foodID == foodID }) == true else {
            throw ValidationError("That item is not in the plan")
        }
        try setTick(eaten, meal: meal, foodID: foodID, on: date)
    }

    /// Ticks or unticks every item of a meal that is on today. Items that are off their cycle are left alone.
    public func setMealEaten(_ eaten: Bool, meal: String, on date: ISODate) throws {
        let items = (try plans.plan(inForceOn: date)?.items ?? []).filter { $0.meal == meal }
        guard !items.isEmpty else { throw ValidationError("That meal is not in the plan") }
        let training = try plans.trainingWeekdays()
        try db.transaction {
            for item in items where item.cycle.isOn(on: date, trainingWeekdays: training) {
                try setTick(eaten, meal: meal, foodID: item.foodID, on: date)
            }
        }
    }

    private func setTick(_ eaten: Bool, meal: String, foodID: Int, on date: ISODate) throws {
        if eaten {
            try db.execute("INSERT OR IGNORE INTO diet_day_ticks (day, meal, food_id) VALUES (?, ?, ?)", [.text(date.string), .text(meal), .int(Int64(foodID))])
        } else {
            try db.execute("DELETE FROM diet_day_ticks WHERE day = ? AND meal = ? AND food_id = ?", [.text(date.string), .text(meal), .int(Int64(foodID))])
        }
    }

    /// Calories-only quick add uses this food: 1 calorie per unit, so the amount is the calories.
    public static let quickCaloriesName = "Quick calories"

    @discardableResult
    public func addExtra(foodID: Int, _ input: PortionInput, on date: ISODate, details: ExtraDetails = ExtraDetails()) throws -> Int {
        guard let food = try library.food(foodID) else { throw ValidationError("That food is not in the library") }
        let portion = try Portions.portion(of: food, input)
        try db.execute("INSERT INTO diet_extras (day, food_id, amount, pieces, label, time_tag, note) VALUES (?, ?, ?, ?, ?, ?, ?)",
                       [.text(date.string), .int(Int64(foodID)), .double(portion.amount), .optional(portion.pieces),
                        .optional(details.label), .optional(details.time?.rawValue), .optional(details.note)])
        return db.lastInsertRowID
    }

    public func updateExtraDetails(_ id: Int, _ details: ExtraDetails) throws {
        try db.execute("UPDATE diet_extras SET label = ?, time_tag = ?, note = ? WHERE id = ?",
                       [.optional(details.label), .optional(details.time?.rawValue), .optional(details.note), .int(Int64(id))])
    }

    /// Food without a label: weigh it and log it against a preset whose unit stands for a weight (a batch of 10 g).
    @discardableResult
    public func quickAddByWeight(presetID: Int, grams: Double, on date: ISODate, details: ExtraDetails) throws -> Int {
        guard let preset = try library.food(presetID) else { throw ValidationError("That food is not in the library") }
        guard let gramsPerUnit = preset.draft.estimateGrams else { throw ValidationError("\(preset.name) is not set up for quick add by weight") }
        guard grams.isFinite, grams > 0 else { throw ValidationError("Enter an amount above 0") }
        return try addExtra(foodID: presetID, .amount(grams / gramsPerUnit * preset.draft.baseQuantity), on: date, details: details)
    }

    @discardableResult
    public func quickAddCalories(_ calories: Double, on date: ISODate, details: ExtraDetails) throws -> Int {
        try addExtra(foodID: try quickCaloriesFoodID(), .amount(calories), on: date, details: details)
    }

    private func quickCaloriesFoodID() throws -> Int {
        if let existing = try library.food(named: Self.quickCaloriesName) { return existing.id }
        return try library.add(FoodDraft(name: Self.quickCaloriesName, unit: "kcal", baseQuantity: 1, labelCalories: 1,
                                         notes: "Used by quick add when only the calories are known"))
    }

    /// The extra as the edit sheet reopens it. Pieces when it is a whole number of pieces, otherwise the food's own amount
    /// (grams, or the unit it is counted in). Nil when the extra is gone.
    public func entry(of id: Int) throws -> ExtraEntry? {
        guard let row = try db.query("SELECT day, food_id, amount, pieces, label, time_tag, note FROM diet_extras WHERE id = ?",
                                     [.int(Int64(id))]).first,
              let day = ISODate(row.text("day")) else { return nil }
        let foodID = row.int("food_id")
        let amount = row.double("amount")
        let details = Self.details(row)
        if let pieces = row.optionalDouble("pieces"), abs(pieces - pieces.rounded()) < 0.01, pieces.rounded() >= 1,
           let food = try library.food(foodID), Portions.modes(for: food).contains(.pieces) {
            return ExtraEntry(id: id, foodID: foodID, date: day, mode: .pieces, value: pieces.rounded(), details: details)
        }
        return ExtraEntry(id: id, foodID: foodID, date: day, mode: .amount, value: amount, details: details)
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
        try db.query("SELECT id, food_id, amount, pieces, label, time_tag, note FROM diet_extras WHERE day = ? ORDER BY id",
                     [.text(date.string)]).map { row in
            let food = try require(book.food(row.int("food_id")))
            return DietExtra(id: row.int("id"), foodID: food.id, name: food.name, unit: food.unit, amount: row.double("amount"),
                             pieces: row.optionalDouble("pieces"),
                             nutrition: try book.nutrition(of: food.id, quantity: row.double("amount")),
                             cost: try book.cost(of: food.id, quantity: row.double("amount")),
                             details: Self.details(row))
        }
    }

    /// The mean of the 7 days of weigh-ins ending at the newest weigh-in on or before the day.
    private func averageWeightKg(on date: ISODate) throws -> Double? {
        guard let latest = try db.query("SELECT MAX(measured_on) AS latest FROM body_weights WHERE measured_on <= ?", [.text(date.string)]).first?
            .optionalText("latest"), let end = ISODate(latest) else { return nil }
        return try db.query("SELECT AVG(weight_kg) AS average FROM body_weights WHERE measured_on BETWEEN ? AND ?",
                            [.text(end.adding(days: -6).string), .text(end.string)]).first?.optionalDouble("average")
    }

    private static func details(_ row: Row) -> ExtraDetails {
        ExtraDetails(label: row.optionalText("label"), time: row.optionalText("time_tag").flatMap(ExtraTime.init(rawValue:)),
                     note: row.optionalText("note"))
    }

    private func require(_ food: Food?) throws -> Food {
        guard let food else { throw ValidationError("That food is not in the library") }
        return food
    }
}
