import Foundation

public struct WhoopGen4HelloInfo: Equatable, Sendable {
    public let batteryPct: Double?
    public let serial: String?
    public let commit: String?
}

public struct WhoopGen5HelloInfo: Equatable, Sendable {
    public static let semanticBodyLen = 104

    public let helloRevision: UInt8
    public let batteryPct: Double?
    public let charging: Bool
    public let tsSeconds: Int
    public let tsSubseconds: Int
    public let serial: String
    public let commitHex: String
    public let cpuHex: String
    public let hardwareFamily: UInt32
    public let pcbaRevision: UInt32
    public let opticalDiscriminator: UInt32
    public let fwMajor: UInt8
    public let fwMinor: UInt8
    public let fwBuild: UInt8
    public let fwUnreleased: UInt32
    public let sigprocMajor: UInt8
    public let sigprocMinor: UInt8
    public let sigprocPatch: UInt8
    public let hrBroadcast: Bool
    public let wristOn: Bool
    public let errorByte: Int

    public var isWhoop5: Bool { opticalDiscriminator >= 48 && opticalDiscriminator < 86 }
    public var isMaverick: Bool { helloRevision == 1 && opticalDiscriminator < 38 }
    public var firmwareVersion: String { "\(fwMajor).\(fwMinor).\(fwBuild).\(fwUnreleased)" }
    public var tsSecondsOrNull: Int? {
        (tsSeconds >= 1_700_000_000 && tsSeconds <= 4_102_444_800) ? tsSeconds : nil
    }
}

public struct WhoopDataRangeInfo: Equatable, Sendable {
    public let rangeOldest: Int?
    public let rangeNewest: Int?
    public let written: Int
    public let used: Int
    public let capacity: Int
    public let trimPage: Int
    public let wrapCount: Int
    public let freeRecords: Int
}

public struct WhoopCommandResponse: Equatable, Sendable {
    public let opcode: UInt8
    public let reqSeq: UInt8?
    public let status: Int
    public let batteryPct: Double?
    public let clockEpoch: Int?
    public let strapName: String?
    public let alarmEpoch: Int?
    public let alarmActive: Bool?
    public let gen4Hello: WhoopGen4HelloInfo?
    public let gen5Hello: WhoopGen5HelloInfo?
    public let dataRange: WhoopDataRangeInfo?
}

public struct WhoopEventInfo: Equatable, Sendable {
    public let eventID: Int
    public let name: String
    public let tsEpoch: Int
    public let tsSubsec: Int
    public let batteryPct: Double?
    public let batteryMv: Int?
    public let charging: Bool?
    public let wristOn: Bool?
    public let chargeUnits: Int?
    public let highFreqSync: String?
    public let payloadJSON: String
}

public enum WhoopMetaSubType: UInt8, Equatable, Sendable {
    case historyStart = 1
    case historyEnd = 2
    case historyComplete = 3
    case unknown = 0
}

public struct WhoopMetaMarker: Equatable, Sendable {
    public let sub: WhoopMetaSubType
    public let rawSub: UInt8
    public let name: String
    public let expectedPacketCount: Int?
    public let token: [UInt8]?
    public let batchID: Int?
    public let strapClockEpoch: Int?
    public let strapClockSubsec: Int?
}

public struct WhoopRealtimeHr: Equatable, Sendable {
    public let hrBpm: Int
    public let rrMs: [Int]
    public let wearing: Bool
    public let tsEpoch: Int
    public let tsSubsec: Int
    public let locationRaw: UInt8?
}

public struct WhoopImuFrame: Equatable, Sendable {
    public let ts: Int
    public let idx: Int
    public let mags: [Double]
    public let xs: [Double]
    public let ys: [Double]
    public let zs: [Double]
}

public enum WhoopControlDecoder {
    private static let minPlausibleUnix = 1_700_000_000
    private static let maxPlausibleUnix = 4_102_444_800

    private static func plausibleUnix(_ v: Int) -> Bool {
        v >= minPlausibleUnix && v <= maxPlausibleUnix
    }

