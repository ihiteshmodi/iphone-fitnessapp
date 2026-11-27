import Foundation

public enum WhoopDeviceType: String, Codable, Equatable, Sendable {
    case gen4
    case gen5
}

public struct WhoopGattProfile: Equatable, Sendable {
    public let service: String
    public let advertisedServiceShort: String?
    public let cmdTo: String
    public let cmdFrom: String
    public let events: String
    public let data: String
    public let memfault: String

    public static let gen4 = WhoopGattProfile(
        service: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6",
        advertisedServiceShort: nil,
        cmdTo: "61080002-8d6d-82b8-614a-1c8cb0f8dcc6",
        cmdFrom: "61080003-8d6d-82b8-614a-1c8cb0f8dcc6",
        events: "61080004-8d6d-82b8-614a-1c8cb0f8dcc6",
        data: "61080005-8d6d-82b8-614a-1c8cb0f8dcc6",
        memfault: "61080007-8d6d-82b8-614a-1c8cb0f8dcc6")

    public static let gen5 = WhoopGattProfile(
        service: "fd4b0001-cce1-4033-93ce-002d5875f58a",
        advertisedServiceShort: "FD4B",
        cmdTo: "fd4b0002-cce1-4033-93ce-002d5875f58a",
        cmdFrom: "fd4b0003-cce1-4033-93ce-002d5875f58a",
        events: "fd4b0004-cce1-4033-93ce-002d5875f58a",
        data: "fd4b0005-cce1-4033-93ce-002d5875f58a",
        memfault: "fd4b0007-cce1-4033-93ce-002d5875f58a")

    public static let maverick = WhoopGattProfile(
        service: "a7c10001-f166-4c36-9f61-547f9a0d0173",
        advertisedServiceShort: "FD4B",
        cmdTo: "a7c10002-f166-4c36-9f61-547f9a0d0173",
        cmdFrom: "a7c10003-f166-4c36-9f61-547f9a0d0173",
        events: "a7c10004-f166-4c36-9f61-547f9a0d0173",
        data: "a7c10005-f166-4c36-9f61-547f9a0d0173",
        memfault: "a7c10007-f166-4c36-9f61-547f9a0d0173")

    public static let whoopAdvService16Bit = "FD4B"
}

public enum WhoopBandProfile: String, Codable, Equatable, Sendable {
    case gen4
    case gen5

    public var isGen5: Bool { self == .gen5 }
    public var headerLen: Int { isGen5 ? 8 : 4 }
    public var sizeFieldOffset: Int { isGen5 ? 2 : 1 }
    public var maxDeclaredLen: Int { isGen5 ? 3072 : 4096 }
    public var burstCountGateEnforced: Bool { isGen5 }
    public var gatt: WhoopGattProfile { isGen5 ? .gen5 : .gen4 }
}

public enum WhoopPacketType {
    public static let command: UInt8 = 0x23
    public static let commandResponse: UInt8 = 0x24
    public static let puffinCommand: UInt8 = 0x25
    public static let puffinCommandResponse: UInt8 = 0x26
    public static let realtimeData: UInt8 = 0x28
    public static let realtimeRawData: UInt8 = 0x2B
    public static let historicalData: UInt8 = 0x2F
    public static let event: UInt8 = 0x30
    public static let metadata: UInt8 = 0x31
    public static let consoleLogs: UInt8 = 0x32
    public static let realtimeImuStream: UInt8 = 0x33
    public static let historicalImuStream: UInt8 = 0x34
    public static let relativePuffinEvents: UInt8 = 0x35
    public static let puffinEventsFromStrap: UInt8 = 0x36
    public static let relativeBatteryPackConsoleLogs: UInt8 = 0x37
    public static let puffinMetadata: UInt8 = 0x38
}

