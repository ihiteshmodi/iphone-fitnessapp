import Foundation

public struct WeeklyAverages: Equatable {
    public let latestWeighIn: ISODate
    public let currentAverageKg: Double
    public let pastAverageKg: Double
}

public struct CalorieEntry: Equatable {
    public let date: ISODate
    public let calories: Double
    public let multiplier: Double
}

public struct CalorieAdvice: Equatable {
    public let averages: WeeklyAverages
    public let target: CalorieTarget
}

/// Calories per day that apply from a date onward, with the goal multiplier chosen with them.
public struct CalorieDefault: Equatable {
    public let effectiveFrom: ISODate
    public let calories: Double
    public let multiplier: Double

    public init(effectiveFrom: ISODate, calories: Double, multiplier: Double) {
        self.effectiveFrom = effectiveFrom
        self.calories = calories
        self.multiplier = multiplier
    }
}

public enum CalorieSource: Equatable {
    /// Typed in for this one day.
    case manual
    /// Taken from the default in force that day.
    case baseline
    /// No entry and no default yet.
    case none
}

public struct CalorieDay: Equatable, Identifiable {
    public let date: ISODate
    public let calories: Double?
    public let source: CalorieSource
    public var id: String { date.string }
}

/// Reads weigh-ins, calories eaten and macro rules, and hands them to the pure `CalorieTarget` calculator.
public final class CalorieService {
    private let db: Database
    private let nutrition: NutritionSettings

    public init(_ db: Database) {
        self.db = db
        nutrition = NutritionSettings(db)
    }

    /// Mean weight of the 7 days ending at the latest weigh-in, and of the 7 days before that.
    public func weeklyAverages() throws -> WeeklyAverages {
        let notEnough = ValidationError("Log body weight for both of the last two weeks")
        guard let latestText = try db.query("SELECT MAX(measured_on) AS latest FROM body_weights").first?.optionalText("latest"),
              let latest = ISODate(latestText) else { throw notEnough }

        func average(from start: ISODate, to end: ISODate) throws -> Double? {
            try db.query("SELECT AVG(weight_kg) AS average FROM body_weights WHERE measured_on BETWEEN ? AND ?",
                         [.text(start.string), .text(end.string)]).first?.optionalDouble("average")
        }

        guard let current = try average(from: latest.adding(days: -6), to: latest),
              let past = try average(from: latest.adding(days: -13), to: latest.adding(days: -7)) else { throw notEnough }
        return WeeklyAverages(latestWeighIn: latest, currentAverageKg: current, pastAverageKg: past)
    }

    /// Target from the week's average calories (the 7 days the weight average covers).
    public func currentAdvice() throws -> CalorieAdvice {
        let averages = try weeklyAverages()
        guard let eaten = try averageCalories(endingOn: averages.latestWeighIn, days: 7) else {
            throw ValidationError("Log the calories you ate per day")
        }
        return try advice(averages: averages, caloriesEaten: eaten, multiplier: try multiplier(on: averages.latestWeighIn))
    }

    // MARK: Defaults and days

    /// The new default counts from `date` onward (past, today or future); earlier days keep the value they had.
    public func setDefault(calories: Double, multiplier: Double = 1, from date: ISODate) throws {
        try validate(calories: calories, multiplier: multiplier)
        try db.execute("""
            INSERT INTO calorie_defaults (effective_from, calories, multiplier) VALUES (?, ?, ?)
            ON CONFLICT(effective_from) DO UPDATE SET calories = excluded.calories, multiplier = excluded.multiplier
            """, [.text(date.string), .double(calories), .double(multiplier)])
    }

    public func setDefault(calories: Double, multiplier: Double = 1, from date: String) throws {
        guard let day = ISODate(date) else { throw ValidationError("Date is not valid") }
        try setDefault(calories: calories, multiplier: multiplier, from: day)
    }

    /// Newest first.
    public func defaults() throws -> [CalorieDefault] {
        try db.query("SELECT effective_from, calories, multiplier FROM calorie_defaults ORDER BY effective_from DESC").compactMap { row in
            guard let day = ISODate(row.text("effective_from")) else { return nil }
            return CalorieDefault(effectiveFrom: day, calories: row.double("calories"), multiplier: row.double("multiplier"))
        }
    }

    public func deleteDefault(from date: ISODate) throws {
        try db.execute("DELETE FROM calorie_defaults WHERE effective_from = ?", [.text(date.string)])
    }