    private static func cstr(_ b: [UInt8], start: Int, end: Int) -> String {
        guard start < b.count else { return "" }
        let cap = min(end, b.count)
        var chars: [UInt8] = []
        for i in start..<cap {
            let c = b[i]
            if c == 0 { break }
            if c < 0x20 || c >= 0x7F { return "" }
            chars.append(c)
        }
        return String(bytes: chars, encoding: .ascii) ?? ""
    }

    public static func eventName(_ eid: Int, isGen5: Bool) -> String {
        switch eid {
        case 3: return "BATTERY_LEVEL"
        case 7: return "CHARGING_ON"
        case 8: return "CHARGING_OFF"
        case 9: return "WRIST_ON"
        case 10: return "WRIST_OFF"
        case 14: return "DOUBLE_TAP"
        case 21: return "BATTERY_PACK_CONNECTED"
        case 22: return "BATTERY_PACK_REMOVED"
        case 29: return isGen5 ? "STRAP_CONDITION_REPORT" : "EVENT_29"
        case 31: return "BLE_BONDED"
        case 33: return "BLE_REALTIME_HR_ON"
        case 34: return "BLE_REALTIME_HR_OFF"
        case 56: return "STRAP_DRIVEN_ALARM_SET"
        case 57: return "STRAP_DRIVEN_ALARM_EXECUTED"
        case 59: return "STRAP_DRIVEN_ALARM_DISABLED"
        case 60: return "HAPTICS_FIRED"
        case 63: return "EXTENDED_BATTERY_INFORMATION"
        case 96: return "HIGH_FREQ_SYNC_PROMPT"
        case 97: return "HIGH_FREQ_SYNC_ENABLED"
        case 98: return "HIGH_FREQ_SYNC_DISABLED"
        case 100: return isGen5 ? "HAPTICS_TERMINATED" : "EVENT_100"
        case 109: return isGen5 ? "BATTERY_PACK_INFO" : "EVENT_109"
        case 111: return "TEMPERATURE_LEVEL"
        case 123: return isGen5 ? "GENERIC_FIRMWARE_EVENT" : "EVENT_123"
        default: return "EVENT_\(eid)"
        }
    }

