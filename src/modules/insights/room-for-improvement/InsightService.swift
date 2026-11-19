import Foundation

/// Runs the rules and remembers what the owner did with their results (dismissed for a day, accepted, not applicable).
public final class InsightService {
    private let db: Database
    private let daily: [DailyRule]
    private let setupRules: [SetupRule]
    private let labRules: [SetupRule]

    public init(_ db: Database, daily: [DailyRule], setup: [SetupRule], labs: [SetupRule] = []) {
        self.db = db
        self.daily = daily
        setupRules = setup
        labRules = labs
    }

    /// What fired yesterday and (for rules that can judge an unfinished day) today, worst first.
    public func today(on today: ISODate) throws -> [Insight] {
        let hidden = try dismissedKeys()
        let archived = try archivedStates()
        var found: [Insight] = []
        for rule in daily where archived[rule.id] == nil {
            let days = rule.checksToday ? [today, today.adding(days: -1)] : [today.adding(days: -1)]
            for day in days {
                if case .fired(let insight) = try rule.evaluate(on: day, db: db), !hidden.contains(insight.id) { found.append(insight) }
            }
        }
        return found.sorted { ($0.severity, $1.day ?? today) < ($1.severity, $0.day ?? today) }
    }

    public func setup(on today: ISODate) throws -> [Insight] {
        let archived = try archivedStates()
        return try setupRules.filter { archived[$0.id] == nil }.flatMap { try $0.evaluate(on: today, db: db) }.sorted { $0.severity < $1.severity }
    }

    /// From bloodwork: doctor alerts first. Dismissed items stay hidden until a newer result changes their id.
    public func labs(on today: ISODate) throws -> [Insight] {
        let hidden = try dismissedKeys()
        let archived = try archivedStates()
        return try labRules.filter { archived[$0.id] == nil }.flatMap { try $0.evaluate(on: today, db: db) }
            .filter { !hidden.contains($0.id) }.sorted { $0.severity < $1.severity }
    }

    /// One row per daily rule still running (accepted ones included), over the `days` ending at `end`.
    public func trends(endingOn end: ISODate, days: Int) throws -> [TrendRow] {
        let archived = try archivedStates()
        return try daily.filter { archived[$0.id] != .notApplicable }.map { rule in
            let marks = try (0..<days).reversed().map { offset -> TrendMark in
                switch try rule.evaluate(on: end.adding(days: -offset), db: db) {
                case .fired: return .fired
                case .ok: return .ok
                case .noData: return .noData
                }
            }
            return TrendRow(ruleID: rule.id, title: rule.title, marks: marks)
        }
    }

    public func badgeCount(on today: ISODate) throws -> Int { try self.today(on: today).count + setup(on: today).count + labs(on: today).count }

    public func archived() throws -> [ArchivedRule] {
        try db.query("SELECT rule_id, title, status, note FROM insight_rules ORDER BY title COLLATE NOCASE").compactMap { row in
            ArchiveStatus(rawValue: row.text("status")).map {
                ArchivedRule(ruleID: row.text("rule_id"), title: row.text("title"), status: $0, note: row.optionalText("note"))
            }
        }
    }

    public func dismiss(_ insight: Insight) throws {
        try db.execute("INSERT OR IGNORE INTO insight_dismissals (key) VALUES (?)", [.text(insight.id)])
    }

    public func accept(_ insight: Insight, note: String? = nil) throws {
        try archive(insight.ruleID, title: insight.title, status: .accepted, note: note)
    }

    public func markNotApplicable(_ ruleID: String, title: String, note: String? = nil) throws {
        try archive(ruleID, title: title, status: .notApplicable, note: note)
    }

    public func restore(_ ruleID: String) throws {
        try db.execute("DELETE FROM insight_rules WHERE rule_id = ?", [.text(ruleID)])
    }

    // MARK: Private

    private func archive(_ ruleID: String, title: String, status: ArchiveStatus, note: String?) throws {
        let cleaned = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.execute("""
            INSERT INTO insight_rules (rule_id, title, status, note) VALUES (?, ?, ?, ?)
            ON CONFLICT(rule_id) DO UPDATE SET title = excluded.title, status = excluded.status, note = excluded.note
            """, [.text(ruleID), .text(title), .text(status.rawValue), .optional(cleaned?.isEmpty == false ? cleaned : nil)])
    }

    private func dismissedKeys() throws -> Set<String> {
        Set(try db.query("SELECT key FROM insight_dismissals").map { $0.text("key") })
    }

    private func archivedStates() throws -> [String: ArchiveStatus] {
        var states: [String: ArchiveStatus] = [:]
        for row in try db.query("SELECT rule_id, status FROM insight_rules") { states[row.text("rule_id")] = ArchiveStatus(rawValue: row.text("status")) }
        return states
    }
}