    /// What one day counts as: the value typed for that day, else the default in force, else nothing.
    public func day(_ date: ISODate) throws -> CalorieDay {
        if let typed = try db.query("SELECT calories FROM calorie_entries WHERE logged_on = ?", [.text(date.string)]).first {
            return CalorieDay(date: date, calories: typed.double("calories"), source: .manual)
        }
        if let baseline = try defaultInForce(on: date) {
            return CalorieDay(date: date, calories: baseline.calories, source: .baseline)
        }
        return CalorieDay(date: date, calories: nil, source: .none)
    }

    /// `count` days ending at `end`, newest first.
    public func days(endingOn end: ISODate, count: Int) throws -> [CalorieDay] {
        try (0..<max(count, 0)).map { try day(end.adding(days: -$0)) }
    }

    /// Mean of the days that have calories, over the `days` days ending at `end`; nil when none do.
    public func averageCalories(endingOn end: ISODate, days count: Int) throws -> Double? {
        let values = try days(endingOn: end, count: count).compactMap(\.calories)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func defaultInForce(on date: ISODate) throws -> CalorieDefault? {
        try db.query("""
            SELECT effective_from, calories, multiplier FROM calorie_defaults
            WHERE effective_from <= ? ORDER BY effective_from DESC LIMIT 1
            """, [.text(date.string)]).first.flatMap { row in
            ISODate(row.text("effective_from")).map { CalorieDefault(effectiveFrom: $0, calories: row.double("calories"), multiplier: row.double("multiplier")) }
        }
    }

    /// The goal multiplier in force on a day: the default's, else the one saved with the latest typed day, else 1.
    private func multiplier(on date: ISODate) throws -> Double {
        if let baseline = try defaultInForce(on: date) { return baseline.multiplier }
        return try db.query("SELECT multiplier FROM calorie_entries WHERE logged_on <= ? ORDER BY logged_on DESC LIMIT 1",
                            [.text(date.string)]).first?.double("multiplier") ?? 1
    }

    /// Target for calories typed on screen without saving them.
    public func advice(caloriesEaten: Double, multiplier: Double = 1) throws -> CalorieAdvice {
        try advice(averages: try weeklyAverages(), caloriesEaten: caloriesEaten, multiplier: multiplier)
    }

    public func latestEntry() throws -> CalorieEntry? { try recentEntries(limit: 1).first }

    /// Newest first.
    public func recentEntries(limit: Int = 30) throws -> [CalorieEntry] {
        try db.query("SELECT logged_on, calories, multiplier FROM calorie_entries ORDER BY logged_on DESC LIMIT ?", [.int(Int64(limit))])
            .compactMap { row in
                guard let day = ISODate(row.text("logged_on")) else { return nil }
                return CalorieEntry(date: day, calories: row.double("calories"), multiplier: row.double("multiplier"))
            }
    }

    /// One entry per day: saving a day again replaces it.
    public func saveCalories(on date: String, calories: Double, multiplier: Double = 1) throws {
        try validate(calories: calories, multiplier: multiplier)
        guard let day = ISODate(date) else { throw ValidationError("Date is not valid") }
        try db.execute("""
            INSERT INTO calorie_entries (logged_on, calories, multiplier) VALUES (?, ?, ?)
            ON CONFLICT(logged_on) DO UPDATE SET calories = excluded.calories, multiplier = excluded.multiplier
            """, [.text(day.string), .double(calories), .double(multiplier)])
    }

    public func saveCalories(on date: ISODate, calories: Double, multiplier: Double = 1) throws {
        try saveCalories(on: date.string, calories: calories, multiplier: multiplier)
    }

    public func deleteCalories(on date: ISODate) throws {
        try db.execute("DELETE FROM calorie_entries WHERE logged_on = ?", [.text(date.string)])
    }

    private func advice(averages: WeeklyAverages, caloriesEaten: Double, multiplier: Double) throws -> CalorieAdvice {
        try validate(calories: caloriesEaten, multiplier: multiplier)
        let target = CalorieTarget.calculate(currentAverageKg: averages.currentAverageKg, pastAverageKg: averages.pastAverageKg,
                                             caloriesEaten: caloriesEaten, multiplier: multiplier, rules: try nutrition.rules())
        return CalorieAdvice(averages: averages, target: target)
    }

    private func validate(calories: Double, multiplier: Double) throws {
        guard calories.isFinite, calories > 0 else { throw ValidationError("Calories must be above 0") }
        guard multiplier.isFinite, multiplier > 0 else { throw ValidationError("Multiplier must be above 0") }
    }
}
