import Foundation

/// The hard training rules from the vault (Vol 06): day spacing, deloads, weekly sets per muscle, cut and bulk rate.
public enum TrainingRules {
    public static var daily: [DailyRule] { [WeeklySetsRule()] }
    public static var setup: [SetupRule] { [TrainingSpacingRule(), DeloadRule(), CutBulkRateRule()] }

    static let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let weeklySets = 10...20
    /// The vault gives no session count for a stall; four sessions without a new best is the owner-approved reading.
    static let stallSessions = 4

    /// Primary muscle groups an exercise trains (chosen, else worked out from its name and group).
    static func primaryRegions(_ exerciseID: Int, db: Database) throws -> Set<MuscleRegion> {
        Set(try ExerciseMuscleService(db).muscles(exerciseId: exerciseID).assignments.filter { $0.role == .primary }.map(\.part.region))
    }
}

struct TrainingSpacingRule: SetupRule {
    let id = "training-spacing"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        let days = try db.query("SELECT id, weekday FROM plan_days WHERE weekday IS NOT NULL ORDER BY weekday").map { ($0.int("id"), $0.int("weekday")) }
        var regions: [Int: Set<MuscleRegion>] = [:]
        for (dayID, weekday) in days {
            for row in try db.query("SELECT exercise_id FROM plan_entries WHERE day_id = ?", [.int(Int64(dayID))]) {
                regions[weekday, default: []].formUnion(try TrainingRules.primaryRegions(row.int("exercise_id"), db: db))
            }
        }
        var clashes: [String] = []
        for weekday in regions.keys.sorted() {
            let next = weekday % 7 + 1
            let shared = (regions[weekday] ?? []).intersection(regions[next] ?? [])
            guard !shared.isEmpty else { continue }
            let names = shared.map(\.displayName).sorted().joined(separator: ", ")
            clashes.append("\(TrainingRules.weekdayNames[weekday - 1]) and \(TrainingRules.weekdayNames[next - 1]) both train \(names)")
        }
        guard !clashes.isEmpty else { return [] }
        return [Insight(ruleID: id, kind: .setup, severity: .improve, title: "Back-to-back days",
                        detail: "\(clashes.joined(separator: "; ")). Spread the days (for example Mon/Wed/Fri).",
                        why: "Vault: leave about 48 h before training the same muscle hard again (it recovers in 48-72 h), and muscle stays sensitive to protein for 24-48 h after lifting, so spread days use more of that window.")]
    }
}

struct DeloadRule: SetupRule {
    let id = "deload"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        let settings = try SettingsRepository(db).load()
        guard !settings.deload.enabled else { return [] }
        let since = settings.historyStartDate.string
        let why = "Vault: deload every 4-8 weeks, or sooner when a key lift drops 2 sessions in a row: about 40-60% of your sets, moderate weights, several reps short of failure, same days."

        for name in try dropping(db, since: since) {
            return [Insight(ruleID: id, kind: .setup, severity: .improve, title: "Deload suggested",
                            detail: "\(name) dropped 2 sessions in a row.", why: why, action: .turnOnDeload)]
        }
        if case .fired = try UnderRecoveredRule().evaluate(on: day.adding(days: -1), db: db) {
            return [Insight(ruleID: id, kind: .setup, severity: .improve, title: "Deload suggested",
                            detail: "3 or more under-recovery signs two weeks running.", why: why, action: .turnOnDeload)]
        }
        let lastDeload = try db.query("SELECT MAX(performed_on) AS d FROM set_logs WHERE is_deload = 1 AND performed_on >= ?", [.text(since)]).first?.optionalText("d")
        let firstSet = try db.query("SELECT MIN(performed_on) AS d FROM set_logs WHERE performed_on >= ?", [.text(since)]).first?.optionalText("d")
        if let start = (lastDeload ?? firstSet).flatMap(ISODate.init) {
            let weeks = day.days(since: start) / 7
            if weeks >= 4 {
                return [Insight(ruleID: id, kind: .setup, severity: weeks >= 8 ? .improve : .tip, title: "Deload due",
                                detail: "\(weeks) weeks without a deload\(lastDeload == nil ? " logged" : ""). Plan one every 4-8 weeks.", why: why, action: .turnOnDeload)]
            }
        }
        for name in try stalled(db, since: since) {
            return [Insight(ruleID: id, kind: .setup, severity: .tip, title: "Key lift stalled",
                            detail: "\(name) has not beaten its best in \(TrainingRules.stallSessions) sessions. Add rest: a missed session beats a heroic one.", why: why)]
        }
        return []
    }

    /// The first exercise of each plan day is its key lift.
    private func keyLifts(_ db: Database) throws -> [(id: Int, name: String)] {
        try db.query("""
            SELECT e.id, e.name FROM plan_days d JOIN plan_entries p ON p.day_id = d.id JOIN exercises e ON e.id = p.exercise_id
            WHERE p.position = (SELECT MIN(position) FROM plan_entries WHERE day_id = d.id) ORDER BY d.position
            """).map { ($0.int("id"), $0.text("name")) }
    }

    /// Best estimated 1RM per session, oldest first.
    private func sessions(_ exercise: Int, db: Database, since: String) throws -> [Double] {
        var best: [String: Double] = [:]
        for row in try db.query("SELECT performed_on, weight_kg, reps FROM set_logs WHERE exercise_id = ? AND is_deload = 0 AND performed_on >= ?",
                                [.int(Int64(exercise)), .text(since)]) {
            let estimate = SessionHistory.epleyEstimate(weightKg: row.double("weight_kg"), reps: row.int("reps"))
            best[row.text("performed_on")] = max(best[row.text("performed_on")] ?? 0, estimate)
        }
        return best.keys.sorted().compactMap { best[$0] }
    }

    private func dropping(_ db: Database, since: String) throws -> [String] {
        try keyLifts(db).filter { lift in
            let last = try sessions(lift.id, db: db, since: since).suffix(3)
            return last.count == 3 && last[last.startIndex + 1] < last[last.startIndex] && last[last.startIndex + 2] < last[last.startIndex + 1]
        }.map(\.name)
    }

    private func stalled(_ db: Database, since: String) throws -> [String] {
        try keyLifts(db).filter { lift in
            let all = try sessions(lift.id, db: db, since: since)
            guard all.count > TrainingRules.stallSessions else { return false }
            let earlierBest = all.dropLast(TrainingRules.stallSessions).max() ?? 0
            return (all.suffix(TrainingRules.stallSessions).max() ?? 0) <= earlierBest
        }.map(\.name)
    }
}

