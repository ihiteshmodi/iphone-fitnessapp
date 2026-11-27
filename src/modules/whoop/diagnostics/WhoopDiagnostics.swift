import Foundation

public struct WhoopHandshakeTelemetry: Equatable, Sendable {
    public let detectedGeneration: String?
    public let firmwareVersion: String?
    public let sigprocVersion: String?
    public let serialNumber: String?
    public let batteryPct: Double?
    public let charging: Bool?
    public let wristOn: Bool?

    public init(detectedGeneration: String? = nil, firmwareVersion: String? = nil, sigprocVersion: String? = nil,
                serialNumber: String? = nil, batteryPct: Double? = nil, charging: Bool? = nil, wristOn: Bool? = nil) {
        self.detectedGeneration = detectedGeneration
        self.firmwareVersion = firmwareVersion
        self.sigprocVersion = sigprocVersion
        self.serialNumber = serialNumber
        self.batteryPct = batteryPct
        self.charging = charging
        self.wristOn = wristOn
    }
}

public struct WhoopBurstTelemetry: Equatable, Sendable {
    public let liveHrBpm: Int?
    public let liveRrMs: [Int]
    public let liveHrTimestamp: Int?
    public let rollingCrcErrorCount: Int
    public let headerCrcErrors: Int
    public let payloadCrc32Errors: Int
    public let resyncCount: Int
    public let offloadActive: Bool
    public let currentBurstDataPackets: Int
    public let currentBurstInlinePackets: Int
    public let lastExpectedPacketCount: Int?
    public let lastActualPacketCount: Int?
    public let lastAckVerdict: String
    public let lastAckWasNack: Bool?
    public let lastAckTokenHex: String?
    public let ackOkCount: Int
    public let nackCount: Int

    public init(liveHrBpm: Int? = nil, liveRrMs: [Int] = [], liveHrTimestamp: Int? = nil,
                rollingCrcErrorCount: Int = 0, headerCrcErrors: Int = 0, payloadCrc32Errors: Int = 0,
                resyncCount: Int = 0, offloadActive: Bool = false,
                currentBurstDataPackets: Int = 0, currentBurstInlinePackets: Int = 0,
                lastExpectedPacketCount: Int? = nil, lastActualPacketCount: Int? = nil,
                lastAckVerdict: String = "none", lastAckWasNack: Bool? = nil, lastAckTokenHex: String? = nil,
                ackOkCount: Int = 0, nackCount: Int = 0) {
        self.liveHrBpm = liveHrBpm
        self.liveRrMs = liveRrMs
        self.liveHrTimestamp = liveHrTimestamp
        self.rollingCrcErrorCount = rollingCrcErrorCount
        self.headerCrcErrors = headerCrcErrors
        self.payloadCrc32Errors = payloadCrc32Errors
        self.resyncCount = resyncCount
        self.offloadActive = offloadActive
        self.currentBurstDataPackets = currentBurstDataPackets
        self.currentBurstInlinePackets = currentBurstInlinePackets
        self.lastExpectedPacketCount = lastExpectedPacketCount
        self.lastActualPacketCount = lastActualPacketCount
        self.lastAckVerdict = lastAckVerdict
        self.lastAckWasNack = lastAckWasNack
        self.lastAckTokenHex = lastAckTokenHex
        self.ackOkCount = ackOkCount
        self.nackCount = nackCount
    }
}

public struct WhoopOneHzInspectorRow: Equatable, Sendable, Identifiable {
    public var id: String { "\(deviceID)#\(tsMs)" }
    public let deviceID: String
    public let tsMs: Int64
    public let recTs: Int?
    public let tsSubsec: Int?
    public let counter: Int
    public let hr: Int?
    public let ax: Double?
    public let ay: Double?
    public let az: Double?
    public let skinTempC: Double?
    public let skinTempRaw: Int?

