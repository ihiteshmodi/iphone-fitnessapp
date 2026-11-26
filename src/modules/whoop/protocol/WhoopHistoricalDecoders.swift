import Foundation

public struct WhoopR24Record: Equatable, Sendable {
    public static let minRrMs = 200
    public static let maxRrMs = 2500
    public static let maxR10RrSlots = 8
    public static let maxV24RrSlots = 4

    public let histVersion: Int
    public let tsEpoch: Int
    public let tsSubsec: Int
    public let counter: Int
    public let hr: Int
    public let rrCount: Int
    public let rrIntervalsMs: [Int]
    public let ppgGreen: Int
    public let accelG: [Double]
    public let spo2RedRaw: Int
    public let spo2IrRaw: Int
    public let skinTempRaw: Int
    public let ambientRaw: Int
}

public struct WhoopR10Lite: Equatable, Sendable {
    public static let minLength = 685
    public let tsEpoch: Int
    public let counter: Int
    public let hr: Int
    public let rrIntervalsMs: [Int]
}

public enum WhoopGen4Decoder {
    private static let legacyMinLength = 89
    private static let shortFrameMinLength = 72
    private static let hrOffsetByVersion: [Int: Int] = [
        7: 27,
        9: 17,
        12: 17,
        18: 14,
        24: 17,
    ]

    public static func decodeR24(_ inner: [UInt8]) -> WhoopR24Record? {
        decode(inner, minLength: legacyMinLength)
    }

    public static func decodeFirmwareAwareR24(_ inner: [UInt8]) -> WhoopR24Record? {
        if let full = decode(inner, minLength: legacyMinLength) { return full }
        guard inner.count >= shortFrameMinLength else { return nil }
        let padded = inner + [UInt8](repeating: 0, count: max(0, legacyMinLength - inner.count))
        return decode(padded, minLength: legacyMinLength)
    }

    public static func decodeR10Lite(_ inner: [UInt8]) -> WhoopR10Lite? {
        guard inner.count >= 18 else { return nil }
        let pkt = inner[0]
        guard pkt == WhoopPacketType.realtimeRawData ||
              (pkt == WhoopPacketType.historicalData && inner.count >= WhoopR10Lite.minLength) else {
            return nil
        }
        guard inner[1] == 10 else { return nil }
        let counter = Int(WhoopBytes.u32(inner, 3))
        let tsEpoch = Int(WhoopBytes.u32(inner, 7))
        let hr = Int(inner[17])
        var rrs: [Int] = []
        if inner.count >= 19 {
            let declared = Int(inner[18])
            if declared > 0 && declared <= WhoopR24Record.maxR10RrSlots {
                for i in 0..<declared where 19 + 2 * i + 2 <= inner.count {
                    let v = Int(WhoopBytes.i16(inner, 19 + 2 * i))
                    if v >= WhoopR24Record.minRrMs && v <= WhoopR24Record.maxRrMs {
                        rrs.append(v)
                    }
                }
            }
        }
        return WhoopR10Lite(tsEpoch: tsEpoch, counter: counter, hr: hr, rrIntervalsMs: rrs)
    }

