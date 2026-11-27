import Foundation

public enum WhoopWristSelection: UInt8, Equatable, Sendable {
    case right = 0x01
    case left = 0x02
}

public enum WhoopCommands {
    public static let defaultAlarmHaptics: [UInt8] = [
        47, 152, 0, 0, 0, 0, 0, 0,
        0, 0,
        7,
        30,
    ]

    /// Hard-blocked opcodes from `edge-main` (`dangerousCmds`). Never auto-sent without explicit opt-in.
    public static let dangerousOpcodes: Set<UInt8> = [
        WhoopCmd.setGenericHrProfile,      // 0x0E
        WhoopCmd.forgetBonds,              // 0x0F
        WhoopCmd.forceTrim,                // 0x19
        WhoopCmd.rebootStrap,              // 0x1D
        WhoopCmd.powerCycleStrap,          // 0x20
        WhoopCmd.setReadPointer,           // 0x21
        WhoopCmd.startUpdateLoad,          // 0x24
        WhoopCmd.loadUpdateData,           // 0x25
        WhoopCmd.processUpdateImage,       // 0x26
        WhoopCmd.verifyImage,              // 0x53
        WhoopCmd.setDeviceConfigValue,     // 0x77
        WhoopCmd.setFfValue,               // 0x78
        WhoopCmd.setSignalConfig,          // 0x8A
        WhoopCmd.startLoadGen5,            // 0x8E
        WhoopCmd.loadDataGen5,             // 0x8F
        WhoopCmd.processImageGen5,         // 0x90
        WhoopCmd.setClockMaverick,         // 0x92
        WhoopCmd.wearDetectOverride,       // 0x94
        WhoopCmd.setLedAccessibility,      // 0x95
        WhoopCmd.persistentOpticalSave,    // 0x99
        WhoopCmd.togglePersistentR21,      // 0x9A
    ]

    /// Fix #1: Exact 8-flag Gen5 R22 unlock sequence (`'1'` = enable, `'2'` = disable suppressor).
    public static let gen5R22EnableFlags: [(String, String)] = [
        ("enable_r22_packets", "1"),
        ("enable_r22_v2_packets", "1"),
        ("enable_r22_v3_packets", "1"),
        ("enable_r22_v4_packets", "1"),
        ("enable_r22_v5_packets", "1"),
        ("enable_r22_v6_packets", "1"),
        ("enable_r22_v8_packets", "1"),
        ("disable_pip_r26_packets", "2"),
    ]

    public static let gen5R22ContestedFlagNames: Set<String> = [
        "enable_r22_v4_packets",
        "enable_r22_v8_packets",
    ]

    public static func isDangerousOpcode(_ opcode: UInt8) -> Bool {
        dangerousOpcodes.contains(opcode)
    }

    public static func buildCommand(seq: UInt8, opcode: UInt8, payload: [UInt8] = [0x00],
                                    profile: WhoopBandProfile = .gen4) -> [UInt8] {
        let inner: [UInt8] = [WhoopPacketType.command, seq, opcode] + payload
        return WhoopFraming.buildFrame(inner, profile: profile)
    }

    public static func guardedCommand(seq: UInt8, opcode: UInt8, payload: [UInt8],
                                      profile: WhoopBandProfile, allowDangerous: Bool = false) throws -> [UInt8] {
        if isDangerousOpcode(opcode) && !allowDangerous {
            throw ValidationError(String(format: "Blocked dangerous WHOOP opcode 0x%02X", opcode))
        }
        return buildCommand(seq: seq, opcode: opcode, payload: payload, profile: profile)
    }

    private static func leTimestamp(sec: UInt32, subsec: UInt16) -> [UInt8] {
        [
            UInt8(sec & 0xFF),
            UInt8((sec >> 8) & 0xFF),
            UInt8((sec >> 16) & 0xFF),
            UInt8((sec >> 24) & 0xFF),
            UInt8(subsec & 0xFF),
            UInt8((subsec >> 8) & 0xFF),
        ]
    }

    public static func buildSetClockPayload(epochMs: Int64) -> [UInt8] {
        let sec = UInt32(clamping: max(0, epochMs / 1000))
        let remMs = max(0, epochMs % 1000)
        let subsec = UInt16((remMs * 32768) / 1000)
        return leTimestamp(sec: sec, subsec: subsec) + [0x00, 0x00]
    }