    public init(deviceID: String, tsMs: Int64, recTs: Int?, tsSubsec: Int?, counter: Int,
                hr: Int?, ax: Double?, ay: Double?, az: Double?, skinTempC: Double?, skinTempRaw: Int?) {
        self.deviceID = deviceID
        self.tsMs = tsMs
        self.recTs = recTs
        self.tsSubsec = tsSubsec
        self.counter = counter
        self.hr = hr
        self.ax = ax
        self.ay = ay
        self.az = az
        self.skinTempC = skinTempC
        self.skinTempRaw = skinTempRaw
    }
}

public struct WhoopRrInspectorRow: Equatable, Sendable, Identifiable {
    public var id: String { "\(deviceID)#\(tsMs)#\(beatIndex)" }
    public let deviceID: String
    public let tsMs: Int64
    public let recTs: Int
    public let beatIndex: Int
    public let rrMs: Int
    public let beatTsMs: Int64?

    public init(deviceID: String, tsMs: Int64, recTs: Int, beatIndex: Int, rrMs: Int, beatTsMs: Int64?) {
        self.deviceID = deviceID
        self.tsMs = tsMs
        self.recTs = recTs
        self.beatIndex = beatIndex
        self.rrMs = rrMs
        self.beatTsMs = beatTsMs
    }
}

public struct WhoopSqliteInspectionSnapshot: Equatable, Sendable {
    public let schemaTables: [String]
    public let oneHzCount: Int
    public let rrCount: Int
    public let rawArchiveCount: Int
    public let liveCoverageCount: Int
    public let batteryCount: Int
    public let backlogCount: Int
    public let eventsCount: Int
    public let counterHw: String?
    public let recTsHw: String?
    public let strapTrimHex: String?
    public let latestOneHzRows: [WhoopOneHzInspectorRow]
    public let latestRrRows: [WhoopRrInspectorRow]

    public init(schemaTables: [String] = [], oneHzCount: Int = 0, rrCount: Int = 0,
                rawArchiveCount: Int = 0, liveCoverageCount: Int = 0, batteryCount: Int = 0,
                backlogCount: Int = 0, eventsCount: Int = 0,
                counterHw: String? = nil, recTsHw: String? = nil, strapTrimHex: String? = nil,
                latestOneHzRows: [WhoopOneHzInspectorRow] = [], latestRrRows: [WhoopRrInspectorRow] = []) {
        self.schemaTables = schemaTables
        self.liveCoverageCount = liveCoverageCount
        self.oneHzCount = oneHzCount
        self.rrCount = rrCount
        self.rawArchiveCount = rawArchiveCount
        self.batteryCount = batteryCount
        self.backlogCount = backlogCount
        self.eventsCount = eventsCount
        self.counterHw = counterHw
        self.recTsHw = recTsHw
        self.strapTrimHex = strapTrimHex
        self.latestOneHzRows = latestOneHzRows
        self.latestRrRows = latestRrRows
    }
}

extension WhoopSessionCoordinator {
    public var handshakeTelemetry: WhoopHandshakeTelemetry {
        WhoopHandshakeTelemetry(
            detectedGeneration: detectedGeneration,
            firmwareVersion: firmwareVersion,
            sigprocVersion: sigprocVersion,
            serialNumber: serialNumber,
            batteryPct: batteryPct,
            charging: charging,
            wristOn: wristOn)
    }

    public var burstTelemetry: WhoopBurstTelemetry {
        let hdrErrs = cmdAccumulator.headerCrcErrors + eventsAccumulator.headerCrcErrors + dataAccumulator.headerCrcErrors
        let pldErrs = cmdAccumulator.lostFrames + eventsAccumulator.lostFrames + dataAccumulator.lostFrames
        let resyncs = cmdAccumulator.resyncs + eventsAccumulator.resyncs + dataAccumulator.resyncs
        return WhoopBurstTelemetry(
            liveHrBpm: lastLiveHr?.hrBpm,
            liveRrMs: lastLiveHr?.rrMs ?? [],
            liveHrTimestamp: lastLiveHr?.tsEpoch,
            rollingCrcErrorCount: hdrErrs + pldErrs,
            headerCrcErrors: hdrErrs,
            payloadCrc32Errors: pldErrs,
            resyncCount: resyncs,
            offloadActive: offloadActive,
            currentBurstDataPackets: burstStats.dataPackets,
            currentBurstInlinePackets: burstStats.inlineTrafficPackets,
            lastExpectedPacketCount: lastExpectedPacketCount,
            lastActualPacketCount: lastActualPacketCount,
            lastAckVerdict: lastAckVerdict,
            lastAckWasNack: lastAckWasNack,
            lastAckTokenHex: lastAckTokenHex,
            ackOkCount: ackOkCount,
            nackCount: nackCount)
    }
}