    private static func decode(_ inner: [UInt8], minLength: Int) -> WhoopR24Record? {
        guard inner.count >= 2 else { return nil }
        guard inner[0] == WhoopPacketType.historicalData || inner[0] == WhoopPacketType.realtimeData else {
            return nil
        }
        let version = Int(inner[1])
        if version == 25 {
            guard inner.count >= 75 else { return nil }
            return WhoopR24Record(
                histVersion: 25,
                tsEpoch: Int(WhoopBytes.u32(inner, 7)),
                tsSubsec: 0,
                counter: Int(WhoopBytes.u32(inner, 3)),
                hr: 0,
                rrCount: 0,
                rrIntervalsMs: [],
                ppgGreen: 0,
                accelG: [],
                spo2RedRaw: 0,
                spo2IrRaw: 0,
                skinTempRaw: 0,
                ambientRaw: 0)
        }

        guard inner.count >= minLength else { return nil }
        let trusted = (version == 24 || version == 12)
        let validate = !trusted
        let hrOffset = hrOffsetByVersion[version] ?? 17
        guard hrOffset < inner.count else { return nil }

        var rrIntervalsMs: [Int] = []
        if !validate {
            let declaredRr = Int(inner[18])
            if declaredRr <= WhoopR24Record.maxV24RrSlots {
                for i in 0..<declaredRr where 19 + 2 * i + 2 <= inner.count {
                    let v = Int(WhoopBytes.i16(inner, 19 + 2 * i))
                    if v >= WhoopR24Record.minRrMs && v <= WhoopR24Record.maxRrMs {
                        rrIntervalsMs.append(v)
                    }
                }
            }
        }

        let hr = Int(inner[hrOffset])
        let ax = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 36)), decimals: 4)
        let ay = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 40)), decimals: 4)
        let az = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 44)), decimals: 4)
        guard ax.isFinite, ay.isFinite, az.isFinite else { return nil }

        if validate {
            let magSq = ax * ax + ay * ay + az * az
            guard (25...230).contains(hr), magSq >= 0.25, magSq <= 3.24 else { return nil }
        }

        return WhoopR24Record(
            histVersion: version,
            tsEpoch: Int(WhoopBytes.u32(inner, 7)),
            tsSubsec: Int(WhoopBytes.u16(inner, 11)),
            counter: Int(WhoopBytes.u32(inner, 3)),
            hr: hr,
            rrCount: rrIntervalsMs.count,
            rrIntervalsMs: rrIntervalsMs,
            ppgGreen: validate ? 0 : Int(WhoopBytes.u16(inner, 29)),
            accelG: [ax, ay, az],
            spo2RedRaw: validate ? 0 : Int(WhoopBytes.u16(inner, 64)),
            spo2IrRaw: validate ? 0 : Int(WhoopBytes.u16(inner, 66)),
            skinTempRaw: validate ? 0 : Int(WhoopBytes.u16(inner, 68)),
            ambientRaw: validate ? 0 : Int(WhoopBytes.u16(inner, 70)))
    }
}

public enum WhoopGen5SleepState: Int, Equatable, Sendable {
    case wake = 0
    case still = 1
    case sleep = 2
    case up = 3
}

public struct WhoopGen5HistoricalHeader: Equatable, Sendable {
    public let version: Int
    public let flags: UInt8
    public let recordIndex: Int
    public let unix: Int
    public let tsSubsec: Int?

    public var ppgSampleRateHz: Int { (flags & 0x80) != 0 ? 25 : 50 }

    public static func tryParse(_ inner: [UInt8]) -> WhoopGen5HistoricalHeader? {
        guard inner.count >= 11 else { return nil }
        return WhoopGen5HistoricalHeader(
            version: Int(inner[1]),
            flags: inner[2],
            recordIndex: Int(WhoopBytes.u32(inner, 3)),
            unix: Int(WhoopBytes.u32(inner, 7)),
            tsSubsec: inner.count >= 13 ? Int(WhoopBytes.u16(inner, 11)) : nil)
    }
}

public struct WhoopGen5HistorySample: Equatable, Sendable {
    public static let skinTempUnavailableRaw: Int16 = -5000
    public static let minReadableLen = 109
    public static let canonicalInnerLen = 112

    public let histVersion: Int
    public let flags: UInt8
    public let recordIndex: Int
    public let unix: Int
    public let tsSubsec: Int
    public let heartRate: Int
    public let rrCount: Int
    public let rrIntervalsMs: [Int]
    public let cardiacFlags: UInt8
    public let hrQualityFlags: UInt8
    public let heartRateAlt: Int
    public let rrPacked: Int
    public let cardiacStatusRaw: UInt8
    public let dynamicAccelerationG: Double?
    public let gravityG: [Double]
    public let stepMotionCounter: Int
    public let stepCadence: Int
    public let activityClass: UInt8
    public let tempAux1C: Double
    public let tempAux2C: Double
    public let skinTempRawCenti: Int16
    public let skinTempC: Double
    public let statusWord: UInt16
    public let statusWord1: UInt16
    public let statusWord2: UInt16
    public let sleepStateByte: UInt8
    public let spo2CandidateRaw: UInt8
    public let pdMeanB: UInt8
    public let pdMeanA: UInt8
    public let psnrB: Int
    public let psnrA: Int
    public let signalQualityLogVariance: Double?