    public static func parseEvent(_ inner: [UInt8], profile: WhoopBandProfile = .gen4) -> WhoopEventInfo? {
        guard inner.count >= 4, inner[0] == WhoopPacketType.event else { return nil }
        let eid = Int(WhoopBytes.u16(inner, 2))
        let name = eventName(eid, isGen5: profile.isGen5)
        let ts = inner.count >= 8 ? Int(WhoopBytes.u32(inner, 4)) : 0
        let subsec = inner.count >= 10 ? Int(WhoopBytes.u16(inner, 8)) : 0
        let body: [UInt8] = {
            guard inner.count >= 12 else { return [] }
            let declared = Int(WhoopBytes.u16(inner, 10))
            let end = min(12 + declared, inner.count)
            return Array(inner[12..<end])
        }()

        var batteryPct: Double?
        var batteryMv: Int?
        var charging: Bool?
        var wristOn: Bool?
        var chargeUnits: Int?
        var highFreqSync: String?
        var jsonFields: [String: Any] = [:]

        switch eid {
        case 7, 8:
            let c = (eid == 7)
            charging = c
            jsonFields["charging"] = c
        case 9, 10:
            let w = (eid == 9)
            wristOn = w
            jsonFields["on_wrist"] = w
        case 14:
            jsonFields["double_tap"] = true
        case 3: // Fix #2: BATTERY_LEVEL charging is at body[9] (inner[21]), NOT body[10]
            if body.count >= 12 {
                let soc = WhoopBytes.jsRound(Double(WhoopBytes.u32(body, 1)) / 10.0, decimals: 1)
                if soc.isFinite && soc >= 0.0 && soc <= 100.0 {
                    batteryPct = soc
                    jsonFields["battery_pct"] = soc
                    let mv = Int(WhoopBytes.u32(body, 5))
                    if (2500...4500).contains(mv) {
                        batteryMv = mv
                        jsonFields["battery_mv"] = mv
                    }
                    let chg = body[9] != 0
                    charging = chg
                    jsonFields["charging"] = chg
                }
            }
        case 63: // EXTENDED_BATTERY_INFORMATION
            if body.first == 1, body.count >= 13 {
                let cu = Int(WhoopBytes.u16(body, 11))
                chargeUnits = cu
                jsonFields["charge_units"] = cu
            } else if body.first == 3, body.count >= 11 {
                let cu = Int(WhoopBytes.u16(body, 9))
                chargeUnits = cu
                jsonFields["charge_units"] = cu
            }
        case 29 where profile.isGen5:
            if body.count >= 4 { jsonFields["condition_pages_behind"] = Int(WhoopBytes.u32(body, 0)) }
            if body.count >= 8 {
                let soc = WhoopBytes.jsRound(Double(WhoopBytes.u16(body, 6)) / 10.0, decimals: 1)
                if soc >= 0.0 && soc <= 100.0 { jsonFields["condition_soc_pct"] = soc }
            }
            if body.count >= 10 { jsonFields["condition_charging"] = (body[9] != 0) }
        case 96:
            highFreqSync = "prompt"
            jsonFields["high_freq_sync"] = "prompt"
        case 97:
            highFreqSync = "enabled"
            jsonFields["high_freq_sync"] = "enabled"
        case 98:
            highFreqSync = "disabled"
            jsonFields["high_freq_sync"] = "disabled"
        case 100 where profile.isGen5:
            if body.count >= 2 {
                jsonFields["haptics_revision"] = Int(body[0])
                jsonFields["haptics_termination_code"] = Int(body[1])
            }
        default:
            break
        }

        let jsonStr: String = {
            guard !jsonFields.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: jsonFields, options: [.sortedKeys]),
                  let s = String(data: data, encoding: .utf8) else { return "{}" }
            return s
        }()

