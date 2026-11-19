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
    /// Added up from the diet plan in force that day: the ticked items plus extras.
    case plan
    /// Taken from the default in force that day.
    case baseline
    /// No entry and no default yet.
    case none
}

public struct CalorieDay: Equatable, Identifiable {
    public let date: ISODate
    public let calories: Double?
    public let source: CalorieSource
    /// Plan days only: the planned items that are on that day, and how many of them are ticked.
    public let plannedCount: Int
    public let tickedCount: Int
    /// Extras added that day on top of the plan or the default.
    public let extraCount: Int
    public var id: String { date.string }
    public var isUnloggedDietDay: Bool { source == .plan && tickedCount == 0 && extraCount == 0 }

    public init(date: ISODate, calories: Double?, source: CalorieSource, plannedCount: Int = 0, tickedCount: Int = 0, extraCount: Int = 0) {
        self.date = date
        self.calories = calories
        self.source = source
        self.plannedCount = plannedCount
        self.tickedCount = tickedCount
        self.extraCount = extraCount
    }
}

/// Reads weigh-ins, calories eaten and macro rules, and hands them to the pure `CalorieTarget` calculator.
public final class CalorieService {
    private let db: Database
    private let nutrition: NutritionSettings
    private let diet: DietDayService
    private let breaks: BreakModeService

    /// Comparing two 7-day averages needs both weeks clear of a break.
    public static let recalibrationDays = 14

    public init(_ db: Database) {
        self.db = db
        nutrition = NutritionSettings(db)
        diet = DietDayService(db)
        breaks = BreakModeService(db)
    }

    /// Mean weight of the 7 days ending at the latest weigh-in, and of the 7 days before that.
    public func weeklyAverages() throws -> WeeklyAverages { try weeklyAverages(upTo: nil) }

    /// Same as `weeklyAverages()`, but only weigh-ins on or before `day` exist, so a past day reads as it did then.
    public func weeklyAverages(asOf day: ISODate) throws -> WeeklyAverages { try weeklyAverages(upTo: day) }

    private func weeklyAverages(upTo day: ISODate?) throws -> WeeklyAverages {
        let notEnough = ValidationError("Log body weight for both of the last two weeks")
        let periods = try breaks.periods()
        let weighIns = try db.query("SELECT measured_on, weight_kg FROM body_weights WHERE measured_on <= ? ORDER BY measured_on",
                                    [.text(day?.string ?? "9999-12-31")]).compactMap { row -> (ISODate, Double)? in
            guard let measured = ISODate(row.text("measured_on")), !periods.contains(where: { $0.contains(measured) }) else { return nil }
            return (measured, row.double("weight_kg"))
        }
        guard let latest = weighIns.last?.0 else { throw notEnough }

        let windowStart = latest.adding(days: -(Self.recalibrationDays - 1))
        if let lastBreakEnd = periods.compactMap(\.end).filter({ $0 >= windowStart && $0 < latest }).max() {
            throw ValidationError("Recalibrating after your break: \(latest.days(since: lastBreakEnd)) of \(Self.recalibrationDays) days")
        }

        func average(from start: ISODate, to end: ISODate) -> Double? {
            let values = weighIns.filter { start <= $0.0 && $0.0 <= end }.map(\.1)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }

        guard let current = average(from: latest.adding(days: -6), to: latest),
              let past = average(from: latest.adding(days: -13), to: latest.adding(days: -7)) else { throw notEnough }
        return WeeklyAverages(latestWeighIn: latest, currentAverageKg: current, pastAverageKg: past)
    }

    /// Target from the average calories of the 7 days ending the day before the latest weigh-in: a morning weigh-in
    /// reflects what was eaten up to the night before, and the weigh-in day itself is usually still being logged.
    /// When none of those days has calories yet (a first default that starts today), the newest default stands in.
    public func currentAdvice() throws -> CalorieAdvice {
        try advice(averages: try weeklyAverages(), fallback: try defaults().first, multiplierOn: nil)
    }

    /// The calorie maths as it stood on a past (or future) day: weigh-ins up to that day, food up to the day before the
    /// weigh-in it uses, and the default and multiplier in force on that day.
    public func advice(asOf day: ISODate) throws -> CalorieAdvice {
        try advice(averages: try weeklyAverages(asOf: day), fallback: try defaultInForce(on: day), multiplierOn: day)
    }

    private func advice(averages: WeeklyAverages, fallback: CalorieDefault?, multiplierOn day: ISODate?) throws -> CalorieAdvice {
        guard let eaten = try averageCalories(endingOn: averages.latestWeighIn.adding(days: -1), days: 7) ?? fallback?.calories else {
            throw ValidationError("Log the calories you ate per day")
        }
        return try advice(averages: averages, caloriesEaten: eaten, multiplier: try multiplier(on: day ?? averages.latestWeighIn))
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

    /// What one day counts as: the value typed for that day, else the ticked items of the diet plan in force plus extras
    /// (0 when nothing is ticked yet), else the default in force plus any extras, else nothing.
    public func day(_ date: ISODate) throws -> CalorieDay {
        if let typed = try db.query("SELECT calories FROM calorie_entries WHERE logged_on = ?", [.text(date.string)]).first {
            return CalorieDay(date: date, calories: typed.double("calories"), source: .manual)
        }
        let eaten = try diet.day(date)
        if eaten.hasPlan {
            return CalorieDay(date: date, calories: eaten.total.calories, source: .plan, plannedCount: eaten.plannedCount, tickedCount: eaten.eatenCount, extraCount: eaten.extras.count)
        }
        if let baseline = try defaultInForce(on: date) {
            return CalorieDay(date: date, calories: baseline.calories + eaten.extrasNutrition.calories, source: .baseline, extraCount: eaten.extras.count)
        }
        return CalorieDay(date: date, calories: nil, source: .none)
    }

    /// `count` days ending at `end`, newest first.
    public func days(endingOn end: ISODate, count: Int) throws -> [CalorieDay] {
        try (0..<max(count, 0)).map { try day(end.adding(days: -$0)) }
    }

    /// Mean of the days that have calories, over the `days` days ending at `end`; nil when none do.
    /// A diet day with nothing ticked and no extras was not logged, so it is left out rather than counted as 0.
    /// Break days are left out too.
    public func averageCalories(endingOn end: ISODate, days count: Int) throws -> Double? {
        let periods = try breaks.periods()
        let values = try days(endingOn: end, count: count)
            .filter { day in !day.isUnloggedDietDay && !periods.contains { $0.contains(day.date) } }
            .compactMap(\.calories)
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

    /// The goal multiplier in force on a day: the default's, else the newest default, else the one saved with the latest typed day, else 1.
    private func multiplier(on date: ISODate) throws -> Double {
        if let baseline = try defaultInForce(on: date) ?? defaults().first { return baseline.multiplier }
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
