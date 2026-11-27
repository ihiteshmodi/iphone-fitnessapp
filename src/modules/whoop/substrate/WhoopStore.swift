import CryptoKit
import Foundation

public struct WhoopBatteryRow: Equatable, Sendable {
    public let deviceID: String
    public let ts: Int
    public let batteryPct: Double?
    public let charging: Bool?
    public let wristOn: Bool?
    public let millivolts: Int?
    public let chargeUnits: Int?
    public let source: String

    public init(deviceID: String = "", ts: Int, batteryPct: Double?, charging: Bool?, wristOn: Bool?,
                millivolts: Int?, chargeUnits: Int?, source: String) {
        self.deviceID = deviceID
        self.ts = ts
        self.batteryPct = batteryPct
        self.charging = charging
        self.wristOn = wristOn
        self.millivolts = millivolts
        self.chargeUnits = chargeUnits
        self.source = source
    }
}

public struct WhoopBacklogRow: Equatable, Sendable {
    public let deviceID: String
    public let ts: Int
    public let written: Int
    public let used: Int
    public let capacity: Int
    public let trimPage: Int
    public let wrapCount: Int
    public let freeRecords: Int
    public let deviceFamily: String

    public init(deviceID: String = "", ts: Int, written: Int, used: Int, capacity: Int,
                trimPage: Int, wrapCount: Int, freeRecords: Int, deviceFamily: String) {
        self.deviceID = deviceID
        self.ts = ts
        self.written = written
        self.used = used
        self.capacity = capacity
        self.trimPage = trimPage
        self.wrapCount = wrapCount
        self.freeRecords = freeRecords
        self.deviceFamily = deviceFamily
    }
}

public struct WhoopRawArchiveRow: Equatable, Sendable {
    public let deviceID: String
    public let counter: Int?
    public let packetType: Int
    public let recTs: Int?
    public let capturedAtMs: Int64
    public let reason: String
    public let frame: Data

    public init(deviceID: String = "", counter: Int?, packetType: Int, recTs: Int?,
                capturedAtMs: Int64, reason: String, frame: Data) {
        self.deviceID = deviceID
        self.counter = counter
        self.packetType = packetType
        self.recTs = recTs
        self.capturedAtMs = capturedAtMs
        self.reason = reason
        self.frame = frame
    }
}

public struct WhoopLiveCoverageRow: Equatable, Sendable {
    public let startTs: Int
    public let endTs: Int
    public let steps: Int
    public let day: String
    public let source: String
    public let deviceID: String

    public init(startTs: Int, endTs: Int, steps: Int, day: String, source: String = "band", deviceID: String = "") {
        self.startTs = startTs
        self.endTs = endTs
        self.steps = steps
        self.day = day
        self.source = source
        self.deviceID = deviceID
    }
}

public struct WhoopEventRow: Equatable, Sendable {
    public let deviceID: String
    public let rawInnerHex: String
    public let info: WhoopEventInfo
    public let capturedAtMs: Int64

    public init(deviceID: String = "", rawInnerHex: String, info: WhoopEventInfo, capturedAtMs: Int64) {
        self.deviceID = deviceID
        self.rawInnerHex = rawInnerHex
        self.info = info
        self.capturedAtMs = capturedAtMs
    }
}

public struct WhoopSyncBatch: Equatable, Sendable {
    public var deviceID: String
    public var gen4Records: [WhoopR24Record]
    public var gen4R10Records: [WhoopR10Lite]
    public var gen5Samples: [WhoopGen5HistorySample]
    public var ecgRawPackets: [WhoopLabradorR16Raw]
    public var archives: [WhoopRawArchiveRow]
    public var events: [WhoopEventRow]
    public var batteryRows: [WhoopBatteryRow]
    public var backlogRows: [WhoopBacklogRow]
    public var liveCoverageSpans: [WhoopLiveCoverageRow]
    public var trimTokenHex: String?
    public var capturedAtMs: Int64

    public init(deviceID: String = "", gen4Records: [WhoopR24Record] = [], gen4R10Records: [WhoopR10Lite] = [],
                gen5Samples: [WhoopGen5HistorySample] = [], ecgRawPackets: [WhoopLabradorR16Raw] = [],
                archives: [WhoopRawArchiveRow] = [], events: [WhoopEventRow] = [],
                batteryRows: [WhoopBatteryRow] = [], backlogRows: [WhoopBacklogRow] = [],
                liveCoverageSpans: [WhoopLiveCoverageRow] = [], trimTokenHex: String? = nil, capturedAtMs: Int64) {
        self.deviceID = deviceID
        self.gen4Records = gen4Records
        self.gen4R10Records = gen4R10Records
        self.gen5Samples = gen5Samples
        self.ecgRawPackets = ecgRawPackets
        self.archives = archives
        self.events = events
        self.batteryRows = batteryRows
        self.backlogRows = backlogRows
        self.liveCoverageSpans = liveCoverageSpans
        self.trimTokenHex = trimTokenHex
        self.capturedAtMs = capturedAtMs
    }

    public var hadDurableRows: Bool {
        !gen4Records.isEmpty || !gen4R10Records.isEmpty || !gen5Samples.isEmpty || !ecgRawPackets.isEmpty
            || archives.contains { $0.reason != "gate_dropped" }
    }
}

public struct WhoopSubstrateSummary: Equatable, Sendable {
    public let oneHzCount: Int
    public let rrCount: Int
    public let rawArchiveCount: Int
    public let liveCoverageCount: Int
    public let oldestRecTs: Int?
    public let latestRecTs: Int?
    public let latestCounter: Int?
    public let strapTrimHex: String?
    public let latestBatteryPct: Double?
    public let latestCharging: Bool?
    public var importedBaselineOneHzCount: Int
    public var importedBaselineMaxRecTs: Int?
    public var appSyncedOneHzCount: Int
    public var lastAppSyncAtSec: Int?

