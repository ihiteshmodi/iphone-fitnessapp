import Foundation

public enum WhoopCoreConstants {
    public static let algoVersion: Int = 133
    public static let minPlausibleHr: Int = 25
    public static let maxPlausibleHr: Int = 230
    public static let minPlausibleRrMs: Double = 250.0
    public static let maxPlausibleRrMs: Double = 2400.0
    public static let maxSustainedAccelG2: Double = 16.0 // 4.0 g squared
    public static let nocturnalSearchLookbackSec: Int64 = 12 * 3600
    public static let napBoundaryBufferSec: Int64 = 3 * 3600
    public static let napLeadingEdgeContiguitySec: Int64 = 60
    public static let rhrMinSleepSec: Int = 10_800 // 3 hours
    public static let maxNapSec: Int = 10_800      // 3 hours
    public static let minNapSec: Int = 900         // 15 minutes
    public static let minManualNapSec: Int = 300   // 5 minutes
    public static let readinessZCap: Double = 5.0
    public static let familySeamKeys: Set<String> = ["skin_temp_adc"]
}

public enum WhoopSubstrateGates {
    @inline(__always)
    public static func plausibleHrOrZero(_ hr: Int?) -> Int {
        guard let hr, hr >= WhoopCoreConstants.minPlausibleHr && hr <= WhoopCoreConstants.maxPlausibleHr else {
            return 0
        }
        return hr
    }

    @inline(__always)
    public static func plausibleRrOrNil(_ rrMs: Double?) -> Double? {
        guard let rrMs, rrMs.isFinite,
              rrMs >= WhoopCoreConstants.minPlausibleRrMs && rrMs <= WhoopCoreConstants.maxPlausibleRrMs else {
            return nil
        }
        return rrMs
    }

    /// Valid iff finite and `0 < ax^2 + ay^2 + az^2 <= 16.0 g^2`. Exact `(0,0,0)` is absent (`false`), never immobile.
    @inline(__always)
    public static func accelPlausible(ax: Double?, ay: Double?, az: Double?) -> Bool {
        guard let ax, let ay, let az, ax.isFinite, ay.isFinite, az.isFinite else { return false }
        let m2 = ax * ax + ay * ay + az * az
        return m2 > 0.0 && m2 <= WhoopCoreConstants.maxSustainedAccelG2
    }

    /// Gen4 uses `skin_temp_raw` (integer ADC counts > 0); Gen5 uses `round(skin_temp_c * 100)` (integer centi-°C > 0).
    public static func consistentSkinTempUnit(family: String?, skinTempRaw: Int?, skinTempC: Double?) -> Int? {
        let fam = (family ?? "").lowercased()
        if fam.contains("gen5") || fam.contains("maverick") {
            guard let c = skinTempC, c.isFinite else { return nil }
            let centi = Int((c * 100.0).rounded())
            return centi > 0 ? centi : nil
        }
        if let raw = skinTempRaw, raw > 0 { return raw }
        if fam.isEmpty, let c = skinTempC, c.isFinite {
            let centi = Int((c * 100.0).rounded())
            return centi > 0 ? centi : nil
        }
        return nil
    }

    public static func monotonizeBeatAxis(_ rawTsMs: [Int64]) -> [Int64] {
        guard !rawTsMs.isEmpty else { return [] }
        var out = rawTsMs
        for i in 1..<out.count where out[i] <= out[i - 1] {
            out[i] = out[i - 1] + 1
        }
        return out
    }

    /// DST-exact `[dayStart, dayEnd)` local midnight bounds (never `dayStart + 86400`).
    public static func calendarDayBounds(for day: ISODate, calendar: Calendar = .current) -> (dayStartSec: Int64, dayEndSec: Int64)? {
        let parts = day.string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 0
        comps.minute = 0
        comps.second = 0
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return nil
        }
        return (Int64(start.timeIntervalSince1970), Int64(end.timeIntervalSince1970))
    }

    /// Excludes both this morning's `[sleepOnsetSec, sleepOffsetSec)` AND `t >= tonightSleepOnsetSec`.
    public static func isAsleep(tsSec: Int64, morningSleep: (onsetSec: Int64, offsetSec: Int64)?, tonightSleepOnsetSec: Int64?) -> Bool {
        if let m = morningSleep, tsSec >= m.onsetSec && tsSec < m.offsetSec {
            return true
        }
        if let tonight = tonightSleepOnsetSec, tsSec >= tonight {
            return true
        }
        return false
    }
}

