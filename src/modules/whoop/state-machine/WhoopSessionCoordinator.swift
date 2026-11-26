import Foundation

public struct WhoopCoordinatorOutput: Equatable, Sendable {
    public let txFrames: [[UInt8]]
    public let liveHr: WhoopRealtimeHr?
    public let historyCompleted: Bool

    public init(txFrames: [[UInt8]] = [], liveHr: WhoopRealtimeHr? = nil, historyCompleted: Bool = false) {
        self.txFrames = txFrames
        self.liveHr = liveHr
        self.historyCompleted = historyCompleted
    }
}

public struct WhoopSessionCoordinator: Sendable {
    public static let fineClockDriftSeconds = 5

    public var profile: WhoopBandProfile
    public var deviceID: String
    public private(set) var isMaverick = false
    public private(set) var serialNumber: String?
    public private(set) var batteryPct: Double?
    public private(set) var charging: Bool?
    public private(set) var wristOn: Bool?
    public private(set) var offloadActive = false
    public private(set) var corruptionTripped = false
    public private(set) var lastDataRange: WhoopDataRangeInfo?

    private var seq = WhoopSeqAllocator()
    private var accumulator: WhoopFrameAccumulator
    private var burstStats = WhoopBurstStats()
    private var trimGuard = WhoopBurstTrimGuard()
    private var recordGate = WhoopRecordGate()
    private var corruptionDetector = WhoopFrameCorruptionDetector()
    private var pendingBatch: WhoopSyncBatch?
    private var droppedBeforeBurst = 0
    private var droppedBelowFloorBeforeBurst = 0
    private var gateDropArchivesThisBurst = 0
    private var liveImuFrames: [WhoopImuFrame] = []
    private var liveWindowStartSec: Int?

    public init(profile: WhoopBandProfile, deviceID: String) {
        self.profile = profile
        self.deviceID = deviceID
        self.accumulator = WhoopFrameAccumulator(profile: profile)
    }

    public mutating func onLinkReady() -> [[UInt8]] {
        seq.reset()
        accumulator.reset()
        offloadActive = false
        pendingBatch = nil
        if profile.isGen5 {
            let helloSeq = seq.nextLive()
            let clockSeq = seq.nextLive()
            return [
                WhoopCommands.gen5ClientHello(seq: helloSeq),
                WhoopCommands.cmdGetClock(seq: clockSeq, profile: .gen5),
            ]
        } else {
            return WhoopCommands.gen4InitPackets()
        }
    }

    public mutating func buildManualBackfillRequest() -> [UInt8] {
        WhoopCommands.cmdSendHistorical(seq: seq.nextSync(), profile: profile)
    }

    public mutating func buildRealtimeHrToggle(on: Bool) -> [UInt8] {
        WhoopCommands.cmdToggleRealtimeHr(seq: seq.nextLive(), on: on, profile: profile)
    }

    public mutating func buildImuToggle(on: Bool) -> [UInt8] {
        WhoopCommands.cmdToggleImu(seq: seq.nextLive(), on: on, profile: profile)
    }

    public mutating func buildHighFreqSyncPrompt() -> [UInt8]? {
        try? WhoopCommands.enterHighFreqSync(seq: seq.nextLive(), intervalSeconds: 120, durationSeconds: 7200, profile: profile)
    }

    public mutating func discardActiveBurstOnDisconnect() {
        if offloadActive {
            trimGuard.discardOpenChunk()
            offloadActive = false
            pendingBatch = nil
        }
    }