    public init(oneHzCount: Int, rrCount: Int, rawArchiveCount: Int, liveCoverageCount: Int,
                oldestRecTs: Int?, latestRecTs: Int?, latestCounter: Int?,
                strapTrimHex: String?, latestBatteryPct: Double?, latestCharging: Bool?,
                importedBaselineOneHzCount: Int = 0, importedBaselineMaxRecTs: Int? = nil,
                appSyncedOneHzCount: Int = 0, lastAppSyncAtSec: Int? = nil) {
        self.oneHzCount = oneHzCount
        self.rrCount = rrCount
        self.rawArchiveCount = rawArchiveCount
        self.liveCoverageCount = liveCoverageCount
        self.oldestRecTs = oldestRecTs
        self.latestRecTs = latestRecTs
        self.latestCounter = latestCounter
        self.strapTrimHex = strapTrimHex
        self.latestBatteryPct = latestBatteryPct
        self.latestCharging = latestCharging
        self.importedBaselineOneHzCount = importedBaselineOneHzCount
        self.importedBaselineMaxRecTs = importedBaselineMaxRecTs
        self.appSyncedOneHzCount = appSyncedOneHzCount
        self.lastAppSyncAtSec = lastAppSyncAtSec
    }
}

public struct WhoopMergeResult: Equatable, Sendable {
    public let addedOneHzRows: Int
    public let addedRrRows: Int
    public let addedArchiveRows: Int

    public init(addedOneHzRows: Int = 0, addedRrRows: Int = 0, addedArchiveRows: Int = 0) {
        self.addedOneHzRows = addedOneHzRows
        self.addedRrRows = addedRrRows
        self.addedArchiveRows = addedArchiveRows
    }
}

public enum WhoopLivePedometer {
    /// Minimal 100 Hz stride-periodicity pedometer for `live_coverage` windows while live IMU `0x33`/`0x2B` is active.
    public static func countSteps(frames: [WhoopImuFrame]) -> Int {
        let mags = frames.flatMap(\.mags)
        guard mags.count >= 25 else { return 0 }
        let mean = mags.reduce(0, +) / Double(mags.count)
        let dyn = mags.map { max(0.0, $0 - max(0.85, mean)) }
        var steps = 0
        var lastPeakIdx = -30
        for i in 1..<(dyn.count - 1) {
            if dyn[i] > 0.18 && dyn[i] >= dyn[i - 1] && dyn[i] > dyn[i + 1] && (i - lastPeakIdx) >= 28 {
                steps += 1
                lastPeakIdx = i
            }
        }
        return steps
    }
}

public final class WhoopStore {
    private static let countableTables: Set<String> = [
        "decoded_onehz", "decoded_rr", "live_coverage", "raw_archive_frames",
        "band_battery", "band_backlog", "band_events", "events", "sync_cursor",
        "samples", "ecg_reading", "ecg_reading_packet", "ecg_raw_packet",
    ]

    public let db: Database

    public init(_ db: Database) throws {
        self.db = db
        try WhoopSubstrateSchema.apply(to: db)
    }

    public static func inMemory() throws -> WhoopStore {
        try WhoopStore(try Database(path: ":memory:"))
    }