extension WhoopStore {
    public func inspect(limit: Int = 5) throws -> WhoopSqliteInspectionSnapshot {
        let safeLimit = max(1, min(limit, 50))
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
            .map { $0.text("name") }

        let oneHzRows = try db.query("""
            SELECT device_id, ts_ms, rec_ts, ts_subsec, counter, hr, ax, ay, az, skin_temp_c, skin_temp_raw
            FROM decoded_onehz
            ORDER BY ts_ms DESC
            LIMIT ?
            """, [.int(Int64(safeLimit))]).map { row in
            WhoopOneHzInspectorRow(
                deviceID: row.text("device_id"),
                tsMs: row.optionalInt64("ts_ms") ?? 0,
                recTs: row.optionalInt("rec_ts"),
                tsSubsec: row.optionalInt("ts_subsec"),
                counter: row.int("counter"),
                hr: row.optionalInt("hr"),
                ax: row.optionalDouble("ax"),
                ay: row.optionalDouble("ay"),
                az: row.optionalDouble("az"),
                skinTempC: row.optionalDouble("skin_temp_c"),
                skinTempRaw: row.optionalInt("skin_temp_raw"))
        }

        let rrRows = try db.query("""
            SELECT device_id, ts_ms, rec_ts, beat_index, rr_ms, beat_ts_ms
            FROM decoded_rr
            ORDER BY ts_ms DESC, beat_index DESC
            LIMIT ?
            """, [.int(Int64(safeLimit))]).map { row in
            WhoopRrInspectorRow(
                deviceID: row.text("device_id"),
                tsMs: row.optionalInt64("ts_ms") ?? 0,
                recTs: row.int("rec_ts"),
                beatIndex: row.int("beat_index"),
                rrMs: row.int("rr_ms"),
                beatTsMs: row.optionalInt64("beat_ts_ms"))
        }

        return WhoopSqliteInspectionSnapshot(
            schemaTables: tables,
            oneHzCount: try count("decoded_onehz"),
            rrCount: try count("decoded_rr"),
            rawArchiveCount: try count("raw_archive_frames"),
            liveCoverageCount: try count("live_coverage"),
            batteryCount: try count("band_battery"),
            backlogCount: try count("band_backlog"),
            eventsCount: try count("band_events"),
            counterHw: try cursorValue("counter_hw"),
            recTsHw: try cursorValue("rec_ts_hw"),
            strapTrimHex: try cursorValue("strap_trim"),
            latestOneHzRows: oneHzRows,
            latestRrRows: rrRows)
    }
}

extension WhoopDatabaseFileService {
    /// Checkpoints WAL into the main SQLite file using `PRAGMA wal_checkpoint(TRUNCATE)` and exports an exact copy
    /// so the database schema, triggers, and committed rows can be inspected directly on a Mac.
    public func exportCheckpointedSnapshot(from store: WhoopStore, timestampTag: String, to directory: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitizedTag = timestampTag.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: " ", with: "-")
        let target = directory.appendingPathComponent("whoop-diagnostic-\(sanitizedTag).sqlite")
        if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }

        if store.db.path != ":memory:" {
            _ = try store.db.query("PRAGMA wal_checkpoint(TRUNCATE)")
            try fm.copyItem(at: URL(fileURLWithPath: store.db.path), to: target)
            // Clear the WAL header flag on the exported copy so read-only SQLite tools on Mac open it without needing -shm/-wal sidecars.
            let exportedCopy = try Database(path: target.path)
            _ = try exportedCopy.query("PRAGMA journal_mode = DELETE")
        } else {
            try store.db.execute("VACUUM INTO ?", [.text(target.path)])
        }
        try validate(fileAt: target)
        return target
    }
}