    public mutating func receiveRawDataFromStrap(_ bytes: [UInt8], store: WhoopStore, nowMs: Int64) throws -> WhoopCoordinatorOutput {
        let frames = accumulator.feed(bytes)
        var tx: [[UInt8]] = []
        var latestHr: WhoopRealtimeHr?
        var completed = false
        let wallNow = Int(nowMs / 1000)

        for frame in frames {
            if corruptionDetector.feed(valid: frame.valid) {
                corruptionTripped = true
            }
            guard frame.decodable, let pktByte = frame.inner.first else {
                if offloadActive {
                    trimGuard.discardOpenChunk()
                }
                continue
            }

            let route = WhoopFrameRoutePolicy.route(packetType: pktByte, isDataRole: true, offloadActive: offloadActive)
            if route == .immediateAndCount {
                burstStats.recordInlineTrafficMember()
            }

            switch pktByte {
            case WhoopPacketType.commandResponse:
                if let resp = WhoopControlDecoder.parseCommandResponse(frame.inner, profile: profile) {
                    tx += try handleCommandResponse(resp, store: store, nowMs: nowMs, wallNow: wallNow)
                }

            case WhoopPacketType.event:
                if let ev = WhoopControlDecoder.parseEvent(frame.inner, profile: profile) {
                    if let pct = ev.batteryPct { batteryPct = pct }
                    if let chg = ev.charging { charging = chg }
                    if let w = ev.wristOn { wristOn = w }
                    let rawHex = WhoopBytes.hex(frame.inner)
                    var immediateBatch = WhoopSyncBatch(
                        deviceID: deviceID,
                        events: [WhoopEventRow(deviceID: deviceID, rawInnerHex: rawHex, info: ev, capturedAtMs: nowMs)],
                        capturedAtMs: nowMs)
                    if ev.batteryPct != nil || ev.charging != nil || ev.chargeUnits != nil || ev.wristOn != nil {
                        immediateBatch.batteryRows.append(WhoopBatteryRow(
                            deviceID: deviceID, ts: ev.tsEpoch > 0 ? ev.tsEpoch : wallNow,
                            batteryPct: ev.batteryPct, charging: ev.charging, wristOn: ev.wristOn,
                            millivolts: ev.batteryMv, chargeUnits: ev.chargeUnits, source: "band_event"))
                    }
                    try store.commitSyncBatch(immediateBatch)
                }

            case WhoopPacketType.realtimeData:
                if let hr = WhoopLiveDecoder.parseRealtimeHr(frame.inner) {
                    latestHr = hr
                    wristOn = hr.wearing
                }

            case WhoopPacketType.realtimeImuStream, WhoopPacketType.realtimeRawData:
                if let imu = WhoopLiveDecoder.frameAccel(frame.inner) {
                    if liveWindowStartSec == nil { liveWindowStartSec = imu.ts }
                    liveImuFrames.append(imu)
                    if let start = liveWindowStartSec, imu.ts - start >= 60 {
                        let steps = WhoopLivePedometer.countSteps(frames: liveImuFrames)
                        let dayStr = Self.utcDayString(epochSec: start)
                        let spanBatch = WhoopSyncBatch(
                            deviceID: deviceID,
                            liveCoverageSpans: [WhoopLiveCoverageRow(startTs: start, endTs: imu.ts, steps: steps, day: dayStr, source: "band", deviceID: deviceID)],
                            capturedAtMs: nowMs)
                        try store.commitSyncBatch(spanBatch)
                        liveImuFrames.removeAll()
                        liveWindowStartSec = imu.ts
                    }
                }

            case WhoopPacketType.metadata:
                if let meta = WhoopControlDecoder.parseMetadata(frame.inner) {
                    let metaOut = try handleMetadata(meta, store: store, nowMs: nowMs)
                    tx += metaOut.tx
                    if metaOut.completed { completed = true }
                }

            case WhoopPacketType.historicalData:
                if !offloadActive {
                    beginBurst(nowMs: nowMs)
                }
                burstStats.recordDataPacket()
                ingestHistoricalFrame(frame.inner, nowMs: nowMs, wallNow: wallNow)

            default:
                break
            }
        }

        return WhoopCoordinatorOutput(txFrames: tx, liveHr: latestHr, historyCompleted: completed)
    }

    private mutating func beginBurst(nowMs: Int64) {
        offloadActive = true
        burstStats.beginBurst()
        trimGuard.beginBurst()
        droppedBeforeBurst = recordGate.dropped
        droppedBelowFloorBeforeBurst = recordGate.droppedBelowFloor
        gateDropArchivesThisBurst = 0
        pendingBatch = WhoopSyncBatch(deviceID: deviceID, capturedAtMs: nowMs)
    }

