import Foundation

public struct MuscleSetTarget: Equatable, Identifiable {
    public static let defaultMin = 10
    public static let defaultMax = 20

    public var id: String { region.rawValue }
    public let region: MuscleRegion
    public let minSets: Int
    public let maxSets: Int
    public let isCustom: Bool

    public init(region: MuscleRegion, minSets: Int = Self.defaultMin, maxSets: Int = Self.defaultMax, isCustom: Bool = false) {
        self.region = region
        self.minSets = minSets
        self.maxSets = maxSets
        self.isCustom = isCustom
    }

    public func contains(_ sets: Int) -> Bool {
        (minSets...maxSets).contains(sets)
    }

    public var rangeLabel: String {
        "\(minSets)–\(maxSets)"
    }
}

public enum MuscleCoverageState: Equatable {
    case met
    case optionalMet
    case under
    case over
}

public struct MuscleRegionCoverage: Equatable, Identifiable {
    public var id: String { region.rawValue }
    public let region: MuscleRegion
    public let plannedSets: Int
    public let target: MuscleSetTarget

    public var state: MuscleCoverageState {
        if plannedSets < target.minSets { return .under }
        if plannedSets > target.maxSets { return .over }
        return target.minSets == 0 ? .optionalMet : .met
    }
}

public struct PlanDayMuscleCount: Equatable, Identifiable {
    public var id: String { region.rawValue }
    public let region: MuscleRegion
    public let sets: Int
}

public struct PlanDayMuscleSummary: Equatable {
    public let dayID: Int
    public let workingSets: Int
    public let items: [PlanDayMuscleCount]

    public var summaryText: String {
        items.map { "\($0.region.displayName) \($0.sets)" }.joined(separator: " · ")
    }
}

public struct PlanMuscleCoverageReport: Equatable {
    public let dayCount: Int
    public let perDay: [Int: PlanDayMuscleSummary]
    public let weekly: [MuscleRegionCoverage]

    public var requiredMusclesCount: Int {
        weekly.filter { $0.target.minSets > 0 }.count
    }

    public var metRequiredMusclesCount: Int {
        weekly.filter { $0.target.minSets > 0 && $0.state == .met }.count
    }
}

/// Manages configurable per-muscle weekly hard-set targets (default 10–20) and evaluates per-day and whole-plan coverage.
public final class PlanMuscleCoverageService {
    private let db: Database

    public init(_ db: Database) {
        self.db = db
    }

    public func targets() throws -> [MuscleRegion: MuscleSetTarget] {
        var map: [MuscleRegion: MuscleSetTarget] = Dictionary(uniqueKeysWithValues: MuscleRegion.allCases.map {
            ($0, MuscleSetTarget(region: $0))
        })
        let hasTable = !(try db.query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'muscle_set_targets'")).isEmpty
        guard hasTable else { return map }
        for row in try db.query("SELECT region, min_sets, max_sets FROM muscle_set_targets") {
            guard let region = MuscleRegion(rawValue: row.text("region")) else { continue }
            let lo = row.int("min_sets")
            let hi = row.int("max_sets")
            let custom = lo != MuscleSetTarget.defaultMin || hi != MuscleSetTarget.defaultMax
            map[region] = MuscleSetTarget(region: region, minSets: lo, maxSets: hi, isCustom: custom)
        }
        return map
    }

    public func allTargets() throws -> [MuscleSetTarget] {
        let map = try targets()
        return MuscleRegion.allCases.compactMap { map[$0] }
    }

    public func setTarget(region: MuscleRegion, minSets: Int, maxSets: Int) throws {
        guard minSets >= 0 else { throw ValidationError("Minimum sets cannot be negative") }
        guard minSets <= maxSets else { throw ValidationError("Minimum sets cannot exceed maximum sets") }
        if minSets == MuscleSetTarget.defaultMin && maxSets == MuscleSetTarget.defaultMax {
            try resetTarget(region: region)
            return
        }
        try db.execute("""
            INSERT INTO muscle_set_targets (region, min_sets, max_sets)
            VALUES (?, ?, ?)
            ON CONFLICT(region) DO UPDATE SET min_sets = excluded.min_sets, max_sets = excluded.max_sets
            """, [.text(region.rawValue), .int(Int64(minSets)), .int(Int64(maxSets))])
    }

    public func resetTarget(region: MuscleRegion) throws {
        try db.execute("DELETE FROM muscle_set_targets WHERE region = ?", [.text(region.rawValue)])
    }

    public func evaluatePlan() throws -> PlanMuscleCoverageReport {
        let dayIDs = try db.query("SELECT id FROM plan_days ORDER BY position").map { $0.int("id") }
        let muscleService = ExerciseMuscleService(db)
        let configured = try targets()

        var perDay: [Int: PlanDayMuscleSummary] = [:]
        var weeklyTotals: [MuscleRegion: Int] = [:]

        for dayID in dayIDs {
            var workingSets = 0
            var dayCounts: [MuscleRegion: Int] = [:]
            let rows = try db.query("SELECT exercise_id, sets FROM plan_entries WHERE day_id = ? ORDER BY position, id",
                                    [.int(Int64(dayID))])
            for row in rows {
                let sets = row.int("sets")
                workingSets += sets
                let primaryRegions = Set(try muscleService.muscles(exerciseId: row.int("exercise_id")).assignments
                    .filter { $0.role == .primary }
                    .map(\.part.region))
                for region in primaryRegions {
                    dayCounts[region, default: 0] += sets
                    weeklyTotals[region, default: 0] += sets
                }
            }
            let orderedItems = MuscleRegion.allCases.compactMap { region -> PlanDayMuscleCount? in
                guard let n = dayCounts[region], n > 0 else { return nil }
                return PlanDayMuscleCount(region: region, sets: n)
            }
            perDay[dayID] = PlanDayMuscleSummary(dayID: dayID, workingSets: workingSets, items: orderedItems)
        }

        let weekly = MuscleRegion.allCases.map { region in
            let target = configured[region] ?? MuscleSetTarget(region: region)
            return MuscleRegionCoverage(region: region, plannedSets: weeklyTotals[region] ?? 0, target: target)
        }
        return PlanMuscleCoverageReport(dayCount: dayIDs.count, perDay: perDay, weekly: weekly)
    }
}