        return WhoopEventInfo(
            eventID: eid, name: name, tsEpoch: ts, tsSubsec: subsec,
            batteryPct: batteryPct, batteryMv: batteryMv, charging: charging,
            wristOn: wristOn, chargeUnits: chargeUnits, highFreqSync: highFreqSync,
            payloadJSON: jsonStr)
    }

    public static func parseMetadata(_ inner: [UInt8]) -> WhoopMetaMarker? {
        guard inner.count >= 3, inner[0] == WhoopPacketType.metadata else { return nil }
        let rawSub = inner[2]
        let sub: WhoopMetaSubType
        let name: String
        switch rawSub {
        case 1: sub = .historyStart; name = "HISTORY_START"
        case 2: sub = .historyEnd; name = "HISTORY_END"
        case 3: sub = .historyComplete; name = "HISTORY_COMPLETE"
        default: sub = .unknown; name = "META_\(rawSub)"
        }

        var expectedCount: Int?
        var token: [UInt8]?
        var batchID: Int?
        var strapClockEpoch: Int?
        var strapClockSubsec: Int?

        if sub == .historyEnd && inner.count >= 13 {
            expectedCount = Int(WhoopBytes.u32(inner, 9))
            let rawClock = Int(WhoopBytes.u32(inner, 3))
            if plausibleUnix(rawClock) {
                strapClockEpoch = rawClock
                strapClockSubsec = Int(WhoopBytes.u16(inner, 7))
            }
        }
        if sub == .historyEnd && inner.count >= 21 {
            token = Array(inner[13..<21])
            batchID = Int(WhoopBytes.u32(inner, 17))
        }

        return WhoopMetaMarker(
            sub: sub, rawSub: rawSub, name: name,
            expectedPacketCount: expectedCount, token: token, batchID: batchID,
            strapClockEpoch: strapClockEpoch, strapClockSubsec: strapClockSubsec)
    }

    public static func parseCommandResponse(_ inner: [UInt8], profile: WhoopBandProfile = .gen4) -> WhoopCommandResponse? {
        guard inner.count >= 3, inner[0] == WhoopPacketType.commandResponse else { return nil }
        let op = inner[2]
        let payload = Array(inner.dropFirst(3))
        let reqSeq = inner.count >= 4 ? inner[3] : nil
        let status = inner.count >= 5 ? Int(inner[4]) : -1

        var batteryPct: Double?
        var clockEpoch: Int?
        var strapName: String?
        var alarmEpoch: Int?
        var alarmActive: Bool?
        var gen4Hello: WhoopGen4HelloInfo?
        var gen5Hello: WhoopGen5HelloInfo?
        var dataRange: WhoopDataRangeInfo?

        if op == WhoopCmd.getBatteryLevel, inner.count >= (profile.isGen5 ? 6 : 7) {
            if profile.isGen5 {
                if status == 1 {
                    let pct = Double(inner[5])
                    if pct >= 0.0 && pct <= 100.0 { batteryPct = pct }
                }
            } else {
                let pct = WhoopBytes.jsRound(Double(WhoopBytes.u16(inner, 5)) / 10.0, decimals: 1)
                if pct >= 0.0 && pct <= 100.0 { batteryPct = pct }
            }
        } else if op == WhoopCmd.getHelloHarvard {
            gen4Hello = parseGen4Hello(payload)
        } else if op == WhoopCmd.getHello, profile.isGen5, status == 1, payload.count >= 2 + WhoopGen5HelloInfo.semanticBodyLen {
            let body = Array(payload.dropFirst(2))
            gen5Hello = parseGen5Hello(body)
        } else if op == WhoopCmd.getClock || op == WhoopCmd.getClockGen5 {
            let at = (op == WhoopCmd.getClockGen5) ? 3 : 2
            let revOk = (op != WhoopCmd.getClockGen5) || (payload.count > 2 && payload[2] == 1)
            let statusOk = !profile.isGen5 || status == 1
            if statusOk, revOk, payload.count >= at + 4 {
                let v = Int(WhoopBytes.u32(payload, at))
                if plausibleUnix(v) { clockEpoch = v }
            }
        } else if op == WhoopCmd.getDataRange {
            let revOk = payload.count > 2 && payload[2] == 1
            let statusOk = !profile.isGen5 || status == 1
            if statusOk, revOk, payload.count >= 35 {
                let writePage = Int(WhoopBytes.u32(payload, 11))
                let capacity = Int(WhoopBytes.u32(payload, 23))
                if capacity > 0 && writePage <= capacity {
                    var oldestOpt: Int?
                    var newestOpt: Int?
                    if payload.count >= 63 {
                        let oldest = Int(WhoopBytes.u32(payload, 35))
                        let newest = Int(WhoopBytes.u32(payload, 59))
                        if plausibleUnix(oldest), plausibleUnix(newest), oldest <= newest {
                            oldestOpt = oldest
                            newestOpt = newest
                        }
                    }
                    dataRange = WhoopDataRangeInfo(
                        rangeOldest: oldestOpt, rangeNewest: newestOpt,
                        written: writePage, used: Int(WhoopBytes.u32(payload, 27)),
                        capacity: capacity, trimPage: Int(WhoopBytes.u32(payload, 15)),
                        wrapCount: Int(WhoopBytes.u32(payload, 19)), freeRecords: Int(WhoopBytes.u32(payload, 31)))
                }
            }
        } else if op == WhoopCmd.getAdvertisingNameHarvard || op == WhoopCmd.getCustomAdvertisingName {
            if status == 1, payload.count > 5 {
                let len = Int(payload[4])
                if len > 0 && len <= 20 {
                    let s = cstr(payload, start: 5, end: 5 + len).trimmingCharacters(in: .whitespaces)
                    if !s.isEmpty { strapName = s }
                }
            }
        } else if op == WhoopCmd.getAlarmTime {
            let statusOk = !profile.isGen5 || status == 1
            let form = payload.count >= 3 ? Int(payload[2]) : -1
            if statusOk, form == 1, payload.count >= 7 {
                alarmEpoch = Int(WhoopBytes.u32(payload, 3))
            } else if statusOk, form == 4, payload.count >= 8 {
                alarmEpoch = Int(WhoopBytes.u32(payload, 4))
                alarmActive = (payload[3] == 1)
            }
        }

        return WhoopCommandResponse(
            opcode: op, reqSeq: reqSeq, status: status, batteryPct: batteryPct,
            clockEpoch: clockEpoch, strapName: strapName, alarmEpoch: alarmEpoch,
            alarmActive: alarmActive, gen4Hello: gen4Hello, gen5Hello: gen5Hello,
            dataRange: dataRange)
    }

    private static func parseGen4Hello(_ payload: [UInt8]) -> WhoopGen4HelloInfo {
        guard payload.count >= 10 else { return WhoopGen4HelloInfo(batteryPct: nil, serial: nil, commit: nil) }
        var pct: Double?
        if payload[2] == 0x04 {
            let v = WhoopBytes.u32(payload, 3)
            if v <= 1000 { pct = WhoopBytes.jsRound(Double(v) / 10.0, decimals: 1) }
        } else {
            for off in 3..<min(10, payload.count - 1) {
                let v = WhoopBytes.u16(payload, off)
                if v >= 10 && v <= 1000 {
                    pct = WhoopBytes.jsRound(Double(v) / 10.0, decimals: 1)
                    break
                }
            }
        }
        let s = cstr(payload, start: 16, end: min(payload.count, 32))
        let validSerial = (6...13).contains(s.count) && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return WhoopGen4HelloInfo(batteryPct: pct, serial: validSerial ? s : nil, commit: nil)
    }

    private static func parseGen5Hello(_ body: [UInt8]) -> WhoopGen5HelloInfo? {
        guard body.count >= WhoopGen5HelloInfo.semanticBodyLen else { return nil }
        let batRaw = WhoopBytes.u32(body, 1)
        let pct: Double? = batRaw <= 1000 ? WhoopBytes.jsRound(Double(batRaw) / 10.0, decimals: 1) : nil
        return WhoopGen5HelloInfo(
            helloRevision: body[0],
            batteryPct: pct,
            charging: (body[5] & 0x01) != 0,
            tsSeconds: Int(WhoopBytes.u32(body, 6)),
            tsSubseconds: Int(WhoopBytes.u32(body, 10)),
            serial: cstr(body, start: 14, end: 25),
            commitHex: WhoopBytes.hex(Array(body[25..<49])),
            cpuHex: WhoopBytes.hex(Array(body[49..<79])),
            hardwareFamily: WhoopBytes.u32(body, 79),
            pcbaRevision: WhoopBytes.u32(body, 83),
            opticalDiscriminator: WhoopBytes.u32(body, 87),
            fwMajor: body[91],
            fwMinor: body[92],
            fwBuild: body[93],
            fwUnreleased: WhoopBytes.u32(body, 94),
            sigprocMajor: body[98],
            sigprocMinor: body[99],
            sigprocPatch: body[100],
            hrBroadcast: body[101] != 0,
            wristOn: body[102] == 1,
            errorByte: Int(Int8(bitPattern: body[103])))
    }
}

