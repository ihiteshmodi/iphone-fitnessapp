import Foundation

public enum MeasurementStatus: Equatable {
    case noReading
    case noTarget
    case atTarget
    /// Inches still to add to reach the target (a grow site below its target).
    case toGain(Double)
    /// Inches still to remove to reach the target (a reduce site above its target).
    case toLose(Double)
    /// Inches beyond the target in the wanted direction: a grow site above it, or a reduce site below it.
    case ahead(Double)
}

/// Whether being above the target is the goal (grow: shoulders, arms) or being below it (reduce: waist).
public enum MeasurementDirection: String, Equatable {
    case grow
    case reduce
}

/// How far from its target a site is, in the direction that matters.
public enum MeasurementAttention: Equatable {
    /// At the target, ahead of it, or short of it by no more than the tolerance.
    case onTrack
    /// Short of the target by more than the tolerance, up to `MeasurementGoal.offTargetPercent`.
    case watch
    /// Short of the target by more than `MeasurementGoal.offTargetPercent`.
    case off
}

/// Pure direction-aware goal maths. The notebook subtracted in one direction only, which showed shrink goals as negative
/// and growth sites above their target as "to lose".
public enum MeasurementGoal {
    /// Further than this from the target, in the wrong direction, is "off" (red) whatever the tolerance.
    public static let offTargetPercent = 10.0

    /// Current against target in percent of the target: positive above it, negative below it. One decimal.
    public static func percentFromTarget(current: Double?, target: Double?) -> Double? {
        guard let current, let target, target > 0 else { return nil }
        let percent = pyRound((current - target) / target * 100, 1)
        return percent == 0 ? 0 : percent
    }

    /// Colour band: only the wrong direction counts (a grow site above target, a reduce site below it, are on track).
    public static func attention(current: Double?, target: Double?, direction: MeasurementDirection, tolerancePercent: Double) -> MeasurementAttention? {
        guard let current, let target, target > 0 else { return nil }
        let wrongWay = direction == .grow ? target - current : current - target
        let percent = pyRound(max(wrongWay, 0) / target * 100, 2)
        if percent <= tolerancePercent { return .onTrack }
        return percent > max(offTargetPercent, tolerancePercent) ? .off : .watch
    }

    public static func status(current: Double?, target: Double?, direction: MeasurementDirection) -> MeasurementStatus {
        guard let current else { return .noReading }
        guard let target else { return .noTarget }
        let remaining = target - current
        if abs(remaining) < 0.005 { return .atTarget }
        let inches = pyRound(abs(remaining), 2)
        switch direction {
        case .grow: return remaining > 0 ? .toGain(inches) : .ahead(inches)
        case .reduce: return remaining < 0 ? .toLose(inches) : .ahead(inches)
        }
    }

    /// 0...1 for the progress ring: 1 once the goal is met in the wanted direction, otherwise how close the site is.
    public static func fraction(current: Double?, target: Double?, direction: MeasurementDirection) -> Double {
        guard let current, let target, current > 0, target > 0 else { return 0 }
        let met = direction == .grow ? current >= target : current <= target
        if met { return 1 }
        let ratio = direction == .grow ? current / target : target / current
        return min(max(ratio, 0), 1)
    }

    /// Inches still to go; zero once the goal is met. Used to put the sites that need work first.
    static func remaining(_ status: MeasurementStatus) -> Double? {
        switch status {
        case .toGain(let inches), .toLose(let inches): return inches
        case .atTarget, .ahead: return 0
        case .noReading, .noTarget: return nil
        }
    }
}

public struct MeasurementReading: Equatable, Identifiable {
    public let id: Int
    public let date: ISODate
    public let inches: Double
}

public struct SiteReading: Equatable {
    public let site: String
    public let reading: MeasurementReading
}

public struct MeasurementProgress: Equatable, Identifiable {
    public var id: String { site.lowercased() }
    public let site: String
    public let current: Double?
    public let target: Double
    public let direction: MeasurementDirection
    public let status: MeasurementStatus
    public let fraction: Double
    /// Current against target in percent of the target (positive above it); nil without a reading.
    public let percentFromTarget: Double?
    public let attention: MeasurementAttention?
}