public enum WhoopCmd {
    public static let linkValid: UInt8 = 0x01
    public static let toggleRealtimeHr: UInt8 = 0x03
    public static let reportVersionInfo: UInt8 = 0x07
    public static let setClock: UInt8 = 0x0A
    public static let getClock: UInt8 = 0x0B
    public static let setGenericHrProfile: UInt8 = 0x0E
    public static let forgetBonds: UInt8 = 0x0F
    public static let runHapticPatternMaverick: UInt8 = 0x13
    public static let abortHistoricalTransmits: UInt8 = 0x14
    public static let sendHistoricalData: UInt8 = 0x16
    public static let historicalDataResult: UInt8 = 0x17
    public static let forceTrim: UInt8 = 0x19
    public static let getBatteryLevel: UInt8 = 0x1A
    public static let rebootStrap: UInt8 = 0x1D
    public static let powerCycleStrap: UInt8 = 0x20
    public static let setReadPointer: UInt8 = 0x21
    public static let getDataRange: UInt8 = 0x22
    public static let getHelloHarvard: UInt8 = 0x23
    public static let startUpdateLoad: UInt8 = 0x24
    public static let loadUpdateData: UInt8 = 0x25
    public static let processUpdateImage: UInt8 = 0x26
    public static let sendR10R11Realtime: UInt8 = 0x3F
    public static let setAlarmTime: UInt8 = 0x42
    public static let getAlarmTime: UInt8 = 0x43
    public static let runAlarm: UInt8 = 0x44
    public static let disableAlarm: UInt8 = 0x45
    public static let getAdvertisingNameHarvard: UInt8 = 0x4C
    public static let setAdvertisingNameHarvard: UInt8 = 0x4D
    public static let runHapticsPattern: UInt8 = 0x4F
    public static let startRawData: UInt8 = 0x51
    public static let stopRawData: UInt8 = 0x52
    public static let verifyImage: UInt8 = 0x53
    public static let getBodyLocationAndStatus: UInt8 = 0x54
    public static let enterHighFreqSync: UInt8 = 0x60
    public static let exitHighFreqSync: UInt8 = 0x61
    public static let toggleImuMode: UInt8 = 0x6A
    public static let enableOpticalData: UInt8 = 0x6B
    public static let toggleOpticalMode: UInt8 = 0x6C
    public static let setDeviceConfigValue: UInt8 = 0x77
    public static let setFfValue: UInt8 = 0x78
    public static let selectWrist: UInt8 = 0x7B
    public static let toggleLabradorDataGeneration: UInt8 = 0x7C
    public static let toggleLabradorRawSave: UInt8 = 0x7D
    public static let setSignalConfig: UInt8 = 0x8A
    public static let toggleLabradorFiltered: UInt8 = 0x8B
    public static let setCustomAdvertisingName: UInt8 = 0x8C
    public static let getCustomAdvertisingName: UInt8 = 0x8D
    public static let startLoadGen5: UInt8 = 0x8E
    public static let loadDataGen5: UInt8 = 0x8F
    public static let processImageGen5: UInt8 = 0x90
    public static let getHello: UInt8 = 0x91
    public static let setClockMaverick: UInt8 = 0x92
    public static let getClockGen5: UInt8 = 0x93
    public static let wearDetectOverride: UInt8 = 0x94
    public static let setLedAccessibility: UInt8 = 0x95
    public static let getBatteryPackInfo: UInt8 = 0x97
    public static let persistentOpticalSave: UInt8 = 0x99
    public static let togglePersistentR21: UInt8 = 0x9A
}

public enum WhoopCRC {
    private static let crc8Table: [UInt8] = [
        0, 7, 14, 9, 28, 27, 18, 21, 56, 63, 54, 49, 36, 35, 42, 45,
        112, 119, 126, 121, 108, 107, 98, 101, 72, 79, 70, 65, 84, 83, 90, 93,
        224, 231, 238, 233, 252, 251, 242, 245, 216, 223, 214, 209, 196, 195, 202, 205,
        144, 151, 158, 153, 140, 139, 130, 133, 168, 175, 166, 161, 180, 179, 186, 189,
        199, 192, 201, 206, 219, 220, 213, 210, 255, 248, 241, 246, 227, 228, 237, 234,
        183, 176, 185, 190, 171, 172, 165, 162, 143, 136, 129, 134, 147, 148, 157, 154,
        39, 32, 41, 46, 59, 60, 53, 50, 31, 24, 17, 22, 3, 4, 13, 10,
        87, 80, 89, 94, 75, 76, 69, 66, 111, 104, 97, 102, 115, 116, 125, 122,
        137, 142, 135, 128, 149, 146, 155, 156, 177, 182, 191, 184, 173, 170, 163, 164,
        249, 254, 247, 240, 229, 226, 235, 236, 193, 198, 207, 200, 221, 218, 211, 212,
        105, 110, 103, 96, 117, 114, 123, 124, 81, 86, 95, 88, 77, 74, 67, 68,
        25, 30, 23, 16, 5, 2, 11, 12, 33, 38, 47, 40, 61, 58, 51, 52,
        78, 73, 64, 71, 82, 85, 92, 91, 118, 113, 120, 127, 106, 109, 100, 99,
        62, 57, 48, 55, 34, 37, 44, 43, 6, 1, 8, 15, 26, 29, 20, 19,
        174, 169, 160, 167, 178, 181, 188, 187, 150, 145, 152, 159, 138, 141, 132, 131,
        222, 217, 208, 215, 194, 197, 204, 203, 230, 225, 232, 239, 250, 253, 244, 243,
    ]