    private mutating func ingestHistoricalFrame(_ inner: [UInt8], nowMs: Int64, wallNow: Int) {
        let oldest = lastDataRange?.rangeOldest
        let newest = lastDataRange?.rangeNewest

        if profile.isGen5 {
            switch WhoopGen5Decoder.classifyHistorical(inner) {
            case .v18(let sample):
                if recordGate.admit(sample.unix, wallNow: wallNow, sessionOldestUnix: oldest, sessionNewestUnix: newest) {
                    pendingBatch?.gen5Samples.append(sample)
                } else {
                    gateDropArchivesThisBurst += 1
                    pendingBatch?.archives.append(WhoopRawArchiveRow(
                        deviceID: deviceID, counter: sample.recordIndex, packetType: Int(WhoopPacketType.historicalData),
                        recTs: sample.unix, capturedAtMs: nowMs, reason: "gate_dropped", frame: Data(inner)))
                }
            case .ecgRaw(let ecg):
                if recordGate.admit(ecg.strapSeconds, wallNow: wallNow, sessionOldestUnix: oldest, sessionNewestUnix: newest) {
                    pendingBatch?.ecgRawPackets.append(ecg)
                } else {
                    gateDropArchivesThisBurst += 1
                    pendingBatch?.archives.append(WhoopRawArchiveRow(
                        deviceID: deviceID, counter: ecg.sequence, packetType: Int(WhoopPacketType.historicalData),
                        recTs: ecg.strapSeconds, capturedAtMs: nowMs, reason: "gate_dropped", frame: Data(inner)))
                }
            case .rawArchive(_, let header, let reason):
                pendingBatch?.archives.append(WhoopRawArchiveRow(
                    deviceID: deviceID, counter: header.recordIndex, packetType: Int(WhoopPacketType.historicalData),
                    recTs: header.unix, capturedAtMs: nowMs, reason: reason, frame: Data(inner)))
            case nil:
                pendingBatch?.archives.append(WhoopRawArchiveRow(
                    deviceID: deviceID, counter: nil, packetType: Int(WhoopPacketType.historicalData),
                    recTs: nil, capturedAtMs: nowMs, reason: "undecodable_gen5_short", frame: Data(inner)))
            }
        } else {
            if inner.count >= WhoopR10Lite.minLength, let r10 = WhoopGen4Decoder.decodeR10Lite(inner) {
                if recordGate.admit(r10.tsEpoch, wallNow: wallNow, sessionOldestUnix: oldest, sessionNewestUnix: newest) {
                    pendingBatch?.gen4R10Records.append(r10)
                } else {
                    gateDropArchivesThisBurst += 1
                    pendingBatch?.archives.append(WhoopRawArchiveRow(
                        deviceID: deviceID, counter: r10.counter, packetType: Int(WhoopPacketType.historicalData),
                        recTs: r10.tsEpoch, capturedAtMs: nowMs, reason: "gate_dropped", frame: Data(inner)))
                }
            } else if let r24 = WhoopGen4Decoder.decodeFirmwareAwareR24(inner), r24.histVersion != 25 {
                if recordGate.admit(r24.tsEpoch, wallNow: wallNow, sessionOldestUnix: oldest, sessionNewestUnix: newest) {
                    pendingBatch?.gen4Records.append(r24)
                } else {
                    gateDropArchivesThisBurst += 1
                    pendingBatch?.archives.append(WhoopRawArchiveRow(
                        deviceID: deviceID, counter: r24.counter, packetType: Int(WhoopPacketType.historicalData),
                        recTs: r24.tsEpoch, capturedAtMs: nowMs, reason: "gate_dropped", frame: Data(inner)))
                }
            } else {
                let ver = inner.count > 1 ? Int(inner[1]) : -1
                pendingBatch?.archives.append(WhoopRawArchiveRow(
                    deviceID: deviceID, counter: nil, packetType: Int(WhoopPacketType.historicalData),
                    recTs: nil, capturedAtMs: nowMs, reason: "undecodable_rec_v\(ver)", frame: Data(inner)))
            }
        }
    }

