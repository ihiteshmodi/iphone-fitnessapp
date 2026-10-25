import Foundation

public enum MeasurementStatus: Equatable {
    case noReading
    case noTarget
    case atTarget
    /// Inches still to add to reach the target.
    case toGain(Double)
    /// Inches still to remove to reach the target.
    case toLose(Double)
}

/// Pure direction-aware goal maths. The notebook subtracted in one direction only, which showed shrink goals as negative.
public enum MeasurementGoal {
    public static func status(current: Double?, target: Double?) -> MeasurementStatus {
        guard let current else { return .noReading }
        guard let target else { return .noTarget }
        let remaining = target - current
        if abs(remaining) < 0.005 { return .atTarget }
        let inches = pyRound(abs(remaining), 2)
        return remaining > 0 ? .toGain(inches) : .toLose(inches)
    }

    /// 0...1 for the progress ring: current/target for growth goals, target/current for shrink goals.
    public static func fraction(current: Double?, target: Double?) -> Double {
        guard let current, let target, current > 0, target > 0 else { return 0 }
        let ratio = target >= current ? current / target : target / current
        return min(max(ratio, 0), 1)
    }
}

public struct MeasurementReading: Equatable, Identifiable {
    public let id: Int
    public let date: ISODate
    public let inches: Double
}

public struct MeasurementProgress: Equatable, Identifiable {
    public var id: String { site.lowercased() }
    public let site: String
    public let current: Double?
    public let target: Double
    public let status: MeasurementStatus
    public let fraction: Double
}

public struct MeasurementDetail: Equatable {
    public let site: String
    public let current: Double?
    public let target: Double?
    public let status: MeasurementStatus
    public let fraction: Double
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

    /// Sites that have a target, largest remaining distance first; sites without a reading come last.
    public func progress() throws -> [MeasurementProgress] {
        let targets = try db.query("SELECT site, inches FROM measurement_targets")
        let rows = try targets.map { row -> (progress: MeasurementProgress, distance: Double?) in
            let site = row.text("site")
            let target = row.double("inches")
            let current = try readings(site: site).last?.inches
            let progress = MeasurementProgress(site: site, current: current, target: target,
                                               status: MeasurementGoal.status(current: current, target: target),
                                               fraction: MeasurementGoal.fraction(current: current, target: target))
            return (progress, current.map { abs(target - $0) })
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
        let target = try db.query("SELECT inches FROM measurement_targets WHERE site = ?", [.text(name)]).first?.double("inches")
        let current = history.last?.inches
        return MeasurementDetail(site: name, current: current, target: target,
                                 status: MeasurementGoal.status(current: current, target: target),
                                 fraction: MeasurementGoal.fraction(current: current, target: target), history: history)
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

    /// A new site starts with one reading (dated today unless given) and a target.
    public func addSite(name: String, firstReading: Double, target: Double, on date: ISODate? = nil) throws {
        try validate(inches: firstReading)
        try validate(inches: target)
        let site = try canonicalName(name)
        if try db.query("SELECT 1 AS found FROM measurement_targets WHERE site = ?", [.text(site)]).first != nil {
            throw ValidationError("Site is already tracked")
        }
        let day = date ?? clock.today()
        try db.transaction {
            try insertReading(site: site, inches: firstReading, on: day)
            try db.execute("INSERT INTO measurement_targets (site, inches, set_on) VALUES (?, ?, ?)",
                           [.text(site), .double(target), .text(clock.today().string)])
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