    public var ppgSampleRateHz: Int { (flags & 0x80) != 0 ? 25 : 50 }
    public var activityClassKnown: Int? {
        (activityClass == 0 || activityClass == 1 || activityClass == 2) ? Int(activityClass) : nil
    }
    public var skinTempCOrNull: Double? {
        guard skinTempRawCenti != Self.skinTempUnavailableRaw, skinTempC >= -40.0, skinTempC <= 60.0 else {
            return nil
        }
        return skinTempC
    }
    public var sleepStateRawNibble: Int { Int((sleepStateByte >> 4) & 0x03) }
    public var sleepState: WhoopGen5SleepState { WhoopGen5SleepState(rawValue: sleepStateRawNibble) ?? .wake }
}

public struct WhoopGen5ImuBuffer: Equatable, Sendable {
    public static let innerLen = 1232
    public static let accelScaleG = 1.0 / 4096.0
    public static let gyroScaleDps = 2000.0 / 32768.0

    public let header: WhoopGen5HistoricalHeader
    public let countA: Int
    public let countB: Int
    public let accelXg: [Double]
    public let accelYg: [Double]
    public let accelZg: [Double]
    public let gyroXdps: [Double]
    public let gyroYdps: [Double]
    public let gyroZdps: [Double]
}

public struct WhoopLabradorR16Raw: Equatable, Sendable {
    public let sequence: Int
    public let strapSeconds: Int
    public let subseconds: Int
    public let innerHex: String
}

public enum WhoopGen5HistoricalKind: Equatable, Sendable {
    case v18(WhoopGen5HistorySample)
    case rawArchive(version: Int, header: WhoopGen5HistoricalHeader, reason: String)
    case ecgRaw(WhoopLabradorR16Raw)
}

