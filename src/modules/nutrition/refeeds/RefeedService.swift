import Foundation

public enum RefeedMark: String, CaseIterable, Equatable {
    case refeed, normal, skipped

    public var title: String {
        switch self {
        case .refeed: return "Refeed done"
        case .normal: return "Normal day"
        case .skipped: return "Skipped"
        }
    }
}

/// Refeed days the owner chooses while cutting (weekdays and/or dates), and what he marked each one as.
public final class RefeedService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    /// Vault: a refeed is 1-2 days at maintenance, the extra mostly carbs, protein and fat unchanged.
    public static func target(maintenance: Double) -> Double { maintenance }

    /// ISO weekdays, 1 = Monday.
    public func weekdays() throws -> Set<Int> {
        let mask = Int(try db.query("SELECT value FROM settings WHERE key = 'refeed_weekdays'").first?.text("value") ?? "") ?? 0
        return Set((1...7).filter { mask & (1 << ($0 - 1)) != 0 })
    }

    public func setWeekdays(_ days: Set<Int>) throws {
        let mask = days.filter { (1...7).contains($0) }.reduce(0) { $0 | (1 << ($1 - 1)) }
        try db.execute("INSERT INTO settings (key, value) VALUES ('refeed_weekdays', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(String(mask))])
    }

    public func dates() throws -> [ISODate] {
        try db.query("SELECT day FROM refeed_days WHERE planned = 1 ORDER BY day").compactMap { ISODate($0.text("day")) }
    }

    public func addDate(_ day: ISODate) throws {
        try db.execute("INSERT INTO refeed_days (day, planned) VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET planned = 1", [.text(day.string)])
    }

    public func removeDate(_ day: ISODate) throws {
        try db.execute("UPDATE refeed_days SET planned = 0 WHERE day = ?", [.text(day.string)])
    }

    /// Only while cutting (the goal multiplier in force that day is under 1).
    public func isRefeedDay(_ day: ISODate) throws -> Bool {
        guard try Self.cutStart(on: day, db: db) != nil else { return false }
        if try weekdays().contains(day.weekday) { return true }
        return try !db.query("SELECT 1 FROM refeed_days WHERE day = ? AND planned = 1", [.text(day.string)]).isEmpty
    }

    public func mark(on day: ISODate) throws -> RefeedMark? {
        try db.query("SELECT mark FROM refeed_days WHERE day = ?", [.text(day.string)]).first?.optionalText("mark").flatMap(RefeedMark.init(rawValue:))
    }

    public func mark(_ mark: RefeedMark?, on day: ISODate) throws {
        try db.execute("INSERT INTO refeed_days (day, mark) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET mark = excluded.mark",
                       [.text(day.string), .optional(mark?.rawValue)])
    }

    /// The last refeed marked done on or before the day.
    public func lastRefeed(onOrBefore day: ISODate) throws -> ISODate? {
        try db.query("SELECT MAX(day) AS d FROM refeed_days WHERE mark = 'refeed' AND day <= ?", [.text(day.string)]).first?.optionalText("d").flatMap(ISODate.init)
    }

    /// The first day of the current run of cutting defaults, or nil when not cutting on that day.
    public static func cutStart(on day: ISODate, db: Database) throws -> ISODate? {
        let defaults = try CalorieService(db).defaults().filter { $0.effectiveFrom <= day }
        guard let current = defaults.first, current.multiplier < 1 else { return nil }
        var start = current.effectiveFrom
        for earlier in defaults.dropFirst() {
            guard earlier.multiplier < 1 else { break }
            start = earlier.effectiveFrom
        }
        return start
    }
}

/// Vault: in a long cut, 1-2 weeks at true maintenance every 6-12 weeks of dieting.
struct DietBreakRule: SetupRule {
    let id = "diet-break"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        guard let start = try RefeedService.cutStart(on: day, db: db) else { return [] }
        let weeks = day.days(since: start) / 7
        guard weeks >= 6 else { return [] }
        return [Insight(ruleID: id, kind: .setup, severity: weeks >= 12 ? .improve : .tip, title: "Diet break",
                        detail: "\(weeks) weeks of cutting since \(start). Plan 1-2 weeks at maintenance (eat at maintenance, not freely), then go back to the deficit.",
                        why: "Vault: a diet break of 1-2 weeks at maintenance every 6-12 weeks of dieting, mostly for long or hard cuts and leaner dieters.")]
    }
}

public enum RefeedRules {
    public static var setup: [SetupRule] { [DietBreakRule()] }
    /// The scale jump after a refeed is water and glycogen; rate checks wait this many days.
    static let quietDaysAfterRefeed = 3
}