    private static let crc32Table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    public static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var crc: UInt8 = 0
        for b in bytes {
            crc = crc8Table[Int(crc ^ b)]
        }
        return crc
    }

    public static func crc16Modbus(_ bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for b in bytes {
            crc ^= UInt16(b)
            for _ in 0..<8 {
                if (crc & 1) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }
        return crc
    }

    public static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in bytes {
            let idx = Int((crc ^ UInt32(b)) & 0xFF)
            crc = crc32Table[idx] ^ (crc >> 8)
        }
        return ~crc
    }
}

public enum WhoopBytes {
    @inline(__always)
    public static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    @inline(__always)
    public static func i16(_ b: [UInt8], _ o: Int) -> Int16 {
        Int16(bitPattern: u16(b, o))
    }

    @inline(__always)
    public static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }

    @inline(__always)
    public static func i32(_ b: [UInt8], _ o: Int) -> Int32 {
        Int32(bitPattern: u32(b, o))
    }

    @inline(__always)
    public static func f32(_ b: [UInt8], _ o: Int) -> Float {
        Float(bitPattern: u32(b, o))
    }

    public static func jsRound(_ v: Double, decimals: Int) -> Double {
        guard v.isFinite else { return v }
        var p = 1.0
        for _ in 0..<decimals { p *= 10.0 }
        return floor(v * p + 0.5) / p
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public struct WhoopFrame: Equatable, Sendable {
    public let inner: [UInt8]
    public let headerCrcOk: Bool
    public let crc32Ok: Bool
    public let frameRevOk: Bool
    public let truncated: Bool

    public init(inner: [UInt8], headerCrcOk: Bool, crc32Ok: Bool, frameRevOk: Bool = true, truncated: Bool = false) {
        self.inner = inner
        self.headerCrcOk = headerCrcOk
        self.crc32Ok = crc32Ok
        self.frameRevOk = frameRevOk
        self.truncated = truncated
    }

    public var valid: Bool { headerCrcOk && crc32Ok }
    public var decodable: Bool { valid && frameRevOk }
    public var packetType: Int { inner.first.map(Int.init) ?? -1 }
    public var seq: Int { inner.count > 1 ? Int(inner[1]) : -1 }
    public var opcode: UInt8 { inner.count > 2 ? inner[2] : 0 }
    public var body: [UInt8] { inner.count > 3 ? Array(inner.dropFirst(3)) : [] }
}

public enum WhoopFraming {
    public static let sof: UInt8 = 0xAA
    public static let revision1: UInt8 = 0x01

    public static func pad4(_ bytes: [UInt8]) -> [UInt8] {
        let pad = (4 - (bytes.count % 4)) % 4
        guard pad > 0 else { return bytes }
        return bytes + [UInt8](repeating: 0, count: pad)
    }

    public static func buildHeader(declared: Int, profile: WhoopBandProfile) -> [UInt8] {
        let lo = UInt8(declared & 0xFF)
        let hi = UInt8((declared >> 8) & 0xFF)
        if !profile.isGen5 {
            return [sof, lo, hi, WhoopCRC.crc8([lo, hi])]
        }
        var h: [UInt8] = [sof, revision1, lo, hi, 0x00, 0x01]
        let c16 = WhoopCRC.crc16Modbus(h)
        h.append(UInt8(c16 & 0xFF))
        h.append(UInt8((c16 >> 8) & 0xFF))
        return h
    }

    public static func headerCrcValid(_ raw: [UInt8], profile: WhoopBandProfile) -> Bool {
        if !profile.isGen5 {
            guard raw.count >= 4 else { return false }
            return raw[3] == WhoopCRC.crc8([raw[1], raw[2]])
        }
        guard raw.count >= 8 else { return false }
        let want = UInt16(raw[6]) | (UInt16(raw[7]) << 8)
        return WhoopCRC.crc16Modbus(Array(raw[0..<6])) == want
    }

    public static func declaredLength(_ raw: [UInt8], profile: WhoopBandProfile) -> Int {
        let off = profile.sizeFieldOffset
        return Int(raw[off]) | (Int(raw[off + 1]) << 8)
    }

    public static func buildFrame(_ inner: [UInt8], profile: WhoopBandProfile = .gen4) -> [UInt8] {
        let padded = pad4(inner)
        let declared = padded.count + 4
        let header = buildHeader(declared: declared, profile: profile)
        let c32 = WhoopCRC.crc32(padded)
        let tail: [UInt8] = [
            UInt8(c32 & 0xFF),
            UInt8((c32 >> 8) & 0xFF),
            UInt8((c32 >> 16) & 0xFF),
            UInt8((c32 >> 24) & 0xFF),
        ]
        return header + padded + tail
    }

    public static func parseFrame(_ raw: [UInt8], profile: WhoopBandProfile = .gen4) -> WhoopFrame? {
        let headerLen = profile.headerLen
        guard raw.count >= headerLen + 4, raw[0] == sof else { return nil }
        let declared = declaredLength(raw, profile: profile)
        guard declared >= 4 else { return nil }
        let total = headerLen + declared
        guard raw.count >= total else { return nil }
        let hdrOk = headerCrcValid(raw, profile: profile)
        let innerEnd = headerLen + declared - 4
        let inner = Array(raw[headerLen..<innerEnd])
        let stored = WhoopBytes.u32(raw, innerEnd)
        let revOk = !profile.isGen5 || raw[1] == revision1
        return WhoopFrame(inner: inner, headerCrcOk: hdrOk, crc32Ok: stored == WhoopCRC.crc32(inner), frameRevOk: revOk)
    }
}

public struct WhoopFrameAccumulator: Sendable {
    public let profile: WhoopBandProfile
    private var buf: [UInt8] = []
    public private(set) var resyncs = 0
    public private(set) var headerCrcErrors = 0
    public private(set) var lostFrames = 0

    public init(profile: WhoopBandProfile = .gen4) {
        self.profile = profile
    }

    public mutating func clearBuffer() {
        buf.removeAll()
    }

    public mutating func reset() {
        buf.removeAll()
        resyncs = 0
        headerCrcErrors = 0
        lostFrames = 0
    }

    private mutating func resync() -> Bool {
        resyncs += 1
        guard buf.count > 1, let nextIdx = buf.dropFirst().firstIndex(of: WhoopFraming.sof) else {
            buf.removeAll()
            return false
        }
        buf.removeFirst(nextIdx)
        return true
    }

    public mutating func feed(_ chunk: [UInt8]) -> [WhoopFrame] {
        var out: [WhoopFrame] = []
        buf.append(contentsOf: chunk)
        let headerLen = profile.headerLen

        while buf.count >= headerLen + 4 {
            if buf[0] != WhoopFraming.sof {
                if !resync() { break }
                continue
            }
            let declared = WhoopFraming.declaredLength(buf, profile: profile)
            let total = headerLen + declared
            if declared < 4 || declared > profile.maxDeclaredLen {
                if !resync() { break }
                continue
            }
            if !WhoopFraming.headerCrcValid(buf, profile: profile) {
                headerCrcErrors += 1
                if !resync() { break }
                continue
            }
            if buf.count < total {
                break
            }
            let rawFrame = Array(buf.prefix(total))
            buf.removeFirst(total)
            if let frame = WhoopFraming.parseFrame(rawFrame, profile: profile) {
                if !frame.valid { lostFrames += 1 }
                out.append(frame)
            }
        }
        return out
    }
}

public enum WhoopBeatTiming {
    public static let minPlausibleRrMs = 250
    public static let maxPlausibleRrMs = 2400

    /// Reconstructs per-beat epoch end milliseconds walking backward from `recTs + tsSubsec / 32768`.
    public static func beatTimesMs(recTs: Int, tsSubsec: Int?, rrMs: [Int]) -> [Int64?] {
        var out = [Int64?](repeating: nil, count: rrMs.count)
        guard let tsSubsec, !rrMs.isEmpty, tsSubsec >= 0, tsSubsec < 32768 else { return out }
        let anchor = Int64(recTs) * 1000 + (Int64(tsSubsec) * 1000) / 32768
        var back: Int64 = 0
        for i in stride(from: rrMs.count - 1, through: 0, by: -1) {
            out[i] = anchor - back
            let interval = rrMs[i]
            guard interval >= minPlausibleRrMs && interval <= maxPlausibleRrMs else { break }
            back += Int64(interval)
        }
        return out
    }

    public static func monotonizeBeatAxis(_ rrTsMs: [Int64]) -> [Int64] {
        guard rrTsMs.count > 1 else { return rrTsMs }
        var out = rrTsMs
        for i in 1..<out.count where out[i] < out[i - 1] {
            out[i] = out[i - 1]
        }
        return out
    }
}