public enum WhoopMath {
    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        let mid = s.count / 2
        return (s.count % 2 == 1) ? s[mid] : 0.5 * (s[mid - 1] + s[mid])
    }

    public static func mad(_ values: [Double], center: Double? = nil) -> Double? {
        guard let med = center ?? median(values) else { return nil }
        return median(values.map { abs($0 - med) })
    }

    public static func percentile(_ values: [Double], p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        if s.count == 1 { return s[0] }
        let idx = min(Double(s.count - 1), max(0.0, (p / 100.0) * Double(s.count - 1)))
        let lo = Int(floor(idx))
        let hi = Int(ceil(idx))
        if lo == hi { return s[lo] }
        let frac = idx - Double(lo)
        return s[lo] * (1.0 - frac) + s[hi] * frac
    }

    public static func quartileDeviation(_ values: [Double]) -> Double {
        guard let q25 = percentile(values, p: 25), let q75 = percentile(values, p: 75) else { return 0 }
        return 0.5 * (q75 - q25)
    }

    public static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    public static func sampleStdDev(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let ss = values.reduce(0.0) { $0 + ($1 - m) * ($1 - m) }
        return sqrt(ss / Double(values.count - 1))
    }

    /// Normalized Lomb–Scargle periodogram power at angular frequency `omega = 2 * pi * freqHz`.
    public static func lombScarglePower(timesSec: [Double], centeredValues: [Double], freqHz: Double) -> Double {
        let n = min(timesSec.count, centeredValues.count)
        guard n >= 4, freqHz > 0 else { return 0 }
        let w = 2.0 * .pi * freqHz
        var sin2wt = 0.0
        var cos2wt = 0.0
        for i in 0..<n {
            let twoWt = 2.0 * w * timesSec[i]
            sin2wt += sin(twoWt)
            cos2wt += cos(twoWt)
        }
        let tau = atan2(sin2wt, cos2wt) / (2.0 * w)
        var yc = 0.0, ys = 0.0, cc = 0.0, ss = 0.0
        for i in 0..<n {
            let arg = w * (timesSec[i] - tau)
            let c = cos(arg)
            let s = sin(arg)
            yc += centeredValues[i] * c
            ys += centeredValues[i] * s
            cc += c * c
            ss += s * s
        }
        let p1 = cc > 1e-12 ? (yc * yc) / cc : 0
        let p2 = ss > 1e-12 ? (ys * ys) / ss : 0
        return 0.5 * (p1 + p2)
    }
}

public struct WhoopDatedMetric: Equatable, Sendable {
    public let date: String
    public let key: String
    public let value: Double

    public init(date: String, key: String, value: Double) {
        self.date = date
        self.key = key
        self.value = value
    }
}

public struct WhoopRecalculatedStages: Codable, Equatable, Sendable {
    public let tstMin: Int
    public let deepMin: Int
    public let remMin: Int
    public let lightMin: Int
    public let wasoMin: Int
    public let efficiencyPct: Int
    public let awakenings: Int

    public init(tstMin: Int, deepMin: Int, remMin: Int, lightMin: Int, wasoMin: Int, efficiencyPct: Int, awakenings: Int) {
        self.tstMin = tstMin
        self.deepMin = deepMin
        self.remMin = remMin
        self.lightMin = lightMin
        self.wasoMin = wasoMin
        self.efficiencyPct = efficiencyPct
        self.awakenings = awakenings
    }
}

public struct WhoopSleepOverrideRecord: Equatable, Sendable {
    public let dayId: String
    public let startTs: Int64
    public let endTs: Int64
    public let source: String
    public let note: String?
    public let recalculatedStages: WhoopRecalculatedStages?

    public init(dayId: String, startTs: Int64, endTs: Int64, source: String, note: String?, recalculatedStages: WhoopRecalculatedStages? = nil) {
        self.dayId = dayId
        self.startTs = startTs
        self.endTs = endTs
        self.source = source
        self.note = note
        self.recalculatedStages = recalculatedStages
    }
}

public struct WhoopNapRecord: Equatable, Sendable {
    public let dayId: String
    public let startTs: Int64
    public let endTs: Int64
    public let source: String // "manual" | "accepted" | "rejected"
    public let payloadJson: String?

    public var durationSec: Int { max(0, Int(endTs - startTs)) }
}

public struct WhoopActivityProposal: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: String // "workout" | "nap"
    public let dayId: String
    public var startTs: Int64
    public var endTs: Int64
    public let detectionStart: Int64
    public let detectionEnd: Int64
    public var detailsJson: String
    public var status: String // "pending" | "accepted" | "discarded" | "superseded"
    public var revision: Int
}

/// Full editable CRUD persistence layer over `whoop.sqlite` analytics, overrides, naps, cycle logs, and activity proposals.
public final class WhoopAnalyticsStore {
    private let db: Database

    public init(_ db: Database) {
        self.db = db
    }

    // MARK: Sleep Overrides (Edit / Clear)

