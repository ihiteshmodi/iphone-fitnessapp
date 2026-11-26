import XCTest
@testable import FitnessCore

final class WhoopProtocolTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        let clean = hex.filter { !$0.isWhitespace }
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            out.append(UInt8(clean[idx..<next], radix: 16)!)
            idx = next
        }
        return out
    }

    private func hex(_ data: [UInt8]) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func putU16(_ buf: inout [UInt8], at offset: Int, _ val: UInt16) {
        buf[offset] = UInt8(val & 0xFF)
        buf[offset + 1] = UInt8((val >> 8) & 0xFF)
    }

    private func putI16(_ buf: inout [UInt8], at offset: Int, _ val: Int16) {
        putU16(&buf, at: offset, UInt16(bitPattern: val))
    }

    private func putU32(_ buf: inout [UInt8], at offset: Int, _ val: UInt32) {
        buf[offset] = UInt8(val & 0xFF)
        buf[offset + 1] = UInt8((val >> 8) & 0xFF)
        buf[offset + 2] = UInt8((val >> 16) & 0xFF)
        buf[offset + 3] = UInt8((val >> 24) & 0xFF)
    }

    private func putF32(_ buf: inout [UInt8], at offset: Int, _ val: Float) {
        putU32(&buf, at: offset, val.bitPattern)
    }

    func testCanonicalGen5HelloFrameCRCsAndFragmentedReassemblyWithEmbeddedSOF() {
        let hello = WhoopCommands.gen5ClientHello(seq: 1)
        XCTAssertEqual(hex(hello), "aa0108000001e67123019101363e5c8d")

        // Header AA 01 08 00 00 01 -> CRC16-Modbus = 0x71E6 (LE: e6 71)
        XCTAssertEqual(WhoopCRC.crc16Modbus([0xAA, 0x01, 0x08, 0x00, 0x00, 0x01]), 0x71E6)

        // Payload containing embedded 0xAA bytes reassembled across 3-byte notification fragments after 2 noise bytes including 0xAA
        let payloadWithSOF: [UInt8] = [WhoopPacketType.event, 0x07, 0xAA, 0xAA, 0x12, 0x34]
        let validGen4 = WhoopFraming.buildFrame(payloadWithSOF, profile: .gen4)
        var stream: [UInt8] = [0xAA, 0xFF, 0xFF, 0x00] // corrupt header (bad length/CRC8) right before real frame
        stream += validGen4

        var acc = WhoopFrameAccumulator(profile: .gen4)
        var emitted: [WhoopFrame] = []
        var cursor = 0
        while cursor < stream.count {
            let end = min(cursor + 3, stream.count)
            emitted += acc.feed(Array(stream[cursor..<end]))
            cursor = end
        }

        XCTAssertEqual(emitted.count, 1)
        XCTAssertTrue(emitted[0].decodable)
        XCTAssertGreaterThanOrEqual(acc.resyncs, 1)
        XCTAssertEqual(Array(emitted[0].inner.prefix(6)), payloadWithSOF)
    }

    func testCommandBuildersEnforce65ByteR22EnableFixGen5TwoByteNACKAndDangerousCmdBlock() throws {
        // Fix #1: 65-byte body [0x01][name:32B][val:32B], '1' (0x31) for enable_r22_*, '2' (0x32) for disable_pip_r26_packets
        let seqFrames = WhoopCommands.buildR22EnableSequence(startSeq: 10)
        XCTAssertEqual(seqFrames.count, 8)

        for (idx, raw) in seqFrames.enumerated() {
            let parsed = try XCTUnwrap(WhoopFraming.parseFrame(raw, profile: .gen5))
            XCTAssertTrue(parsed.decodable)
            XCTAssertEqual(parsed.opcode, WhoopCmd.setFfValue)
            // inner = [0x23, seq, 120] + 65B body = 68B (already multiple of 4)
            XCTAssertEqual(parsed.body.count, 65)
            XCTAssertEqual(parsed.body[0], 0x01)
            let (expectedName, expectedChar) = WhoopCommands.gen5R22EnableFlags[idx]
            let nameSlice = Array(parsed.body[1..<33])
            let decodedName = String(bytes: nameSlice.prefix { $0 != 0 }, encoding: .ascii)
            XCTAssertEqual(decodedName, expectedName)
            XCTAssertEqual(parsed.body[33], expectedChar == "1" ? 0x31 : 0x32)
            XCTAssertTrue(parsed.body[34..<65].allSatisfy { $0 == 0 })
        }
        XCTAssertEqual(WhoopCommands.gen5R22EnableFlags.last?.0, "disable_pip_r26_packets")
        XCTAssertEqual(WhoopCommands.gen5R22EnableFlags.last?.1, "2")

        // Fix #4: Gen5 NACK is [0x00, 0x00], Gen4 NACK is [0x00]
        let nack5 = try XCTUnwrap(WhoopFraming.parseFrame(WhoopCommands.buildHistoryResultFail(seq: 9, profile: .gen5), profile: .gen5))
        XCTAssertEqual(Array(nack5.inner), [0x23, 0x09, 0x17, 0x00, 0x00, 0x00, 0x00, 0x00])
        let nack4 = try XCTUnwrap(WhoopFraming.parseFrame(WhoopCommands.buildHistoryResultFail(seq: 9, profile: .gen4), profile: .gen4))
        XCTAssertEqual(Array(nack4.inner), [0x23, 0x09, 0x17, 0x00])

        // Gen5 HighFreqSync rejects interval <= 60 or duration >= 28800
        XCTAssertThrowsError(try WhoopCommands.enterHighFreqSync(seq: 5, intervalSeconds: 60, durationSeconds: 7200, profile: .gen5))
        XCTAssertThrowsError(try WhoopCommands.enterHighFreqSync(seq: 5, intervalSeconds: 900, durationSeconds: 28800, profile: .gen5))
        let validPrompt = try WhoopCommands.enterHighFreqSync(seq: 5, intervalSeconds: 61, durationSeconds: 7200, profile: .gen5)
        XCTAssertNotNil(WhoopFraming.parseFrame(validPrompt, profile: .gen5))

        // Dangerous commands blocked unless authorized
        XCTAssertTrue(WhoopCommands.isDangerousOpcode(WhoopCmd.forgetBonds))
        XCTAssertTrue(WhoopCommands.isDangerousOpcode(WhoopCmd.forceTrim))
        XCTAssertTrue(WhoopCommands.isDangerousOpcode(WhoopCmd.setClockMaverick))
        XCTAssertThrowsError(try WhoopCommands.guardedCommand(seq: 1, opcode: WhoopCmd.rebootStrap, payload: [0x00], profile: .gen5, allowDangerous: false))
    }

    func testGen4R24V12AndV25DecodersReadExactByteOffsetsAndRefuseV25PseudoGravity() throws {
        var v24 = [UInt8](repeating: 0, count: 92)
        v24[0] = WhoopPacketType.historicalData
        v24[1] = 24
        putU32(&v24, at: 3, 424242)
        putU32(&v24, at: 7, 1795000100)
        putU16(&v24, at: 11, 16384) // 0.5 s
        v24[17] = 62 // HR
        v24[18] = 3  // 3 RR slots (1 out-of-range 150ms should be filtered out)
        putI16(&v24, at: 19, 980)
        putI16(&v24, at: 21, 150) // < 200ms -> dropped!
        putI16(&v24, at: 23, 1012)
        putU16(&v24, at: 29, 1450) // ppgGreen
        putF32(&v24, at: 36, -0.25)
        putF32(&v24, at: 40, 0.50)
        putF32(&v24, at: 44, 0.82)
        putU16(&v24, at: 64, 21000) // spo2RedRaw
        putU16(&v24, at: 66, 21450) // spo2IrRaw
        putU16(&v24, at: 68, 3120)  // skinTempRaw
        putU16(&v24, at: 70, 88)    // ambientRaw

        let decoded24 = try XCTUnwrap(WhoopGen4Decoder.decodeR24(v24))
        XCTAssertEqual(decoded24.counter, 424242)
        XCTAssertEqual(decoded24.tsEpoch, 1795000100)
        XCTAssertEqual(decoded24.tsSubsec, 16384)
        XCTAssertEqual(decoded24.hr, 62)
        XCTAssertEqual(decoded24.rrIntervalsMs, [980, 1012])
        XCTAssertEqual(decoded24.rrCount, 2)
        XCTAssertEqual(decoded24.accelG, [-0.25, 0.5, 0.82])
        XCTAssertEqual(decoded24.spo2RedRaw, 21000)
        XCTAssertEqual(decoded24.spo2IrRaw, 21450)
        XCTAssertEqual(decoded24.skinTempRaw, 3120)
        XCTAssertEqual(decoded24.ambientRaw, 88)

        // 88-byte v12 record decodes via FirmwareAwareR24Decoder
        var v12 = Array(v24.prefix(88))
        v12[1] = 12
        let decoded12 = try XCTUnwrap(WhoopGen4Decoder.decodeFirmwareAwareR24(v12))
        XCTAssertEqual(decoded12.histVersion, 12)
        XCTAssertEqual(decoded12.ambientRaw, 88)

        // v25 (~24Hz PPG burst) returns hr=0 and empty accelG so caller archives to raw_archive_frames
        var v25 = [UInt8](repeating: 0x77, count: 76)
        v25[0] = WhoopPacketType.historicalData
        v25[1] = 25
        putU32(&v25, at: 3, 999)
        putU32(&v25, at: 7, 1795000200)
        let decoded25 = try XCTUnwrap(WhoopGen4Decoder.decodeR24(v25))
        XCTAssertEqual(decoded25.histVersion, 25)
        XCTAssertEqual(decoded25.hr, 0)
        XCTAssertTrue(decoded25.accelG.isEmpty)
    }

    func testGen5V18DecoderHandlesSignedSkinTempSentinelUnconditionalAuxTempsHighGDynAccelAndSleepState() throws {
        var v18 = [UInt8](repeating: 0, count: 112)
        v18[0] = WhoopPacketType.historicalData
        v18[1] = 18
        v18[2] = 0x80 // 25 Hz optical bit
        putU32(&v18, at: 3, 15667472)
        putU32(&v18, at: 7, 1795113155)
        putU16(&v18, at: 11, 27197)
        v18[14] = 58 // HR
        v18[15] = 2  // 2 RR beats
        putI16(&v18, at: 16, 839)
        putI16(&v18, at: 18, 876)
        v18[28] = 0x80 // hrRrValidThisSecond
        v18[29] = 58   // heartRateAlt
        putF32(&v18, at: 33, 11.5) // >8g high-impact motion preserved (0..16g)
        putF32(&v18, at: 37, 0.3288)
        putF32(&v18, at: 41, 0.8205)
        putF32(&v18, at: 45, 0.4510)
        putU16(&v18, at: 49, 31904)
        v18[51] = 162
        v18[55] = 1 // walk
        putI16(&v18, at: 61, 329)   // 32.9 C
        putI16(&v18, at: 63, 332)   // 33.2 C
        putI16(&v18, at: 65, -5000) // -50.00 C unavailable sentinel!
        v18[73] = 0x20              // sleepState = 2 (sleep)
        v18[100] = UInt8(bitPattern: -128)
        v18[101] = UInt8(bitPattern: -128)
        putF32(&v18, at: 105, -4.9963)

        let sample = try XCTUnwrap(WhoopGen5Decoder.decodeV18(v18))
        XCTAssertEqual(sample.ppgSampleRateHz, 25)
        XCTAssertEqual(sample.recordIndex, 15667472)
        XCTAssertEqual(sample.unix, 1795113155)
        XCTAssertEqual(sample.tsSubsec, 27197)
        XCTAssertEqual(sample.heartRate, 58)
        XCTAssertEqual(sample.rrIntervalsMs, [839, 876])
        XCTAssertEqual(sample.dynamicAccelerationG ?? 0, 11.5, accuracy: 1e-4)
        XCTAssertEqual(sample.stepMotionCounter, 31904)
        XCTAssertEqual(sample.stepCadence, 162)
        XCTAssertEqual(sample.activityClassKnown, 1)
        XCTAssertEqual(sample.tempAux1C, 32.9, accuracy: 1e-6)
        XCTAssertEqual(sample.tempAux2C, 33.2, accuracy: 1e-6)
        XCTAssertNil(sample.skinTempCOrNull, "-5000 sentinel must map to nil without dropping aux temps")
        XCTAssertEqual(sample.sleepState, .sleep)
        XCTAssertEqual(sample.signalQualityLogVariance ?? 0, -4.9963, accuracy: 1e-4)
    }

    func testEventBatteryChargingOffsetMetadataHistoryEndGen5HelloAndRealtimeStreams() throws {
        // Real Event 3 hex from openstrap_export_1795700891234.db
        let realEv3 = bytes("30050300fc40ff6a3d4a1400029b010000e80e00000000101105000901000000")
        let evOff = try XCTUnwrap(WhoopControlDecoder.parseEvent(realEv3, profile: .gen5))
        XCTAssertEqual(evOff.eventID, 3)
        XCTAssertEqual(evOff.batteryPct ?? 0, 41.1, accuracy: 1e-6)
        XCTAssertEqual(evOff.batteryMv, 3816)
        XCTAssertEqual(evOff.charging, false)

        // Flip body[9] (inner[21]) to 1 while leaving body[10] (inner[22]) = 0 -> charging MUST be true (Fix #2)
        var chargingEv3 = realEv3
        chargingEv3[21] = 1
        chargingEv3[22] = 0
        let evOn = try XCTUnwrap(WhoopControlDecoder.parseEvent(chargingEv3, profile: .gen5))
        XCTAssertEqual(evOn.charging, true)

        // Event 63 EXTENDED_BATTERY_INFORMATION Gen5 rev 3 -> charge_units at body[9:11]
        var ev63 = [UInt8](repeating: 0, count: 24)
        ev63[0] = WhoopPacketType.event
        putU16(&ev63, at: 2, 63)
        putU32(&ev63, at: 4, 1795113300)
        putU16(&ev63, at: 10, 12) // bodyLen = 12
        ev63[12] = 3              // rev 3 (Gen5)
        putU16(&ev63, at: 21, 512) // body[9:11] = inner[21:23]
        let parsed63 = try XCTUnwrap(WhoopControlDecoder.parseEvent(ev63, profile: .gen5))
        XCTAssertEqual(parsed63.chargeUnits, 512)

        // 0x28 Realtime HR caps rr_count at 4 so wearing byte at inner[18] is never read as a heartbeat
        var rtCorrupt = [UInt8](repeating: 0, count: 20)
        rtCorrupt[0] = WhoopPacketType.realtimeData
        putU32(&rtCorrupt, at: 2, 1795113400)
        rtCorrupt[8] = 72 // HR
        rtCorrupt[9] = 6  // corrupt rr_count > 4
        putU16(&rtCorrupt, at: 10, 820)
        rtCorrupt[18] = 1 // wearing = true
        let parsedRtCorrupt = try XCTUnwrap(WhoopLiveDecoder.parseRealtimeHr(rtCorrupt))
        XCTAssertEqual(parsedRtCorrupt.hrBpm, 72)
        XCTAssertTrue(parsedRtCorrupt.rrMs.isEmpty, "rr_count > 4 must emit zero RR beats rather than reading wearing byte")
        XCTAssertTrue(parsedRtCorrupt.wearing)

        // 0x31 METADATA HISTORY_END
        var metaEnd = [UInt8](repeating: 0, count: 21)
        metaEnd[0] = WhoopPacketType.metadata
        metaEnd[2] = 2 // HISTORY_END
        putU32(&metaEnd, at: 3, 1795113500)
        putU16(&metaEnd, at: 7, 1024)
        putU32(&metaEnd, at: 9, 47)
        let tokenBytes: [UInt8] = [0xA0, 0xA7, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00]
        for i in 0..<8 { metaEnd[13 + i] = tokenBytes[i] }
        let meta = try XCTUnwrap(WhoopControlDecoder.parseMetadata(metaEnd))
        XCTAssertEqual(meta.sub, .historyEnd)
        XCTAssertEqual(meta.expectedPacketCount, 47)
        XCTAssertEqual(meta.token, tokenBytes)
        XCTAssertEqual(meta.batchID, 10)
    }

    func testBeatTimesMsMatchesRealOpenStrapExportOracleAndMonotonizeBeatAxisClampsSeam() {
        // Exact oracle from openstrap_export_1795700891234.db:
        // rec_ts=1795113155, ts_subsec=27197, rr=[839, 876] -> [1795113154953, 1795113155829]
        let beats = WhoopBeatTiming.beatTimesMs(recTs: 1795113155, tsSubsec: 27197, rrMs: [839, 876])
        XCTAssertEqual(beats, [1795113154953, 1795113155829])

        // Out-of-range tsSubsec (>= 32768) returns nils
        XCTAssertEqual(WhoopBeatTiming.beatTimesMs(recTs: 1795113155, tsSubsec: 40000, rrMs: [839]), [nil])

        // Seam monotonization clamps backward anchor step without dropping beats
        let axis = WhoopBeatTiming.monotonizeBeatAxis([1000, 1850, 1820, 2600])
        XCTAssertEqual(axis, [1000, 1850, 1850, 2600])
    }
}