public enum WhoopLiveDecoder {
    /// Parses compact `0x28` realtime HR/RR packet, strictly capping `rr_count <= 4` so `wearing` at `inner[18]` is never misread.
    public static func parseRealtimeHr(_ inner: [UInt8]) -> WhoopRealtimeHr? {
        guard inner.count >= 9, inner[0] == WhoopPacketType.realtimeData else { return nil }
        let ts = Int(WhoopBytes.u32(inner, 2))
        let subsec = Int(WhoopBytes.u16(inner, 6))
        let hr = Int(inner[8])
        guard (1...250).contains(hr) else { return nil }

        let declaredCount = inner.count > 9 ? Int(inner[9]) : 0
        var rrs: [Int] = []
        if declaredCount > 0 && declaredCount <= 4 {
            for i in 0..<declaredCount where 10 + 2 * i + 2 <= inner.count {
                let v = Int(WhoopBytes.u16(inner, 10 + 2 * i))
                if v >= WhoopR24Record.minRrMs && v <= WhoopR24Record.maxRrMs {
                    rrs.append(v)
                }
            }
        }
        let wearing = inner.count > 18 ? (inner[18] == 1) : true
        let loc = inner.count > 19 ? inner[19] : nil
        return WhoopRealtimeHr(hrBpm: hr, rrMs: rrs, wearing: wearing, tsEpoch: ts, tsSubsec: subsec, locationRaw: loc)
    }