public struct MeasurementDetail: Equatable {
    public let site: String
    public let current: Double?
    public let target: Double?
    public let direction: MeasurementDirection
    public let status: MeasurementStatus
    public let fraction: Double
    public let percentFromTarget: Double?
    public let attention: MeasurementAttention?
    /// Oldest first, ready for a line chart.
    public let history: [MeasurementReading]
}

public final class MeasurementService {
    private let db: Database
    private let clock: AppClock

    public init(_ db: Database, clock: AppClock = SystemClock()) {
        self.db = db
        self.clock = clock
    }

    /// Sites that have a target, the ones with the most still to do first; sites without a reading come last.
    public func progress() throws -> [MeasurementProgress] {
        let targets = try db.query("SELECT site, inches, direction FROM measurement_targets")
        let tolerance = try SettingsRepository(db).load().measurementTolerancePercent
        let rows = try targets.map { row -> (progress: MeasurementProgress, distance: Double?) in
            let site = row.text("site")
            let target = row.double("inches")
            let direction = MeasurementDirection(rawValue: row.text("direction")) ?? .grow
            let current = try readings(site: site).last?.inches
            let status = MeasurementGoal.status(current: current, target: target, direction: direction)
            let progress = MeasurementProgress(site: site, current: current, target: target, direction: direction, status: status,
                                               fraction: MeasurementGoal.fraction(current: current, target: target, direction: direction),
                                               percentFromTarget: MeasurementGoal.percentFromTarget(current: current, target: target),
                                               attention: MeasurementGoal.attention(current: current, target: target, direction: direction,
                                                                                    tolerancePercent: tolerance))
            return (progress, MeasurementGoal.remaining(status))
        }
        return rows.sorted { lhs, rhs in
            switch (lhs.distance, rhs.distance) {
            case let (left?, right?) where left != right: return left > right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.progress.site.localizedCaseInsensitiveCompare(rhs.progress.site) == .orderedAscending
            }
        }.map(\.progress)
    }