    public static func cmdSetClock(seq: UInt8, epochMs: Int64, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.setClock, payload: buildSetClockPayload(epochMs: epochMs), profile: profile)
    }

    public static func cmdGetClock(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.getClock, payload: [], profile: profile)
    }

    public static func cmdLinkValid(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.linkValid, payload: [0x00], profile: profile)
    }

    public static func cmdGetBattery(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.getBatteryLevel, payload: [], profile: profile)
    }

    public static func cmdGetDataRange(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.getDataRange, payload: profile.isGen5 ? [] : [0x00], profile: profile)
    }

    public static func cmdSendHistorical(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.sendHistoricalData, payload: profile.isGen5 ? [] : [0x00], profile: profile)
    }

    public static func cmdAbortHistorical(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.abortHistoricalTransmits, payload: [0x00], profile: profile)
    }

    public static func buildHistoryResultOk(seq: UInt8, token: [UInt8], profile: WhoopBandProfile = .gen4) throws -> [UInt8] {
        guard token.count == 8 else {
            throw ValidationError("WHOOP history token must be 8 bytes, got \(token.count)")
        }
        return buildCommand(seq: seq, opcode: WhoopCmd.historicalDataResult, payload: [0x01] + token, profile: profile)
    }

    /// Fix #4: Gen5 requires 2 zero bytes `[0x00, 0x00]` on negative ACK; Gen4 uses `[0x00]`.
    public static func buildHistoryResultFail(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.historicalDataResult,
                     payload: profile.isGen5 ? [0x00, 0x00] : [0x00], profile: profile)
    }

    /// Canonical 16-byte Gen5 CLIENT_HELLO (`0x91`, payload `[0x01]`).
    public static func gen5ClientHello(seq: UInt8 = 1) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.getHello, payload: [0x01], profile: .gen5)
    }

    public static func gen4InitPackets() -> [[UInt8]] {
        [
            buildCommand(seq: 0, opcode: WhoopCmd.getHelloHarvard, payload: [0x00], profile: .gen4),
            buildCommand(seq: 1, opcode: WhoopCmd.getAdvertisingNameHarvard, payload: [0x00], profile: .gen4),
            buildCommand(seq: 2, opcode: WhoopCmd.getDataRange, payload: [0x00], profile: .gen4),
            buildCommand(seq: 3, opcode: WhoopCmd.getAlarmTime, payload: [0x01], profile: .gen4),
            buildCommand(seq: 4, opcode: WhoopCmd.sendHistoricalData, payload: [0x00], profile: .gen4),
        ]
    }

    public static func cmdGetCustomAdvName(seq: UInt8) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.getCustomAdvertisingName, payload: [0x01], profile: .gen5)
    }

    public static func cmdGetBatteryPackInfo(seq: UInt8, profile: WhoopBandProfile = .gen5) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.getBatteryPackInfo, payload: [0x01], profile: profile)
    }

    public static func cmdToggleRealtimeHr(seq: UInt8, on: Bool, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.toggleRealtimeHr, payload: [on ? 0x01 : 0x00], profile: profile)
    }

    public static func cmdSendR10R11(seq: UInt8, on: Bool) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.sendR10R11Realtime, payload: [on ? 0x01 : 0x00], profile: .gen4)
    }

    public static func cmdToggleImu(seq: UInt8, on: Bool, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        let payload: [UInt8] = profile.isGen5 ? [0x01, on ? 0x01 : 0x00] : [on ? 0x01 : 0x00]
        return buildCommand(seq: seq, opcode: WhoopCmd.toggleImuMode, payload: payload, profile: profile)
    }

    public static func cmdBuzz(seq: UInt8, pattern: UInt8 = 2, overallLoop: UInt8 = 1, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        if profile.isGen5 {
            let p: [UInt8] = [0x01, 47, 152, 0, 0, 0, 0, 0, 0, 0, 0, overallLoop]
            return buildCommand(seq: seq, opcode: WhoopCmd.runHapticPatternMaverick, payload: p, profile: .gen5)
        }
        return buildCommand(seq: seq, opcode: WhoopCmd.runHapticsPattern, payload: [pattern, 0, 0, 0, 0], profile: .gen4)
    }

    public static func cmdStopHaptics(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: 0x7A, payload: [0x00], profile: profile)
    }

    /// User-gated safety Restart Band (`0x1D` `rebootStrap`). Blocked unless `userConfirmed == true`.
    public static func cmdRestartStrap(seq: UInt8, profile: WhoopBandProfile = .gen5, userConfirmed: Bool) throws -> [UInt8] {
        try guardedCommand(seq: seq, opcode: WhoopCmd.rebootStrap, payload: [0x00], profile: profile, allowDangerous: userConfirmed)
    }

    public static func enterHighFreqSync(seq: UInt8, intervalSeconds: Int, durationSeconds: Int,
                                         profile: WhoopBandProfile = .gen4) throws -> [UInt8] {
        guard (0...0xFFFF).contains(intervalSeconds), (0...0xFFFF).contains(durationSeconds) else {
            throw ValidationError("High-freq sync interval and duration must fit in UInt16")
        }
        if profile.isGen5 {
            guard intervalSeconds > 60 else { throw ValidationError("Gen5 high-freq sync requires interval > 60s") }
            guard durationSeconds < 28800 else { throw ValidationError("Gen5 high-freq sync requires duration < 28800s") }
        }
        let payload: [UInt8] = [
            0x02,
            UInt8(intervalSeconds & 0xFF), UInt8((intervalSeconds >> 8) & 0xFF),
            UInt8(durationSeconds & 0xFF), UInt8((durationSeconds >> 8) & 0xFF),
        ]
        return buildCommand(seq: seq, opcode: WhoopCmd.enterHighFreqSync, payload: payload, profile: profile)
    }

    public static func exitHighFreqSync(seq: UInt8, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.exitHighFreqSync, payload: [], profile: profile)
    }

    public static func alarmRev1Payload(epochMs: Int64, hapticMode: UInt16 = 0) -> [UInt8] {
        let sec = UInt32(clamping: max(0, epochMs / 1000))
        let subsec = UInt16((max(0, epochMs % 1000) * 32768) / 1000)
        return [0x01] + leTimestamp(sec: sec, subsec: subsec) + [UInt8(hapticMode & 0xFF), UInt8((hapticMode >> 8) & 0xFF)]
    }

    public static func cmdSetAlarmGen4Rev1(seq: UInt8, epochMs: Int64, hapticMode: UInt16 = 0) -> [UInt8] {
        buildCommand(seq: seq, opcode: WhoopCmd.setAlarmTime, payload: alarmRev1Payload(epochMs: epochMs, hapticMode: hapticMode), profile: .gen4)
    }

    public static func cmdSetAlarmGen5(seq: UInt8, epochMs: Int64, slot: UInt8 = 1, haptics: [UInt8] = defaultAlarmHaptics) throws -> [UInt8] {
        guard (1...6).contains(slot) else { throw ValidationError("Gen5 alarm slot must be 1..6") }
        guard haptics.count == 12 else { throw ValidationError("Gen5 alarm haptic pattern must be 12 bytes") }
        let sec = UInt32(clamping: max(0, epochMs / 1000))
        let subsec = UInt16((max(0, epochMs % 1000) * 32768) / 1000)
        let payload: [UInt8] = [0x04, slot] + leTimestamp(sec: sec, subsec: subsec) + haptics + [0x00]
        return buildCommand(seq: seq, opcode: WhoopCmd.setAlarmTime, payload: payload, profile: .gen5)
    }

    public static func cmdDisableAlarm(seq: UInt8, slot: UInt8? = nil, profile: WhoopBandProfile = .gen4) -> [UInt8] {
        if profile.isGen5 {
            return buildCommand(seq: seq, opcode: WhoopCmd.disableAlarm, payload: [0x02, slot ?? 0xFF], profile: .gen5)
        }
        return buildCommand(seq: seq, opcode: WhoopCmd.disableAlarm, payload: [0x01], profile: .gen4)
    }

    /// Exact 65-byte `SET_FF_VALUE (0x78)` builder (`[0x01][name:32B NUL-padded][value:32B NUL-padded]`).
    public static func cmdSetConfigGen5(seq: UInt8, name: String, value: String) throws -> [UInt8] {
        let nameBytes = Array(name.utf8)
        let valBytes = Array(value.utf8)
        guard nameBytes.count <= 31, nameBytes.allSatisfy({ $0 <= 0x7F }) else {
            throw ValidationError("Config flag name must be <= 31 ASCII characters")
        }
        guard valBytes.count == 1, valBytes[0] == 0x31 || valBytes[0] == 0x32 || valBytes[0] == 0x30 else {
            throw ValidationError("Config flag value must be '1', '2', or '0'")
        }
        var fieldName = [UInt8](repeating: 0, count: 32)
        fieldName.replaceSubrange(0..<nameBytes.count, with: nameBytes)
        var fieldVal = [UInt8](repeating: 0, count: 32)
        fieldVal[0] = valBytes[0]
        return try guardedCommand(seq: seq, opcode: WhoopCmd.setFfValue, payload: [0x01] + fieldName + fieldVal,
                                  profile: .gen5, allowDangerous: true)
    }

    public static func buildR22EnableSequence(startSeq: UInt8 = 1, omitContestedFlags: Bool = false) -> [[UInt8]] {
        let flags = omitContestedFlags
            ? gen5R22EnableFlags.filter { !gen5R22ContestedFlagNames.contains($0.0) }
            : gen5R22EnableFlags
        return flags.enumerated().compactMap { offset, pair in
            let seq = UInt8((Int(startSeq) + offset) & 0xFF)
            return try? cmdSetConfigGen5(seq: seq, name: pair.0, value: pair.1)
        }
    }
}