    /// Commits a sync batch inside a single `BEGIN IMMEDIATE ... COMMIT` with `PRAGMA synchronous = FULL`
    /// BEFORE `0x17` flash-trim ACK may be transmitted.
    public func commitSyncBatch(_ batch: WhoopSyncBatch) throws {
        if db.path != ":memory:" {
            try db.execute("PRAGMA synchronous = FULL")
        }
        let updatedSec = Int64(batch.capturedAtMs / 1000)

        let beforeOneHz = try count("decoded_onehz")

        try db.transaction {
            var maxCounter: Int64?
            var maxRecTs: Int64?

            func trackHighWater(counter: Int, recTs: Int) {
                let c = Int64(counter)
                let t = Int64(recTs)
                if maxCounter == nil || c > maxCounter! { maxCounter = c }
                if maxRecTs == nil || t > maxRecTs! { maxRecTs = t }
            }

            func replaceRR(deviceID: String, tsMs: Int64, recTs: Int, subsec: Int?, rrMs: [Int], family: String) throws {
                try db.execute("DELETE FROM decoded_rr WHERE device_id = ? AND ts_ms = ?", [
                    .text(deviceID), .int(tsMs),
                ])
                guard !rrMs.isEmpty else { return }
                let beatTimes = WhoopBeatTiming.beatTimesMs(recTs: recTs, tsSubsec: subsec, rrMs: rrMs)
                for (idx, rr) in rrMs.enumerated() {
                    let beatTs = idx < beatTimes.count ? beatTimes[idx] : nil
                    let rrTsMs = beatTs ?? tsMs
                    try db.execute("""
                        INSERT INTO decoded_rr (
                            device_id, ts_ms, rec_ts, beat_index, rr_ts_ms, rr_ms, device_family, source, beat_ts_ms
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, 'band', ?)
                        """, [
                        .text(deviceID), .int(tsMs), .int(Int64(recTs)),
                        .int(Int64(idx)), .int(rrTsMs), .int(Int64(rr)),
                        .text(family), .optional(beatTs),
                    ])
                }
            }

            for rec in batch.gen4Records {
                let tsMs = Int64(rec.tsEpoch) * 1000
                let hrVal: Int? = rec.hr > 0 ? rec.hr : nil
                let ax: Double? = rec.accelG.count > 0 ? rec.accelG[0] : nil
                let ay: Double? = rec.accelG.count > 1 ? rec.accelG[1] : nil
                let az: Double? = rec.accelG.count > 2 ? rec.accelG[2] : nil
                let spo2Red: Int? = rec.spo2RedRaw > 0 ? rec.spo2RedRaw : nil
                let spo2Ir: Int? = rec.spo2IrRaw > 0 ? rec.spo2IrRaw : nil
                try db.execute("""
                    INSERT OR REPLACE INTO decoded_onehz (
                        device_id, ts_ms, rec_ts, counter, hr, ax, ay, az,
                        spo2_red_raw, spo2_ir_raw, skin_temp_raw, ambient_raw,
                        hr_valid, device_family, source, ts_subsec
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'gen4', 'band', ?)
                    """, [
                    .text(batch.deviceID), .int(tsMs), .int(Int64(rec.tsEpoch)),
                    .int(Int64(rec.counter)), .optional(hrVal),
                    .optional(ax), .optional(ay), .optional(az),
                    .optional(spo2Red), .optional(spo2Ir),
                    .int(Int64(rec.skinTempRaw)), .int(Int64(rec.ambientRaw)),
                    .int(hrVal != nil ? 1 : 0), .int(Int64(rec.tsSubsec)),
                ])
                try replaceRR(deviceID: batch.deviceID, tsMs: tsMs, recTs: rec.tsEpoch, subsec: rec.tsSubsec, rrMs: rec.rrIntervalsMs, family: "gen4")
                trackHighWater(counter: rec.counter, recTs: rec.tsEpoch)
            }

            for r10 in batch.gen4R10Records {
                let tsMs = Int64(r10.tsEpoch) * 1000
                let hrVal: Int? = r10.hr > 0 ? r10.hr : nil
                try db.execute("""
                    INSERT OR REPLACE INTO decoded_onehz (
                        device_id, ts_ms, rec_ts, counter, hr, hr_valid, device_family, source, ts_subsec
                    ) VALUES (?, ?, ?, ?, ?, ?, 'gen4', 'band', 0)
                    """, [
                    .text(batch.deviceID), .int(tsMs), .int(Int64(r10.tsEpoch)),
                    .int(Int64(r10.counter)), .optional(hrVal), .int(hrVal != nil ? 1 : 0),
                ])
                try replaceRR(deviceID: batch.deviceID, tsMs: tsMs, recTs: r10.tsEpoch, subsec: nil, rrMs: r10.rrIntervalsMs, family: "gen4")
                trackHighWater(counter: r10.counter, recTs: r10.tsEpoch)
            }

            for s in batch.gen5Samples {
                let tsMs = Int64(s.unix) * 1000
                let hrVal: Int? = s.heartRate > 0 ? s.heartRate : nil
                let hrAltVal: Int? = s.heartRateAlt > 0 ? s.heartRateAlt : nil
                let ax: Double? = s.gravityG.count > 0 ? s.gravityG[0] : nil
                let ay: Double? = s.gravityG.count > 1 ? s.gravityG[1] : nil
                let az: Double? = s.gravityG.count > 2 ? s.gravityG[2] : nil
                try db.execute("""
                    INSERT OR REPLACE INTO decoded_onehz (
                        device_id, ts_ms, rec_ts, counter, hr, ax, ay, az,
                        spo2_red_raw, skin_temp_raw, step_count, step_cadence, activity_class,
                        skin_temp_c, hr_valid, hr_alt, device_family, source,
                        temp_ch2_c, temp_ch3_c, signal_quality_logvar, dyn_accel_g, ts_subsec, band_sleep_state
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'gen5', 'band', ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(batch.deviceID), .int(tsMs), .int(Int64(s.unix)),
                    .int(Int64(s.recordIndex)), .optional(hrVal),
                    .optional(ax), .optional(ay), .optional(az),
                    .int(Int64(s.spo2CandidateRaw)), .int(Int64(s.skinTempRawCenti)),
                    .int(Int64(s.stepMotionCounter)), .int(Int64(s.stepCadence)),
                    .optional(s.activityClassKnown), .optional(s.skinTempCOrNull),
                    .int(hrVal != nil ? 1 : 0), .optional(hrAltVal),
                    .optional(s.tempAux1C), .optional(s.tempAux2C),
                    .optional(s.signalQualityLogVariance), .optional(s.dynamicAccelerationG),
                    .int(Int64(s.tsSubsec)), .int(Int64(s.sleepStateRawNibble)),
                ])
                try replaceRR(deviceID: batch.deviceID, tsMs: tsMs, recTs: s.unix, subsec: s.tsSubsec, rrMs: s.rrIntervalsMs, family: "gen5")
                trackHighWater(counter: s.recordIndex, recTs: s.unix)
            }

            for ecg in batch.ecgRawPackets {
                try db.execute("""
                    INSERT OR REPLACE INTO ecg_raw_packet (
                        hex, device_id, sequence, strap_seconds, strap_subsec, captured_at
                    ) VALUES (?, ?, ?, ?, ?, ?)
                    """, [
                    .text(ecg.innerHex), .text(batch.deviceID),
                    .int(Int64(ecg.sequence)), .int(Int64(ecg.strapSeconds)),
                    .int(Int64(ecg.subseconds)), .int(batch.capturedAtMs),
                ])
                trackHighWater(counter: ecg.sequence, recTs: ecg.strapSeconds)
            }

            for arch in batch.archives {
                let devID = arch.deviceID.isEmpty ? batch.deviceID : arch.deviceID
                let digest = Insecure.SHA1.hash(data: arch.frame)
                let hashData = Data(digest)
                try db.execute("""
                    INSERT OR IGNORE INTO raw_archive_frames (
                        device_id, hash, counter, packet_type, rec_ts, captured_at, reason, frame
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .blob(hashData), .optional(arch.counter),
                    .int(Int64(arch.packetType)), .optional(arch.recTs),
                    .int(arch.capturedAtMs), .text(arch.reason), .blob(arch.frame),
                ])
            }

            for ev in batch.events {
                let devID = ev.deviceID.isEmpty ? batch.deviceID : ev.deviceID
                try db.execute("""
                    INSERT OR REPLACE INTO band_events (
                        device_id, hex, event_id, name, ts, payload_json, captured_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .text(ev.rawInnerHex),
                    .int(Int64(ev.info.eventID)), .text(ev.info.name),
                    .int(Int64(ev.info.tsEpoch)), .text(ev.info.payloadJSON),
                    .int(ev.capturedAtMs),
                ])
                try db.execute("""
                    INSERT OR REPLACE INTO events (device_id, hex, event_id, ts, captured_at)
                    VALUES (?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .text(ev.rawInnerHex),
                    .int(Int64(ev.info.eventID)), .int(Int64(ev.info.tsEpoch)),
                    .int(ev.capturedAtMs),
                ])
            }

            for b in batch.batteryRows {
                let devID = b.deviceID.isEmpty ? batch.deviceID : b.deviceID
                try db.execute("""
                    INSERT OR REPLACE INTO band_battery (
                        device_id, ts, battery_pct, charging, wrist_on, millivolts, charge_units, source
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .int(Int64(b.ts)), .optional(b.batteryPct),
                    .optional(b.charging.map { $0 ? 1 : 0 }),
                    .optional(b.wristOn.map { $0 ? 1 : 0 }),
                    .optional(b.millivolts), .optional(b.chargeUnits), .text(b.source),
                ])
            }

            for bl in batch.backlogRows {
                let devID = bl.deviceID.isEmpty ? batch.deviceID : bl.deviceID
                try db.execute("""
                    INSERT OR REPLACE INTO band_backlog (
                        device_id, ts, written, used, capacity, trim_page, wrap_count, free_records, device_family
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """, [
                    .text(devID), .int(Int64(bl.ts)), .int(Int64(bl.written)), .int(Int64(bl.used)),
                    .int(Int64(bl.capacity)), .int(Int64(bl.trimPage)),
                    .int(Int64(bl.wrapCount)), .int(Int64(bl.freeRecords)), .text(bl.deviceFamily),
                ])
            }

            for span in batch.liveCoverageSpans {
                let devID = span.deviceID.isEmpty ? batch.deviceID : span.deviceID
                try db.execute("""
                    INSERT INTO live_coverage (start_ts, end_ts, steps, day, source, device_id)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, [
                    .int(Int64(span.startTs)), .int(Int64(span.endTs)), .int(Int64(span.steps)),
                    .text(span.day), .text(span.source), .text(devID),
                ])
            }

            if let maxC = maxCounter {
                let prev = Int64(try cursorValue("counter_hw") ?? "") ?? 0
                if maxC > prev {
                    try upsertCursor(name: "counter_hw", value: String(maxC), updatedAt: updatedSec)
                }
            }
            if let maxT = maxRecTs {
                let prev = Int64(try cursorValue("rec_ts_hw") ?? "") ?? 0
                if maxT > prev {
                    try upsertCursor(name: "rec_ts_hw", value: String(maxT), updatedAt: updatedSec)
                }
            }
            if let trimHex = batch.trimTokenHex {
                try upsertCursor(name: "strap_trim", value: trimHex, updatedAt: updatedSec)
            }

            let afterOneHz = try count("decoded_onehz")
            let netAdded = max(0, afterOneHz - beforeOneHz)
            if netAdded > 0 || !batch.gen4Records.isEmpty || !batch.gen4R10Records.isEmpty || !batch.gen5Samples.isEmpty {
                let prevAppSynced = Int(try cursorValue("fitnessapp_synced_onehz") ?? "") ?? 0
                try upsertCursor(name: "fitnessapp_synced_onehz", value: String(prevAppSynced + netAdded), updatedAt: updatedSec)
                try upsertCursor(name: "fitnessapp_last_sync_at", value: String(updatedSec), updatedAt: updatedSec)
            }
        }
    }

    public func upsertCursor(name: String, value: String, updatedAt: Int64) throws {
        try db.execute("""
            INSERT INTO sync_cursor (name, value, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(name) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at
            """, [.text(name), .text(value), .int(updatedAt)])
    }

    public func cursorValue(_ name: String) throws -> String? {
        try db.query("SELECT value FROM sync_cursor WHERE name = ?", [.text(name)]).first?.optionalText("value")
    }

    public func count(_ table: String) throws -> Int {
        guard Self.countableTables.contains(table) else { throw ValidationError("Unknown WHOOP table \(table)") }
        return try db.query("SELECT COUNT(*) AS c FROM \(table)").first?.int("c") ?? 0
    }

    public func summary() throws -> WhoopSubstrateSummary {
        let oneHzRow = try db.query("""
            SELECT COUNT(*) AS c, MIN(rec_ts) AS min_ts, MAX(rec_ts) AS max_ts, MAX(counter) AS max_c
            FROM decoded_onehz
            """).first
        let oneHzCount = oneHzRow?.int("c") ?? 0
        let rrCount = try count("decoded_rr")
        let rawArchiveCount = try count("raw_archive_frames")
        let liveCoverageCount = try count("live_coverage")
        let strapTrim = try cursorValue("strap_trim")
        let importedBase = Int(try cursorValue("imported_baseline_onehz") ?? "") ?? 0
        let importedMaxTs = (try cursorValue("imported_baseline_max_ts")).flatMap(Int.init)
        let explicitAppSynced = (try cursorValue("fitnessapp_synced_onehz")).flatMap(Int.init)
        let appSynced = explicitAppSynced ?? max(0, oneHzCount - importedBase)
        let lastAppSync = (try cursorValue("fitnessapp_last_sync_at")).flatMap(Int.init)
        let battRow = try db.query("""
            SELECT battery_pct, charging FROM band_battery
            WHERE battery_pct IS NOT NULL
            ORDER BY ts DESC LIMIT 1
            """).first
        return WhoopSubstrateSummary(
            oneHzCount: oneHzCount,
            rrCount: rrCount,
            rawArchiveCount: rawArchiveCount,
            liveCoverageCount: liveCoverageCount,
            oldestRecTs: oneHzCount > 0 ? oneHzRow?.optionalInt("min_ts") : nil,
            latestRecTs: oneHzCount > 0 ? oneHzRow?.optionalInt("max_ts") : nil,
            latestCounter: oneHzCount > 0 ? oneHzRow?.optionalInt("max_c") : nil,
            strapTrimHex: strapTrim,
            latestBatteryPct: battRow?.optionalDouble("battery_pct"),
            latestCharging: battRow?.optionalInt("charging").map { $0 != 0 },
            importedBaselineOneHzCount: importedBase,
            importedBaselineMaxRecTs: importedMaxTs,
            appSyncedOneHzCount: appSynced,
            lastAppSyncAtSec: lastAppSync)
    }

    public func batteryHistory(limit: Int = 40) throws -> [WhoopBatteryRow] {
        let rows = try db.query("""
            SELECT device_id, ts, battery_pct, charging, wrist_on, millivolts, charge_units, source
            FROM band_battery
            WHERE battery_pct IS NOT NULL
            ORDER BY ts DESC
            LIMIT ?
            """, [.int(Int64(max(1, limit)))])
        return rows.reversed().map { r in
            WhoopBatteryRow(
                deviceID: r.optionalText("device_id") ?? "",
                ts: r.int("ts"),
                batteryPct: r.optionalDouble("battery_pct"),
                charging: r.optionalInt("charging").map { $0 != 0 },
                wristOn: r.optionalInt("wrist_on").map { $0 != 0 },
                millivolts: r.optionalInt("millivolts"),
                chargeUnits: r.optionalInt("charge_units"),
                source: r.optionalText("source") ?? "band"
            )
        }
    }

    /// Stages `[onsetSec, offsetSec]` directly from `decoded_onehz` + `decoded_rr` using the 4-class cardiorespiratory stager.
    public func stageSleepFromSubstrate(onsetSec: Int64, offsetSec: Int64, sleepSource: String = "override") throws -> WhoopSleepSegmentation? {
        let inBed = Int(offsetSec - onsetSec)
        guard inBed >= 1800 && inBed <= 64_800 else { return nil }
        let oneHzRows = try db.query("""
            SELECT rec_ts, hr, ax, ay, az, band_sleep_state
            FROM decoded_onehz
            WHERE rec_ts >= ? AND rec_ts < ?
            ORDER BY rec_ts ASC
            """, [.int(onsetSec), .int(offsetSec)])
        guard !oneHzRows.isEmpty else { return nil }

        var ax = [Double?](repeating: nil, count: inBed)
        var ay = [Double?](repeating: nil, count: inBed)
        var az = [Double?](repeating: nil, count: inBed)
        var hr = [Int](repeating: 0, count: inBed)
        var sleepState = [Int?](repeating: nil, count: inBed)

        for r in oneHzRows {
            let idx = Int(Int64(r.int("rec_ts")) - onsetSec)
            guard idx >= 0 && idx < inBed else { continue }
            ax[idx] = r.optionalDouble("ax")
            ay[idx] = r.optionalDouble("ay")
            az[idx] = r.optionalDouble("az")
            hr[idx] = r.optionalInt("hr") ?? 0
            sleepState[idx] = r.optionalInt("band_sleep_state")
        }

        let rrRows = try db.query("""
            SELECT COALESCE(beat_ts_ms, rr_ts_ms) AS b_ms, rr_ms
            FROM decoded_rr
            WHERE rec_ts >= ? AND rec_ts < ?
            ORDER BY rec_ts ASC, beat_index ASC
            """, [.int(onsetSec), .int(offsetSec)])
        var rrMs: [Double] = []
        var rrTsMs: [Int64] = []
        for r in rrRows {
            if let v = r.optionalInt("rr_ms"), let b = r.optionalInt64("b_ms") {
                rrMs.append(Double(v))
                rrTsMs.append(b)
            }
        }

        var trimSec: Int? = nil
        var effOffset = offsetSec
        if sleepSource == "auto" {
            let trimmed = WhoopSleepAndNapEngine.bandTrimmedOffsetSec(startSec: onsetSec, endSec: offsetSec, bandStates: sleepState)
            if trimmed.trimmedEndSec < offsetSec {
                trimSec = trimmed.trimmedSec ?? Int(offsetSec - trimmed.trimmedEndSec)
                effOffset = trimmed.trimmedEndSec
            }
        }
        let effLen = Int(effOffset - onsetSec)
        return WhoopSleepAndNapEngine.stageSleepWindow(
            onsetSec: onsetSec,
            offsetSec: effOffset,
            bandOffsetTrimSec: trimSec,
            sleepSource: sleepSource,
            ax: Array(ax.prefix(effLen)),
            ay: Array(ay.prefix(effLen)),
            az: Array(az.prefix(effLen)),
            hr: Array(hr.prefix(effLen)),
            rrMs: rrMs,
            rrTsMs: rrTsMs
        )
    }

    /// Runs automatic model derivations (`HRV`, `RHR`, `Sleep`, `Strain`, `Readiness`, `Auto-Workouts`, `Naps`) upon wake sync completion.
    public func runAutomaticWakeDerivation(
        ageYears: Double = 30.0,
        isFemale: Bool = false,
        stepTicksPerStep: Double = 1.0,
        calendar: Calendar = .current
    ) throws {
        guard let latestSec = try summary().latestRecTs else { return }
        let latestDate = Date(timeIntervalSince1970: TimeInterval(latestSec))
        let comps = calendar.dateComponents([.year, .month, .day], from: latestDate)
        let dayStr = String(format: "%04d-%02d-%02d", comps.year ?? 2026, comps.month ?? 1, comps.day ?? 1)
        guard let iso = ISODate(dayStr),
              let bounds = WhoopSubstrateGates.calendarDayBounds(for: iso, calendar: calendar) else { return }

        let analyticsStore = WhoopAnalyticsStore(db)
        let stepRes = try WhoopStepsEngine.countStepsFromDatabase(
            whoopDb: db, startSec: bounds.dayStartSec, endSec: bounds.dayEndSec, stepTicksPerStep: stepTicksPerStep
        )
        if stepRes.steps > 0 {
            try db.execute("INSERT OR REPLACE INTO metric_series (date, key, value) VALUES (?, 'steps', ?)",
                           [.text(dayStr), .double(Double(stepRes.steps))])
        }

        // Day waking HR -> Strain + Auto-Workout & Nap proposal detection
        let dayRows = try db.query("""
            SELECT rec_ts, hr, ax, ay, az, dyn_accel_g
            FROM decoded_onehz
            WHERE rec_ts >= ? AND rec_ts < ?
            ORDER BY rec_ts ASC
            """, [.int(bounds.dayStartSec), .int(bounds.dayEndSec)])
        guard !dayRows.isEmpty else { return }

        var tsArr: [Int64] = []
        var hrArr: [Int] = []
        var axArr: [Double?] = []
        var ayArr: [Double?] = []
        var azArr: [Double?] = []
        var motArr: [Double?] = []
        var byMin: [Int64: [Int]] = [:]

        for r in dayRows {
            let ts = Int64(r.int("rec_ts"))
            let h = r.optionalInt("hr") ?? 0
            tsArr.append(ts)
            hrArr.append(h)
            axArr.append(r.optionalDouble("ax"))
            ayArr.append(r.optionalDouble("ay"))
            azArr.append(r.optionalDouble("az"))
            motArr.append(r.optionalDouble("dyn_accel_g"))
            let pHr = WhoopSubstrateGates.plausibleHrOrZero(h)
            if pHr > 0 { byMin[ts / 60, default: []].append(pHr) }
        }

        let rhrRecent = try db.query("SELECT value FROM metric_series WHERE key = 'rhr' AND date <= ? ORDER BY date DESC LIMIT 1", [.text(dayStr)])
            .first?.optionalDouble("value") ?? 54.0
        let maxHr = WhoopReadinessAndStrainEngine.estimatedTanakaMaxHr(ageYears: ageYears)

        if !byMin.isEmpty {
            let wakeMins = byMin.values.map { Double($0.reduce(0, +)) / Double($0.count) }
            if let strainRes = WhoopReadinessAndStrainEngine.computeDailyStrain(
                wakeMinuteHr: wakeMins, rhr: rhrRecent, maxHr: maxHr, isFemale: isFemale,
                priorQuietHrr: [0.12, 0.12, 0.12], sessionMaxStrain: nil
            ) {
                try db.execute("INSERT OR REPLACE INTO metric_series (date, key, value) VALUES (?, 'strain', ?)",
                               [.text(dayStr), .double(strainRes.strain)])
                try db.execute("INSERT OR REPLACE INTO metric_series (date, key, value) VALUES (?, 'trimp', ?)",
                               [.text(dayStr), .double(strainRes.grossTrimp)])
            }
        }

        // Queue any newly auto-detected workout bouts
        let detectedWorkouts = WhoopAutoWorkoutDetector.detect(
            dayId: dayStr, tsSec: tsArr, hr: hrArr, motionIntensityG: motArr,
            rhr: Int(rhrRecent.rounded()), maxHr: Int(maxHr.rounded())
        )
        if !detectedWorkouts.isEmpty {
            try WhoopAutoWorkoutDetector.queueProposals(detectedWorkouts, into: analyticsStore, nowSec: Int64(latestSec))
        }

        // Queue any newly auto-detected daytime naps
        let onWrist = hrArr.map { WhoopSubstrateGates.plausibleHrOrZero($0) > 0 }
        let chg = [Bool](repeating: false, count: tsArr.count)
        let detectedNaps = WhoopSleepAndNapEngine.detectNaps(
            tsSec: tsArr, ax: axArr, ay: ayArr, az: azArr, hr: hrArr,
            onWrist: onWrist, charging: chg,
            dayStartSec: bounds.dayStartSec, dayEndSec: bounds.dayEndSec,
            mainSleepUntrimmed: nil, tonightSleepOnsetSec: nil
        )
        for nap in detectedNaps {
            let pid = "nap:\(nap.startSec)"
            let durMin = max(1, Int((nap.endSec - nap.startSec) / 60))
            let json = "{\"start\":\(nap.startSec),\"end\":\(nap.endSec),\"duration_min\":\(durMin),\"confidence\":\(String(format: "%.2f", nap.confidence))}"
            try analyticsStore.upsertProposal(WhoopActivityProposal(
                id: pid, kind: "nap", dayId: dayStr, startTs: nap.startSec, endTs: nap.endSec,
                detectionStart: nap.startSec, detectionEnd: nap.endSec,
                detailsJson: json, status: "pending", revision: 0
            ), nowSec: Int64(latestSec))
        }
    }

    private static func hexToData(_ hex: String) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex, let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) {
            if let b = UInt8(hex[idx..<next], radix: 16) { bytes.append(b) }
            idx = next
        }
        return Data(bytes)
    }
}