    /// Every site name that has a reading or a target, for pickers.
    public func sites() throws -> [String] {
        var seen = Set<String>()
        let names = try db.query("SELECT site FROM measurement_targets UNION ALL SELECT site FROM body_measurements").map { $0.text("site") }
        return names.filter { seen.insert($0.lowercased()).inserted }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    public func detail(site: String) throws -> MeasurementDetail {
        let name = try canonicalName(site)
        let history = try readings(site: name)
        let row = try db.query("SELECT inches, direction FROM measurement_targets WHERE site = ?", [.text(name)]).first
        let target = row?.double("inches")
        let direction = row.flatMap { MeasurementDirection(rawValue: $0.text("direction")) } ?? .grow
        let current = history.last?.inches
        let tolerance = try SettingsRepository(db).load().measurementTolerancePercent
        return MeasurementDetail(site: name, current: current, target: target, direction: direction,
                                 status: MeasurementGoal.status(current: current, target: target, direction: direction),
                                 fraction: MeasurementGoal.fraction(current: current, target: target, direction: direction),
                                 percentFromTarget: MeasurementGoal.percentFromTarget(current: current, target: target),
                                 attention: MeasurementGoal.attention(current: current, target: target, direction: direction, tolerancePercent: tolerance),
                                 history: history)
    }

    /// Switches a tracked site between "grow" and "reduce". The site needs a target.
    public func setDirection(site: String, _ direction: MeasurementDirection) throws {
        let name = try canonicalName(site)
        guard try db.query("SELECT 1 AS found FROM measurement_targets WHERE site = ?", [.text(name)]).first != nil else {
            throw ValidationError("Set a target for this site first")
        }
        try db.execute("UPDATE measurement_targets SET direction = ? WHERE site = ?", [.text(direction.rawValue), .text(name)])
    }

    public func setTarget(site: String, inches: Double) throws {
        try validate(inches: inches)
        let name = try canonicalName(site)
        try db.execute("""
            INSERT INTO measurement_targets (site, inches, set_on) VALUES (?, ?, ?)
            ON CONFLICT(site) DO UPDATE SET inches = excluded.inches, set_on = excluded.set_on
            """, [.text(name), .double(inches), .text(clock.today().string)])
    }

    @discardableResult
    public func logReading(site: String, inches: Double, on date: String) throws -> Int {
        try validate(inches: inches)
        let name = try canonicalName(site)
        let day = try validDate(date)
        return try insertReading(site: name, inches: inches, on: day)
    }

    @discardableResult
    public func logReading(site: String, inches: Double, on date: ISODate) throws -> Int {
        try logReading(site: site, inches: inches, on: date.string)
    }

    public func updateReading(id: Int, inches: Double, on date: String? = nil) throws {
        try validate(inches: inches)
        let day = try date.map(validDate)
        guard try db.query("SELECT 1 AS found FROM body_measurements WHERE id = ?", [.int(Int64(id))]).first != nil else {
            throw ValidationError("Entry not found")
        }
        try db.execute("UPDATE body_measurements SET inches = ?, measured_on = COALESCE(?, measured_on) WHERE id = ?",
                       [.double(inches), .optional(day?.string), .int(Int64(id))])
    }

    public func deleteReading(id: Int) throws {
        try db.execute("DELETE FROM body_measurements WHERE id = ?", [.int(Int64(id))])
    }

    /// A new site starts with one reading (dated today unless given) and a target. Unless told otherwise, a target below
    /// the first reading means "reduce".
    public func addSite(name: String, firstReading: Double, target: Double, direction: MeasurementDirection? = nil, on date: ISODate? = nil) throws {
        try validate(inches: firstReading)
        try validate(inches: target)
        let site = try canonicalName(name)
        if try db.query("SELECT 1 AS found FROM measurement_targets WHERE site = ?", [.text(site)]).first != nil {
            throw ValidationError("Site is already tracked")
        }
        let day = date ?? clock.today()
        let chosen = direction ?? (target < firstReading ? .reduce : .grow)
        try db.transaction {
            try insertReading(site: site, inches: firstReading, on: day)
            try db.execute("INSERT INTO measurement_targets (site, inches, set_on, direction) VALUES (?, ?, ?, ?)",
                           [.text(site), .double(target), .text(clock.today().string), .text(chosen.rawValue)])
        }
    }

    /// Removes the target. Readings are kept unless `deleteAllReadings` is true.
    public func removeSite(_ site: String, deleteAllReadings: Bool = false) throws {
        let name = try canonicalName(site)
        try db.transaction {
            try db.execute("DELETE FROM measurement_targets WHERE site = ?", [.text(name)])
            if deleteAllReadings { try db.execute("DELETE FROM body_measurements WHERE site = ?", [.text(name)]) }
        }
    }

    /// Every reading of every site taken on one day, so a wrong one can be found and fixed.
    public func readings(on date: ISODate) throws -> [SiteReading] {
        try db.query("SELECT id, site, measured_on, inches FROM body_measurements WHERE measured_on = ? ORDER BY site COLLATE NOCASE, id",
                     [.text(date.string)]).compactMap { row in
            guard let day = ISODate(row.text("measured_on")) else { return nil }
            return SiteReading(site: row.text("site"), reading: MeasurementReading(id: row.int("id"), date: day, inches: row.double("inches")))
        }
    }

    /// Oldest first; same-day readings keep entry order so the last one is the current value.
    private func readings(site: String) throws -> [MeasurementReading] {
        try db.query("SELECT id, measured_on, inches FROM body_measurements WHERE site = ? ORDER BY measured_on, id", [.text(site)])
            .compactMap { row in
                guard let day = ISODate(row.text("measured_on")) else { return nil }
                return MeasurementReading(id: row.int("id"), date: day, inches: row.double("inches"))
            }
    }

    @discardableResult
    private func insertReading(site: String, inches: Double, on day: ISODate) throws -> Int {
        try db.execute("INSERT INTO body_measurements (measured_on, site, inches) VALUES (?, ?, ?)",
                       [.text(day.string), .text(site), .double(inches)])
        return db.lastInsertRowID
    }

    /// Reuses the spelling already stored so "left calf" and "Left Calf" stay one site.
    private func canonicalName(_ site: String) throws -> String {
        let trimmed = site.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ValidationError("Site name is required") }
        let stored = try db.query("""
            SELECT site FROM measurement_targets WHERE site = ?1
            UNION ALL SELECT site FROM body_measurements WHERE site = ?1 LIMIT 1
            """, [.text(trimmed)]).first?.optionalText("site")
        return stored ?? trimmed
    }

    private func validate(inches: Double) throws {
        guard inches.isFinite, inches > 0 else { throw ValidationError("Measurement must be above 0") }
    }

    private func validDate(_ text: String) throws -> ISODate {
        guard let day = ISODate(text) else { throw ValidationError("Date is not valid") }
        return day
    }
}