    public func sleepOverride(for dayId: String) throws -> WhoopSleepOverrideRecord? {
        try db.query("SELECT day_id, onset_ts, offset_ts, source, note, stages_json FROM sleep_override WHERE day_id = ?", [.text(dayId)]).first.map { row in
            let stages: WhoopRecalculatedStages? = row.optionalText("stages_json").flatMap { json in
                try? JSONDecoder().decode(WhoopRecalculatedStages.self, from: Data(json.utf8))
            }
            return WhoopSleepOverrideRecord(
                dayId: row.text("day_id"),
                startTs: row.optionalInt64("onset_ts") ?? 0,
                endTs: row.optionalInt64("offset_ts") ?? 0,
                source: row.text("source"),
                note: row.optionalText("note"),
                recalculatedStages: stages
            )
        }
    }

    public func upsertSleepOverride(
        dayId: String,
        startTs: Int64,
        endTs: Int64,
        source: String = "manual",
        note: String? = nil,
        recalculatedStages: WhoopRecalculatedStages? = nil,
        nowSec: Int64 = 0
    ) throws {
        let dur = endTs - startTs
        guard dur >= 1800 && dur <= 57_600 else {
            throw ValidationError("Sleep override must be between 30 minutes and 16 hours")
        }
        let stagesJson: String? = recalculatedStages.flatMap { st in
            (try? JSONEncoder().encode(st)).flatMap { String(data: $0, encoding: .utf8) }
        }
        try db.execute("""
            INSERT INTO sleep_override (day_id, onset_ts, offset_ts, source, created_at, note, stages_json)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(day_id) DO UPDATE SET
                onset_ts = excluded.onset_ts,
                offset_ts = excluded.offset_ts,
                source = excluded.source,
                note = excluded.note,
                stages_json = excluded.stages_json
            """, [.text(dayId), .int(startTs), .int(endTs), .text(source), .int(nowSec), .optional(note), .optional(stagesJson)])
    }

    public func deleteSleepOverride(dayId: String) throws {
        try db.execute("DELETE FROM sleep_override WHERE day_id = ?", [.text(dayId)])
    }

    // MARK: Naps (Manual Add / Edit Span / Reject / Delete)

    public func naps(for dayId: String) throws -> [WhoopNapRecord] {
        try db.query("SELECT day_id, start_ts, end_ts, source, payload_json FROM sleep_nap WHERE day_id = ? ORDER BY start_ts ASC",
                     [.text(dayId)]).map { row in
            WhoopNapRecord(dayId: row.text("day_id"), startTs: row.optionalInt64("start_ts") ?? 0,
                           endTs: row.optionalInt64("end_ts") ?? 0, source: row.text("source"),
                           payloadJson: row.optionalText("payload_json"))
        }
    }

    /// Returns accepted + manual naps bounded to `5 min .. 3 h`, excluding rejected windows (`dropOversizedNaps(applyNapEdits(...))`).
    public func effectiveNaps(for dayId: String) throws -> [WhoopNapRecord] {
        let all = try naps(for: dayId)
        let rejected = all.filter { $0.source == "rejected" }
        return all.filter { rec in
            guard rec.source == "manual" || rec.source == "accepted" else { return false }
            let dur = rec.durationSec
            guard dur >= WhoopCoreConstants.minManualNapSec && dur <= WhoopCoreConstants.maxNapSec else { return false }
            let overlapsRejected = rejected.contains { r in rec.startTs < r.endTs && r.startTs < rec.endTs }
            return !overlapsRejected
        }
    }

    public func upsertNap(dayId: String, startTs: Int64, endTs: Int64, source: String = "manual", payloadJson: String? = nil, nowSec: Int64 = 0) throws {
        let dur = Int(endTs - startTs)
        guard dur >= WhoopCoreConstants.minManualNapSec && dur <= WhoopCoreConstants.maxNapSec else {
            throw ValidationError("Nap duration must be between 5 minutes and 3 hours")
        }
        try db.execute("""
            INSERT INTO sleep_nap (day_id, start_ts, end_ts, source, created_at, payload_json)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(day_id, start_ts) DO UPDATE SET
                end_ts = excluded.end_ts,
                source = excluded.source,
                payload_json = COALESCE(excluded.payload_json, sleep_nap.payload_json)
            """, [.text(dayId), .int(startTs), .int(endTs), .text(source), .int(nowSec), .optional(payloadJson)])
    }

    public func updateNapSpan(dayId: String, oldStartTs: Int64, newStartTs: Int64, newEndTs: Int64, nowSec: Int64 = 0) throws {
        let dur = Int(newEndTs - newStartTs)
        guard dur >= WhoopCoreConstants.minManualNapSec && dur <= WhoopCoreConstants.maxNapSec else {
            throw ValidationError("Nap duration must be between 5 minutes and 3 hours")
        }
        let existing = try db.query("SELECT source, payload_json FROM sleep_nap WHERE day_id = ? AND start_ts = ?",
                                    [.text(dayId), .int(oldStartTs)]).first
        let src = existing?.optionalText("source") ?? "manual"
        let payload = existing?.optionalText("payload_json")
        try db.transaction {
            try db.execute("DELETE FROM sleep_nap WHERE day_id = ? AND start_ts = ?", [.text(dayId), .int(oldStartTs)])
            try upsertNap(dayId: dayId, startTs: newStartTs, endTs: newEndTs, source: src, payloadJson: payload, nowSec: nowSec)
        }
    }

