import Foundation

/// Days off logging. `end` is nil while the break is still on.
public struct BreakPeriod: Equatable, Identifiable {
    public let id: Int
    public let start: ISODate
    public let end: ISODate?

    public init(id: Int, start: ISODate, end: ISODate?) {
        self.id = id
        self.start = start
        self.end = end
    }

    public func contains(_ day: ISODate) -> Bool { start <= day && (end.map { day <= $0 } ?? true) }
}

/// Where the calorie maths stood the day before a break, and what the scale did across it.
public struct BeforeBreak: Equatable {
    public let advice: CalorieAdvice
    public let weightBeforeKg: Double?
    public let weightAfterKg: Double?
}

public final class BreakModeService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    /// Oldest first.
    public func periods() throws -> [BreakPeriod] {
        try db.query("SELECT id, starts_on, ends_on FROM break_periods ORDER BY starts_on").compactMap { row in
            guard let start = ISODate(row.text("starts_on")) else { return nil }
            return BreakPeriod(id: row.int("id"), start: start, end: row.optionalText("ends_on").flatMap(ISODate.init))
        }
    }

    public func isOnBreak(_ day: ISODate) throws -> Bool { try periods().contains { $0.contains(day) } }

    public func current(on day: ISODate) throws -> BreakPeriod? { try periods().first { $0.contains(day) } }

    public func start(on day: ISODate) throws { try insert(from: day, to: nil) }

    public func add(from start: ISODate, to end: ISODate) throws { try insert(from: start, to: end) }

    /// Closes the break that is on that day.
    public func end(on day: ISODate) throws {
        guard let open = try current(on: day) else { throw ValidationError("There is no break on that day") }
        try db.execute("UPDATE break_periods SET ends_on = ? WHERE id = ?", [.text(day.string), .int(Int64(open.id))])
    }

    public func delete(id: Int) throws {
        try db.execute("DELETE FROM break_periods WHERE id = ?", [.int(Int64(id))])
    }

    public func beforeBreak(_ period: BreakPeriod, calories: CalorieService) throws -> BeforeBreak? {
        guard let advice = try? calories.advice(asOf: period.start.adding(days: -1)) else { return nil }
        let before = try db.query("SELECT weight_kg FROM body_weights WHERE measured_on < ? ORDER BY measured_on DESC LIMIT 1",
                                  [.text(period.start.string)]).first?.double("weight_kg")
        let after = try period.end.flatMap { end in
            try db.query("SELECT weight_kg FROM body_weights WHERE measured_on > ? ORDER BY measured_on LIMIT 1",
                         [.text(end.string)]).first?.double("weight_kg")
        }
        return BeforeBreak(advice: advice, weightBeforeKg: before, weightAfterKg: after)
    }

    private func insert(from start: ISODate, to end: ISODate?) throws {
        if let end, end < start { throw ValidationError("A break ends on or after the day it starts") }
        let candidate = BreakPeriod(id: 0, start: start, end: end)
        let overlaps = try periods().contains { other in
            let otherEndsBeforeStart = other.end.map { $0 < candidate.start } ?? false
            let candidateEndsBeforeOther = candidate.end.map { $0 < other.start } ?? false
            return !otherEndsBeforeStart && !candidateEndsBeforeOther
        }
        guard !overlaps else { throw ValidationError("That overlaps another break") }
        try db.execute("INSERT INTO break_periods (starts_on, ends_on) VALUES (?, ?)", [.text(start.string), .optional(end?.string)])
    }
}