public struct WhoopDatabaseFileService {
    public static let notWhoopDatabase = "This is not a WHOOP / OpenStrap database"
    private static let sqliteHeader = Array("SQLite format 3\0".utf8)
    private static let requiredTables: Set<String> = ["decoded_onehz", "decoded_rr", "sync_cursor"]

    public let location: AppDatabaseLocation

    public init(location: AppDatabaseLocation) {
        self.location = location
    }

    public var databaseURL: URL { location.directory.appendingPathComponent("whoop.sqlite") }
    public var exists: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }

    public func openLiveStore() throws -> WhoopStore? {
        guard exists else { return nil }
        return try WhoopStore(try Database(path: databaseURL.path))
    }

    public func openOrCreateLiveStore() throws -> WhoopStore {
        try FileManager.default.createDirectory(at: location.directory, withIntermediateDirectories: true)
        return try WhoopStore(try Database(path: databaseURL.path))
    }

    public func validate(fileAt url: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { throw ValidationError(Self.notWhoopDatabase) }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: Self.sqliteHeader.count)) ?? Data()
        guard Array(header) == Self.sqliteHeader else { throw ValidationError(Self.notWhoopDatabase) }

        let probe = try Database(path: url.path, readOnly: true)
        let tables = Set(try probe.query("SELECT name FROM sqlite_master WHERE type = 'table'").map { $0.text("name") })
        guard Self.requiredTables.isSubset(of: tables) else { throw ValidationError(Self.notWhoopDatabase) }
    }

    public func importDatabase(from source: URL, today: ISODate? = nil) throws {
        try validate(fileAt: source)
        let fm = FileManager.default
        try fm.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let staged = location.directory.appendingPathComponent(".whoop-import-\(UUID().uuidString).tmp")
        do {
            try fm.copyItem(at: source, to: staged)
            try validate(fileAt: staged)
            let stagedStore = try WhoopStore(try Database(path: staged.path))
            if (try stagedStore.cursorValue("fitnessapp_synced_onehz")) == nil,
               (try stagedStore.cursorValue("imported_baseline_onehz")) == nil {
                let totalRows = try stagedStore.count("decoded_onehz")
                let maxRecTs = try stagedStore.db.query("SELECT MAX(rec_ts) AS m FROM decoded_onehz").first?.optionalInt("m")
                let stamp = Int64(Date().timeIntervalSince1970)
                try stagedStore.upsertCursor(name: "imported_baseline_onehz", value: String(totalRows), updatedAt: stamp)
                if let maxRecTs {
                    try stagedStore.upsertCursor(name: "imported_baseline_max_ts", value: String(maxRecTs), updatedAt: stamp)
                }
            }
            if exists {
                if let today {
                    try fm.createDirectory(at: location.backupsDirectory, withIntermediateDirectories: true)
                    var n = 1
                    var backup: URL
                    repeat {
                        backup = location.backupsDirectory.appendingPathComponent("whoop-before-import-\(today)-\(n).sqlite")
                        n += 1
                    } while fm.fileExists(atPath: backup.path)
                    try fm.moveItem(at: databaseURL, to: backup)
                } else {
                    try fm.removeItem(at: databaseURL)
                }
                for suffix in ["-wal", "-shm", "-journal"] {
                    try? fm.removeItem(atPath: databaseURL.path + suffix)
                }
            }
            try fm.moveItem(at: staged, to: databaseURL)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
    }

    public func export(from db: Database, today: ISODate, to directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        var target = directory.appendingPathComponent("whoop-\(today).sqlite")
        var suffix = 2
        while fm.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("whoop-\(today)-\(suffix).sqlite")
            suffix += 1
        }
        do {
            try db.execute("VACUUM INTO ?", [.text(target.path)])
            try validate(fileAt: target)
        } catch {
            try? fm.removeItem(at: target)
            throw error
        }
        return target
    }

    public func filesInDocuments() -> [URL] {
        let fm = FileManager.default
        var candidates: [URL] = []
        for dir in [location.directory, location.inboxDirectory] {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items {
                let ext = item.pathExtension.lowercased()
                let name = item.lastPathComponent.lowercased()
                guard ext == "sqlite" || ext == "db" else { continue }
                guard name != "fitness.sqlite" && name != "whoop.sqlite" && !name.hasPrefix("fitness-") else { continue }
                if (try? validate(fileAt: item)) != nil {
                    candidates.append(item)
                }
            }
        }
        return candidates.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Non-destructively merges historical OpenStrap / WHOOP records from `source` into `liveStore` using `INSERT OR IGNORE`
    /// so live BLE rows and `strap_trim` cursor in `liveStore` always win on overlap.
    public func mergeDatabase(from source: URL, into liveStore: WhoopStore, nowSec: Int64) throws -> WhoopMergeResult {
        try validate(fileAt: source)
        let fm = FileManager.default
        try fm.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let staged = location.directory.appendingPathComponent(".whoop-merge-\(UUID().uuidString).tmp")
        defer {
            try? fm.removeItem(at: staged)
            for suffix in ["-wal", "-shm", "-journal"] {
                try? fm.removeItem(atPath: staged.path + suffix)
            }
        }
        try fm.copyItem(at: source, to: staged)
        do {
            let upgraded = try WhoopStore(try Database(path: staged.path))
            _ = upgraded
        }

        let beforeOneHz = try liveStore.count("decoded_onehz")
        let beforeRr = try liveStore.count("decoded_rr")
        let beforeArchive = try liveStore.count("raw_archive_frames")

        try liveStore.db.execute("ATTACH DATABASE ? AS ext_hist", [.text(staged.path)])
        var detached = false
        defer {
            if !detached { try? liveStore.db.execute("DETACH DATABASE ext_hist") }
        }

        let extMaxTs = try liveStore.db.query("SELECT MAX(rec_ts) AS m FROM ext_hist.decoded_onehz").first?.optionalInt("m")

        try liveStore.db.transaction {
            try liveStore.db.execute("""
                INSERT OR IGNORE INTO decoded_onehz (
                    device_id, ts_ms, rec_ts, counter, hr, ax, ay, az,
                    spo2_red_raw, spo2_ir_raw, skin_temp_raw, step_count, step_cadence, activity_class,
                    skin_temp_c, on_wrist, hr_valid, hr_alt, ambient_raw, device_family, source,
                    temp_ch2_c, temp_ch3_c, signal_quality_logvar, dyn_accel_g, ts_subsec, band_sleep_state
                )
                SELECT
                    device_id, ts_ms, rec_ts, counter, hr, ax, ay, az,
                    spo2_red_raw, spo2_ir_raw, skin_temp_raw, step_count, step_cadence, activity_class,
                    skin_temp_c, on_wrist, hr_valid, hr_alt, ambient_raw, device_family, source,
                    temp_ch2_c, temp_ch3_c, signal_quality_logvar, dyn_accel_g, ts_subsec, band_sleep_state
                FROM ext_hist.decoded_onehz
                """)

            try liveStore.db.execute("""
                INSERT OR IGNORE INTO decoded_rr (
                    device_id, ts_ms, rec_ts, beat_index, rr_ts_ms, rr_ms, device_family, source, beat_ts_ms
                )
                SELECT r.device_id, r.ts_ms, r.rec_ts, r.beat_index, r.rr_ts_ms, r.rr_ms, r.device_family, r.source, r.beat_ts_ms
                FROM ext_hist.decoded_rr r
                WHERE NOT EXISTS (
                    SELECT 1 FROM decoded_rr existing
                    WHERE existing.device_id = r.device_id AND existing.ts_ms = r.ts_ms
                )
                """)

            try liveStore.db.execute("""
                INSERT OR IGNORE INTO raw_archive_frames (
                    device_id, hash, counter, packet_type, rec_ts, captured_at, reason, hex, frame
                )
                SELECT device_id, hash, counter, packet_type, rec_ts, captured_at, reason, hex, frame
                FROM ext_hist.raw_archive_frames
                """)

            try liveStore.db.execute("""
                INSERT OR IGNORE INTO band_battery (
                    device_id, ts, battery_pct, charging, wrist_on, millivolts, charge_units, source
                )
                SELECT device_id, ts, battery_pct, charging, wrist_on, millivolts, charge_units, source
                FROM ext_hist.band_battery
                """)

            try liveStore.db.execute("""
                INSERT OR IGNORE INTO band_backlog (
                    device_id, ts, written, used, capacity, trim_page, wrap_count, free_records, device_family
                )
                SELECT device_id, ts, written, used, capacity, trim_page, wrap_count, free_records, device_family
                FROM ext_hist.band_backlog
                """)

            try liveStore.db.execute("""
                INSERT OR IGNORE INTO band_events (
                    device_id, hex, event_id, name, ts, payload_json, captured_at
                )
                SELECT device_id, hex, event_id, name, ts, payload_json, captured_at
                FROM ext_hist.band_events
                """)

            try liveStore.db.execute("""
                INSERT OR IGNORE INTO live_coverage (start_ts, end_ts, steps, day, source, device_id)
                SELECT c.start_ts, c.end_ts, c.steps, c.day, c.source, c.device_id
                FROM ext_hist.live_coverage c
                WHERE NOT EXISTS (
                    SELECT 1 FROM live_coverage existing
                    WHERE existing.device_id = c.device_id AND existing.start_ts = c.start_ts
                )
                """)
        }

        try liveStore.db.execute("DETACH DATABASE ext_hist")
        detached = true

        let addedOneHz = max(0, (try liveStore.count("decoded_onehz")) - beforeOneHz)
        let addedRr = max(0, (try liveStore.count("decoded_rr")) - beforeRr)
        let addedArchive = max(0, (try liveStore.count("raw_archive_frames")) - beforeArchive)

        let prevImported = Int(try liveStore.cursorValue("imported_baseline_onehz") ?? "") ?? 0
        try liveStore.upsertCursor(name: "imported_baseline_onehz", value: String(prevImported + addedOneHz), updatedAt: nowSec)
        if let extMaxTs {
            let prevMax = Int(try liveStore.cursorValue("imported_baseline_max_ts") ?? "") ?? 0
            if extMaxTs > prevMax {
                try liveStore.upsertCursor(name: "imported_baseline_max_ts", value: String(extMaxTs), updatedAt: nowSec)
            }
        }

        return WhoopMergeResult(addedOneHzRows: addedOneHz, addedRrRows: addedRr, addedArchiveRows: addedArchive)
    }
}