    public func deleteNap(dayId: String, startTs: Int64) throws {
        try db.execute("DELETE FROM sleep_nap WHERE day_id = ? AND start_ts = ?", [.text(dayId), .int(startTs)])
    }

    // MARK: Activity Suggestions (Accept / Edit & Accept / Dismiss / Undo)

    public func activityProposals(status: String? = nil) throws -> [WhoopActivityProposal] {
        let rows: [Row]
        if let status {
            rows = try db.query("SELECT * FROM activity_suggestions WHERE status = ? ORDER BY start_ts DESC", [.text(status)])
        } else {
            rows = try db.query("SELECT * FROM activity_suggestions ORDER BY start_ts DESC")
        }
        return rows.map { row in
            WhoopActivityProposal(
                id: row.text("id"),
                kind: row.text("kind"),
                dayId: row.text("day_id"),
                startTs: row.optionalInt64("start_ts") ?? 0,
                endTs: row.optionalInt64("end_ts") ?? 0,
                detectionStart: row.optionalInt64("detection_start") ?? 0,
                detectionEnd: row.optionalInt64("detection_end") ?? 0,
                detailsJson: row.text("details_json"),
                status: row.text("status"),
                revision: row.int("revision")
            )
        }
    }

    public func upsertProposal(_ p: WhoopActivityProposal, nowSec: Int64 = 0) throws {
        try db.execute("""
            INSERT INTO activity_suggestions (
                id, kind, day_id, start_ts, end_ts, detection_start, detection_end,
                details_json, status, revision, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                start_ts = excluded.start_ts,
                end_ts = excluded.end_ts,
                details_json = excluded.details_json,
                status = excluded.status,
                revision = excluded.revision,
                updated_at = excluded.updated_at
            """, [
                .text(p.id), .text(p.kind), .text(p.dayId),
                .int(p.startTs), .int(p.endTs), .int(p.detectionStart), .int(p.detectionEnd),
                .text(p.detailsJson), .text(p.status), .int(Int64(p.revision)), .int(nowSec), .int(nowSec),
            ])
    }

    public func updateProposalStatus(id: String, status: String, editedStartTs: Int64? = nil, editedEndTs: Int64? = nil, editedDetailsJson: String? = nil, nowSec: Int64 = 0) throws {
        guard let existing = try db.query("SELECT * FROM activity_suggestions WHERE id = ?", [.text(id)]).first else {
            throw ValidationError("Activity proposal not found")
        }
        let sTs = editedStartTs ?? existing.optionalInt64("start_ts") ?? 0
        let eTs = editedEndTs ?? existing.optionalInt64("end_ts") ?? 0
        let det = editedDetailsJson ?? existing.text("details_json")
        let rev = existing.int("revision") + 1
        try db.execute("""
            UPDATE activity_suggestions
            SET status = ?, start_ts = ?, end_ts = ?, details_json = ?, revision = ?, updated_at = ?
            WHERE id = ?
            """, [.text(status), .int(sTs), .int(eTs), .text(det), .int(Int64(rev)), .int(nowSec), .text(id)])
    }

    // MARK: Metric Series & Cycle Log

    public func writeMetric(date: String, key: String, value: Double?) throws {
        if let value, value.isFinite {
            try db.execute("INSERT OR REPLACE INTO metric_series (date, key, value) VALUES (?, ?, ?)",
                           [.text(date), .text(key), .double(value)])
        } else {
            try db.execute("DELETE FROM metric_series WHERE date = ? AND key = ?", [.text(date), .text(key)])
        }
    }

    public func metricsBefore(date: String, key: String, maxDays: Int = 28) throws -> [Double] {
        try db.query("""
            SELECT value FROM metric_series
            WHERE key = ? AND date < ? AND value IS NOT NULL
            ORDER BY date DESC LIMIT ?
            """, [.text(key), .text(date), .int(Int64(maxDays))])
            .compactMap { $0.optionalDouble("value") }
            .reversed()
    }

    public func upsertCycleLog(date: String, kind: String = "start", note: String? = nil) throws {
        try db.execute("INSERT OR REPLACE INTO cycle_log (date, kind, note) VALUES (?, ?, ?)",
                       [.text(date), .text(kind), .optional(note)])
    }

    public func deleteCycleLog(date: String) throws {
        try db.execute("DELETE FROM cycle_log WHERE date = ?", [.text(date)])
    }
}
