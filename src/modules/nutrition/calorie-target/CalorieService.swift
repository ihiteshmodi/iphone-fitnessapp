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

    /// Target from the most recent calorie entry.
    public func currentAdvice() throws -> CalorieAdvice {
        let averages = try weeklyAverages()
        guard let entry = try latestEntry() else { throw ValidationError("Log the calories you ate per day") }
        return try advice(averages: averages, caloriesEaten: entry.calories, multiplier: entry.multiplier)
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