public enum WhoopGen5Decoder {
    public static func decodeV18(_ inner: [UInt8]) -> WhoopGen5HistorySample? {
        guard inner.count >= WhoopGen5HistorySample.minReadableLen,
              inner[0] == WhoopPacketType.historicalData,
              inner[1] == 18,
              let hdr = WhoopGen5HistoricalHeader.tryParse(inner) else { return nil }

        let hrRaw = Int(inner[14])
        let hr = (25...230).contains(hrRaw) ? hrRaw : 0

        let declaredRr = Int(inner[15])
        var rrs: [Int] = []
        if declaredRr <= 4 {
            for i in 0..<declaredRr where 16 + 2 * i + 2 <= inner.count {
                let val = Int(WhoopBytes.i16(inner, 16 + 2 * i))
                if val >= WhoopR24Record.minRrMs && val <= WhoopR24Record.maxRrMs {
                    rrs.append(val)
                }
            }
        }

        let fullScaleG = 16.0
        let dynAccel = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 33)), decimals: 4)
        let dynOk = dynAccel.isFinite && dynAccel >= 0.0 && dynAccel <= fullScaleG

        let gx = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 37)), decimals: 4)
        let gy = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 41)), decimals: 4)
        let gz = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 45)), decimals: 4)
        let gravOk = gx.isFinite && gy.isFinite && gz.isFinite
            && abs(gx) <= fullScaleG && abs(gy) <= fullScaleG && abs(gz) <= fullScaleG

        let rawAux1 = WhoopBytes.i16(inner, 61)
        let rawAux2 = WhoopBytes.i16(inner, 63)
        let rawSkin = WhoopBytes.i16(inner, 65)

        let logVarRaw = WhoopBytes.jsRound(Double(WhoopBytes.f32(inner, 105)), decimals: 4)

        return WhoopGen5HistorySample(
            histVersion: hdr.version,
            flags: hdr.flags,
            recordIndex: hdr.recordIndex,
            unix: hdr.unix,
            tsSubsec: Int(WhoopBytes.u16(inner, 11)),
            heartRate: hr,
            rrCount: rrs.count,
            rrIntervalsMs: rrs,
            cardiacFlags: inner[25],
            hrQualityFlags: inner[28],
            heartRateAlt: Int(inner[29]),
            rrPacked: Int(WhoopBytes.u16(inner, 30)),
            cardiacStatusRaw: inner[32],
            dynamicAccelerationG: dynOk ? dynAccel : nil,
            gravityG: gravOk ? [gx, gy, gz] : [],
            stepMotionCounter: Int(WhoopBytes.u16(inner, 49)),
            stepCadence: Int(inner[51]),
            activityClass: inner[55],
            tempAux1C: WhoopBytes.jsRound(Double(rawAux1) / 10.0, decimals: 2),
            tempAux2C: WhoopBytes.jsRound(Double(rawAux2) / 10.0, decimals: 2),
            skinTempRawCenti: rawSkin,
            skinTempC: WhoopBytes.jsRound(Double(rawSkin) / 100.0, decimals: 2),
            statusWord: WhoopBytes.u16(inner, 67),
            statusWord1: WhoopBytes.u16(inner, 69),
            statusWord2: WhoopBytes.u16(inner, 71),
            sleepStateByte: inner[73],
            spo2CandidateRaw: inner[74],
            pdMeanB: inner[98],
            pdMeanA: inner[99],
            psnrB: Int(Int8(bitPattern: inner[100])),
            psnrA: Int(Int8(bitPattern: inner[101])),
            signalQualityLogVariance: logVarRaw.isFinite ? logVarRaw : nil)
    }

    public static func isGen5ImuBuffer(_ inner: [UInt8]) -> Bool {
        guard inner.count == WhoopGen5ImuBuffer.innerLen else { return false }
        let countA = Int(WhoopBytes.u16(inner, 16))
        let countB = Int(WhoopBytes.u16(inner, 622))
        return (1...100).contains(countA) && (1...100).contains(countB)
    }

    public static func parseGen5ImuBuffer(_ inner: [UInt8]) -> WhoopGen5ImuBuffer? {
        guard isGen5ImuBuffer(inner), let hdr = WhoopGen5HistoricalHeader.tryParse(inner) else { return nil }
        let countA = Int(WhoopBytes.u16(inner, 16))
        let countB = Int(WhoopBytes.u16(inner, 622))
        func axis(start: Int, scale: Double, count: Int) -> [Double] {
            (0..<count).map { Double(WhoopBytes.i16(inner, start + 2 * $0)) * scale }
        }
        return WhoopGen5ImuBuffer(
            header: hdr, countA: countA, countB: countB,
            accelXg: axis(start: 20, scale: WhoopGen5ImuBuffer.accelScaleG, count: countA),
            accelYg: axis(start: 220, scale: WhoopGen5ImuBuffer.accelScaleG, count: countA),
            accelZg: axis(start: 420, scale: WhoopGen5ImuBuffer.accelScaleG, count: countA),
            gyroXdps: axis(start: 632, scale: WhoopGen5ImuBuffer.gyroScaleDps, count: countB),
            gyroYdps: axis(start: 832, scale: WhoopGen5ImuBuffer.gyroScaleDps, count: countB),
            gyroZdps: axis(start: 1032, scale: WhoopGen5ImuBuffer.gyroScaleDps, count: countB))
    }

    public static func classifyHistorical(_ inner: [UInt8]) -> WhoopGen5HistoricalKind? {
        guard inner.count >= 13, inner[0] == WhoopPacketType.historicalData,
              let hdr = WhoopGen5HistoricalHeader.tryParse(inner) else { return nil }
        switch hdr.version {
        case 18:
            if let v18 = decodeV18(inner) { return .v18(v18) }
            return .rawArchive(version: 18, header: hdr, reason: "undecodable_rec_v18")
        case 16:
            return .ecgRaw(WhoopLabradorR16Raw(
                sequence: hdr.recordIndex,
                strapSeconds: hdr.unix,
                subseconds: hdr.tsSubsec ?? 0,
                innerHex: WhoopBytes.hex(inner)))
        case 20, 21, 22, 26:
            return .rawArchive(version: hdr.version, header: hdr, reason: "undecodable_rec_v\(hdr.version)")
        default:
            return .rawArchive(version: hdr.version, header: hdr, reason: "undecodable_rec_v\(hdr.version)")
        }
    }
}