    private mutating func handleCommandResponse(_ resp: WhoopCommandResponse, store: WhoopStore, nowMs: Int64, wallNow: Int) throws -> [[UInt8]] {
        var tx: [[UInt8]] = []
        if let pct = resp.batteryPct { batteryPct = pct }

        if let g5 = resp.gen5Hello {
            isMaverick = g5.isMaverick
            if !g5.serial.isEmpty { serialNumber = g5.serial }
            if let pct = g5.batteryPct { batteryPct = pct }
            charging = g5.charging
            wristOn = g5.wristOn

            let battBatch = WhoopSyncBatch(
                deviceID: deviceID,
                batteryRows: [WhoopBatteryRow(
                    deviceID: deviceID, ts: g5.tsSeconds > 0 ? g5.tsSeconds : wallNow,
                    batteryPct: g5.batteryPct, charging: g5.charging, wristOn: g5.wristOn,
                    millivolts: nil, chargeUnits: nil, source: "get_hello")],
                capturedAtMs: nowMs)
            try store.commitSyncBatch(battBatch)

            let startSeq = seq.nextLive()
            let r22Frames = WhoopCommands.buildR22EnableSequence(startSeq: startSeq, omitContestedFlags: false)
            for _ in 1..<max(1, r22Frames.count) { _ = seq.nextLive() }
            tx += r22Frames

            if g5.tsSeconds > 0,
               WhoopClockPolicy.acceptsClockRead(deviceClock: g5.tsSeconds, wallNow: wallNow),
               (WhoopClockPolicy.shouldSetClock(deviceClock: g5.tsSeconds, wallNow: wallNow)
                || abs(wallNow - g5.tsSeconds) > Self.fineClockDriftSeconds) {
                tx.append(WhoopCommands.cmdSetClock(seq: seq.nextLive(), epochMs: nowMs, profile: .gen5))
            }

            tx.append(WhoopCommands.cmdGetDataRange(seq: seq.nextLive(), profile: .gen5))
            tx.append(WhoopCommands.cmdToggleRealtimeHr(seq: seq.nextLive(), on: true, profile: .gen5))
        } else if let g4 = resp.gen4Hello {
            if let s = g4.serial { serialNumber = s }
            if let pct = g4.batteryPct { batteryPct = pct }
        }

        if let clock = resp.clockEpoch,
           WhoopClockPolicy.acceptsClockRead(deviceClock: clock, wallNow: wallNow),
           (WhoopClockPolicy.shouldSetClock(deviceClock: clock, wallNow: wallNow)
            || abs(wallNow - clock) > Self.fineClockDriftSeconds) {
            tx.append(WhoopCommands.cmdSetClock(seq: seq.nextLive(), epochMs: nowMs, profile: profile))
        }

        if let dr = resp.dataRange {
            lastDataRange = dr
            let blBatch = WhoopSyncBatch(
                deviceID: deviceID,
                backlogRows: [WhoopBacklogRow(
                    deviceID: deviceID, ts: wallNow, written: dr.written, used: dr.used,
                    capacity: dr.capacity, trimPage: dr.trimPage, wrapCount: dr.wrapCount,
                    freeRecords: dr.freeRecords, deviceFamily: profile.isGen5 ? "gen5" : "gen4")],
                capturedAtMs: nowMs)
            try store.commitSyncBatch(blBatch)
            if dr.used > 0 && !offloadActive {
                tx.append(WhoopCommands.cmdSendHistorical(seq: seq.nextSync(), profile: profile))
            }
        }

        return tx
    }

    private mutating func handleMetadata(_ meta: WhoopMetaMarker, store: WhoopStore, nowMs: Int64) throws -> (tx: [[UInt8]], completed: Bool) {
        switch meta.sub {
        case .historyStart:
            beginBurst(nowMs: nowMs)
            return ([], false)

        case .historyEnd:
            let droppedThisBurst = recordGate.dropped - droppedBeforeBurst
            let droppedBelowFloorThisBurst = recordGate.droppedBelowFloor - droppedBelowFloorBeforeBurst
            let countOk: Bool
            if let expected = meta.expectedPacketCount, expected > 0 {
                if profile.isGen5 {
                    countOk = burstStats.passesGen5CountGate(expectedPacketCount: expected, droppedThisBurst: droppedThisBurst)
                } else {
                    countOk = burstStats.totalTrafficPacketCount + droppedThisBurst >= expected
                }
            } else {
                countOk = true
            }

            guard countOk, let token = meta.token, token.count == 8 else {
                burstStats.noteValidationFailure()
                offloadActive = false
                pendingBatch = nil
                let nack = WhoopCommands.buildHistoryResultFail(seq: seq.nextSync(), profile: profile)
                return ([nack], false)
            }

            burstStats.noteValidationSuccess()
            var batch = pendingBatch ?? WhoopSyncBatch(deviceID: deviceID, capturedAtMs: nowMs)
            let hadDurable = batch.hadDurableRows
            let verdictPreCommit = WhoopTrimAckPolicy.evaluate(
                sessionCurrent: true,
                burstDiscarded: trimGuard.discarded,
                commitDurable: true,
                hadDurableRows: hadDurable,
                droppedThisBurst: droppedThisBurst,
                droppedBelowFloorThisBurst: droppedBelowFloorThisBurst,
                gateDropArchives: gateDropArchivesThisBurst,
                shortfallRetry: false)

            guard verdictPreCommit == .send else {
                offloadActive = false
                pendingBatch = nil
                let nack = WhoopCommands.buildHistoryResultFail(seq: seq.nextSync(), profile: profile)
                return ([nack], false)
            }

            batch.trimTokenHex = WhoopBytes.hex(token)
            batch.capturedAtMs = nowMs
            do {
                try store.commitSyncBatch(batch)
            } catch {
                offloadActive = false
                pendingBatch = nil
                let nack = WhoopCommands.buildHistoryResultFail(seq: seq.nextSync(), profile: profile)
                return ([nack], false)
            }

            offloadActive = false
            pendingBatch = nil
            let ack = try WhoopCommands.buildHistoryResultOk(seq: seq.nextSync(), token: token, profile: profile)
            return ([ack], false)

        case .historyComplete:
            offloadActive = false
            pendingBatch = nil
            return ([], true)

        case .unknown:
            return ([], false)
        }
    }

    private static func utcDayString(epochSec: Int) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(epochSec))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}