    /// Decodes live `0x33` (Gen4 10-sample IMU) or `0x2B` (Gen4 R10 100-sample / Gen5 R21 100-sample IMU).
    public static func frameAccel(_ inner: [UInt8]) -> WhoopImuFrame? {
        guard inner.count >= 32 else { return nil }
        let pkt = inner[0]

        if pkt == WhoopPacketType.realtimeRawData, let gen5Buf = WhoopGen5Decoder.parseGen5ImuBuffer(inner) {
            var mags: [Double] = []
            var xs: [Double] = []
            var ys: [Double] = []
            var zs: [Double] = []
            for i in 0..<gen5Buf.accelXg.count {
                let xg = gen5Buf.accelXg[i]
                let yg = gen5Buf.accelYg[i]
                let zg = gen5Buf.accelZg[i]
                xs.append(xg / WhoopGen5ImuBuffer.accelScaleG)
                ys.append(yg / WhoopGen5ImuBuffer.accelScaleG)
                zs.append(zg / WhoopGen5ImuBuffer.accelScaleG)
                mags.append((xg * xg + yg * yg + zg * zg).squareRoot())
            }
            return WhoopImuFrame(ts: gen5Buf.header.unix, idx: 0, mags: mags, xs: xs, ys: ys, zs: zs)
        }

        if pkt == WhoopPacketType.realtimeImuStream && inner.count >= 84 {
            let ts = Int(WhoopBytes.u32(inner, 4))
            guard ts > 0 else { return nil }
            let idx = Int(WhoopBytes.u16(inner, 14))
            var mags: [Double] = [], xs: [Double] = [], ys: [Double] = [], zs: [Double] = []
            for i in 0..<10 {
                let x = Double(WhoopBytes.i16(inner, 24 + 2 * i))
                let y = Double(WhoopBytes.i16(inner, 44 + 2 * i))
                let z = Double(WhoopBytes.i16(inner, 64 + 2 * i))
                xs.append(x); ys.append(y); zs.append(z)
                mags.append((x * x + y * y + z * z).squareRoot() / 4096.0)
            }
            return WhoopImuFrame(ts: ts, idx: idx, mags: mags, xs: xs, ys: ys, zs: zs)
        }

        if inner[1] == 10 && inner.count >= WhoopR10Lite.minLength &&
           (pkt == WhoopPacketType.realtimeRawData || pkt == WhoopPacketType.historicalData) {
            let ts = Int(WhoopBytes.u32(inner, 7))
            guard ts > 0 else { return nil }
            var mags: [Double] = [], xs: [Double] = [], ys: [Double] = [], zs: [Double] = []
            for i in 0..<100 {
                let x = Double(WhoopBytes.i16(inner, 85 + 2 * i))
                let y = Double(WhoopBytes.i16(inner, 285 + 2 * i))
                let z = Double(WhoopBytes.i16(inner, 485 + 2 * i))
                xs.append(x); ys.append(y); zs.append(z)
                mags.append((x * x + y * y + z * z).squareRoot() / 4096.0)
            }
            return WhoopImuFrame(ts: ts, idx: 0, mags: mags, xs: xs, ys: ys, zs: zs)
        }

        return nil
    }
}