struct WeeklySetsRule: DailyRule {
    let id = "weekly-sets"
    let title = "Weekly sets"
    let checksToday = false

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let rows = try db.query("""
            SELECT exercise_id, COUNT(*) AS n FROM set_logs WHERE is_deload = 0 AND performed_on BETWEEN ? AND ? GROUP BY exercise_id
            """, [.text(day.adding(days: -6).string), .text(day.string)])
        guard !rows.isEmpty else { return .noData }
        var sets: [MuscleRegion: Int] = [:]
        for row in rows {
            for region in try TrainingRules.primaryRegions(row.int("exercise_id"), db: db) { sets[region, default: 0] += row.int("n") }
        }
        let targets = try PlanMuscleCoverageService(db).targets()
        let outside = sets.filter { region, count in
            let target = targets[region] ?? MuscleSetTarget(region: region)
            return !target.contains(count)
        }.sorted { $0.key.displayName < $1.key.displayName }
        guard !outside.isEmpty else { return .ok }
        let itemsText = outside.map { region, count in
            let target = targets[region] ?? MuscleSetTarget(region: region)
            let rangeHint = target.isCustom ? " (aim \(target.minSets)-\(target.maxSets))" : ""
            return "\(region.displayName) \(count) set\(count == 1 ? "" : "s")\(rangeHint)"
        }.joined(separator: ", ")
        return .fired(Insight(ruleID: id, kind: .today, severity: .tip, title: title,
                              detail: itemsText + " in the last 7 days; aim for 10-20 hard sets per muscle (or your configured range).",
                              why: "Vault: 10-20 hard sets per muscle a week, 1-3 reps short of failure.", day: day))
    }
}

struct CutBulkRateRule: SetupRule {
    let id = "cut-bulk-rate"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        if let refeed = try RefeedService(db).lastRefeed(onOrBefore: day), day.days(since: refeed) <= RefeedRules.quietDaysAfterRefeed { return [] }
        guard let advice = try? CalorieService(db).advice(asOf: day) else { return [] }
        let change = (advice.averages.currentAverageKg - advice.averages.pastAverageKg) / advice.averages.pastAverageKg * 100
        let multiplier = advice.target.multiplier
        let explicitMode = try SettingsRepository(db).load().explicitGoalMode
        let isCutting = explicitMode.map { $0 == .cut } ?? (multiplier < 1)
        let isBulking = explicitMode.map { $0 == .bulk } ?? (multiplier > 1)
        if isCutting {
            let loss = -change
            guard loss > 1 || loss < 0.5 else { return [] }
            return [Insight(ruleID: id, kind: .setup, severity: .tip, title: loss > 1 ? "Cutting fast" : "Cutting slowly",
                            detail: "Losing \(String(format: "%.1f", loss))% of body weight a week; aim for 0.5-1% (leaner people near 0.5%).",
                            why: "Vault: a cut of 0.5-1% of body weight a week, deficit about 300-700 kcal, keeps muscle.")]
        }
        if isBulking, multiplier > 1, !(1.05...1.10).contains(multiplier) {
            return [Insight(ruleID: id, kind: .setup, severity: .tip, title: "Surplus size",
                            detail: "The target is \(String(format: "%.0f", (multiplier - 1) * 100))% over maintenance; a lean bulk is 5-10% (about 200-400 kcal).",
                            why: "Vault: a surplus of 5-10% builds muscle; about 15% mostly adds fat.")]
        }
        return []
    }
}
