import XCTest
@testable import FitnessCore

final class WhoopDiagnosticTests: XCTestCase {
    func testHandshakeLiveHrRollingCrcBurstStatsAndTrimAckVerdictsAreCaptured() throws {
        let store = try WhoopStore.inMemory()
        var coord = WhoopSessionCoordinator(profile: .gen5, deviceID: "mav-diag-1")
        let nowSec = 1_795_750_000
        let nowMs = Int64(nowSec) * 1000
        _ = coord.onLinkReady()

        // 1. 0x91 Maverick GET_HELLO: rev=1, bat=845 (84.5%), chg=1, serial="MAV9988", opt=20 (<38 -> Maverick), fw=50.32.2.0, sigproc=1.4.2
        var helloBody = [UInt8](repeating: 0, count: 104)
        helloBody[0] = 1
        helloBody[1] = UInt8(845 & 0xFF); helloBody[2] = UInt8((845 >> 8) & 0xFF)
        helloBody[5] = 1
        let strapClock = UInt32(nowSec)
        helloBody[6] = UInt8(strapClock & 0xFF)
        helloBody[7] = UInt8((strapClock >> 8) & 0xFF)
        helloBody[8] = UInt8((strapClock >> 16) & 0xFF)
        helloBody[9] = UInt8((strapClock >> 24) & 0xFF)
        let sn = Array("MAV9988".utf8)
        helloBody.replaceSubrange(14..<(14 + sn.count), with: sn)
        helloBody[87] = 20 // Maverick opticalDiscriminator < 38
        helloBody[91] = 50; helloBody[92] = 32; helloBody[93] = 2 // fw 50.32.2.0
        helloBody[98] = 1; helloBody[99] = 4; helloBody[100] = 2  // sigproc 1.4.2
        helloBody[102] = 1 // wristOn
        let helloFrame = WhoopFraming.buildFrame(
            [WhoopPacketType.commandResponse, 0x01, WhoopCmd.getHello, 0xA0, 0x01] + helloBody,
            profile: .gen5)
        _ = try coord.receiveRawDataFromStrap(helloFrame, store: store, nowMs: nowMs)

        XCTAssertEqual(coord.handshakeTelemetry.detectedGeneration, "Gen5 / MG (Maverick)")
        XCTAssertEqual(coord.handshakeTelemetry.firmwareVersion, "50.32.2.0")
        XCTAssertEqual(coord.handshakeTelemetry.sigprocVersion, "1.4.2")
        XCTAssertEqual(coord.handshakeTelemetry.serialNumber, "MAV9988")
        XCTAssertEqual(coord.handshakeTelemetry.batteryPct, 84.5)
        XCTAssertEqual(coord.handshakeTelemetry.charging, true)
        XCTAssertEqual(coord.handshakeTelemetry.wristOn, true)

        // 2. Live 0x28 packet: HR = 64 bpm, RR = [912, 948] ms, wearing = 1
        var rtInner = [UInt8](repeating: 0, count: 20)
        rtInner[0] = WhoopPacketType.realtimeData
        rtInner[2] = UInt8(strapClock & 0xFF)
        rtInner[3] = UInt8((strapClock >> 8) & 0xFF)
        rtInner[4] = UInt8((strapClock >> 16) & 0xFF)
        rtInner[5] = UInt8((strapClock >> 24) & 0xFF)
        rtInner[8] = 64 // HR
        rtInner[9] = 2  // 2 RR intervals
        rtInner[10] = UInt8(912 & 0xFF); rtInner[11] = UInt8((912 >> 8) & 0xFF)
        rtInner[12] = UInt8(948 & 0xFF); rtInner[13] = UInt8((948 >> 8) & 0xFF)
        rtInner[18] = 1
        let rtFrame = WhoopFraming.buildFrame(rtInner, profile: .gen5)
        _ = try coord.receiveRawDataFromStrap(rtFrame, store: store, nowMs: nowMs)

        XCTAssertEqual(coord.burstTelemetry.liveHrBpm, 64)
        XCTAssertEqual(coord.burstTelemetry.liveRrMs, [912, 948])

        // 3. Inject 1 corrupted CRC32 frame, then 1 valid v18 burst + HISTORY_END(expected=1)
        var badCrcFrame = rtFrame
        badCrcFrame[badCrcFrame.count - 1] ^= 0xFF // flip payload CRC32 byte while keeping header CRC16 valid!
        _ = try coord.receiveRawDataFromStrap(badCrcFrame, store: store, nowMs: nowMs)
        XCTAssertEqual(coord.burstTelemetry.rollingCrcErrorCount, 1)
        XCTAssertEqual(coord.burstTelemetry.payloadCrc32Errors, 1)

        let startFrame = WhoopFraming.buildFrame([WhoopPacketType.metadata, 0x01, WhoopMetaSubType.historyStart.rawValue], profile: .gen5)
        _ = try coord.receiveRawDataFromStrap(startFrame, store: store, nowMs: nowMs)

        var v18 = [UInt8](repeating: 0, count: 112)
        v18[0] = WhoopPacketType.historicalData
        v18[1] = 18
        v18[3] = 77
        let recTs = UInt32(nowSec - 10)
        v18[7] = UInt8(recTs & 0xFF); v18[8] = UInt8((recTs >> 8) & 0xFF)
        v18[9] = UInt8((recTs >> 16) & 0xFF); v18[10] = UInt8((recTs >> 24) & 0xFF)
        v18[14] = 61
        v18[15] = 1
        v18[16] = UInt8(980 & 0xFF); v18[17] = UInt8((980 >> 8) & 0xFF)
        _ = try coord.receiveRawDataFromStrap(WhoopFraming.buildFrame(v18, profile: .gen5), store: store, nowMs: nowMs)

        let token: [UInt8] = [0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]
        var endOk: [UInt8] = [WhoopPacketType.metadata, 0x02, WhoopMetaSubType.historyEnd.rawValue]
        endOk += [0, 0, 0, 0, 0, 0]
        endOk += [1, 0, 0, 0] // expected = 1
        endOk += token
        _ = try coord.receiveRawDataFromStrap(WhoopFraming.buildFrame(endOk, profile: .gen5), store: store, nowMs: nowMs)

        XCTAssertEqual(coord.burstTelemetry.lastExpectedPacketCount, 1)
        XCTAssertEqual(coord.burstTelemetry.lastActualPacketCount, 1)
        XCTAssertEqual(coord.burstTelemetry.lastAckVerdict, "send")
        XCTAssertEqual(coord.burstTelemetry.lastAckWasNack, false)
        XCTAssertEqual(coord.burstTelemetry.lastAckTokenHex, "0123456789abcdef")
        XCTAssertEqual(coord.burstTelemetry.ackOkCount, 1)

        // 4. Subsequent burst with packet loss (expected = 4, actual = 0) -> NACK
        _ = try coord.receiveRawDataFromStrap(startFrame, store: store, nowMs: nowMs)
        var endFail: [UInt8] = [WhoopPacketType.metadata, 0x02, WhoopMetaSubType.historyEnd.rawValue]
        endFail += [0, 0, 0, 0, 0, 0]
        endFail += [4, 0, 0, 0] // expected = 4
        endFail += token
        _ = try coord.receiveRawDataFromStrap(WhoopFraming.buildFrame(endFail, profile: .gen5), store: store, nowMs: nowMs)

        XCTAssertEqual(coord.burstTelemetry.lastExpectedPacketCount, 4)
        XCTAssertEqual(coord.burstTelemetry.lastActualPacketCount, 0)
        XCTAssertEqual(coord.burstTelemetry.lastAckVerdict, "blockedPacketCountMismatch")
        XCTAssertEqual(coord.burstTelemetry.lastAckWasNack, true)
        XCTAssertEqual(coord.burstTelemetry.nackCount, 1)
    }

    func testSqliteInspectorReturnsLatestFiveRowsAndExportsWalCheckpointedDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("whoop-diag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileSvc = WhoopDatabaseFileService(location: AppDatabaseLocation(directory: tempDir))
        let store = try fileSvc.openOrCreateLiveStore()

        var samples: [WhoopGen5HistorySample] = []
        let baseTs: UInt32 = 1_795_750_100
        for offset in 0..<7 {
            var v18 = [UInt8](repeating: 0, count: 112)
            v18[0] = WhoopPacketType.historicalData
            v18[1] = 18
            v18[3] = UInt8(10 + offset) // counter
            let ts = baseTs + UInt32(offset)
            v18[7] = UInt8(ts & 0xFF); v18[8] = UInt8((ts >> 8) & 0xFF)
            v18[9] = UInt8((ts >> 16) & 0xFF); v18[10] = UInt8((ts >> 24) & 0xFF)
            let subsec = UInt16(1000 + offset * 100)
            v18[11] = UInt8(subsec & 0xFF); v18[12] = UInt8((subsec >> 8) & 0xFF)
            v18[14] = UInt8(55 + offset) // HR
            v18[15] = 1
            let rr = 900 + offset * 10
            v18[16] = UInt8(rr & 0xFF); v18[17] = UInt8((rr >> 8) & 0xFF)
            // gravity X/Y/Z at offsets 37, 41, 45 (Float32 LE)
            let gx: Float = 0.12; let gy: Float = -0.34; let gz: Float = 0.91
            for (o, f) in [(37, gx), (41, gy), (45, gz)] {
                let bits = f.bitPattern
                v18[o] = UInt8(bits & 0xFF); v18[o + 1] = UInt8((bits >> 8) & 0xFF)
                v18[o + 2] = UInt8((bits >> 16) & 0xFF); v18[o + 3] = UInt8((bits >> 24) & 0xFF)
            }
            // skinTempRawCenti at offset 65..66 (Int16 LE = 3425 -> 34.25 C)
            let rawTemp: Int16 = 3425
            let rawBits = UInt16(bitPattern: rawTemp)
            v18[65] = UInt8(rawBits & 0xFF); v18[66] = UInt8((rawBits >> 8) & 0xFF)
            samples.append(try XCTUnwrap(WhoopGen5Decoder.decodeV18(v18)))
        }

        try store.commitSyncBatch(WhoopSyncBatch(
            deviceID: "mav-diag-1",
            gen5Samples: samples,
            trimTokenHex: "feedface01020304",
            capturedAtMs: 1_795_750_200_000))

        let snap = try store.inspect(limit: 5)
        XCTAssertEqual(snap.oneHzCount, 7)
        XCTAssertEqual(snap.rrCount, 7)
        XCTAssertTrue(snap.schemaTables.contains("decoded_onehz"))
        XCTAssertTrue(snap.schemaTables.contains("decoded_rr"))
        XCTAssertEqual(snap.strapTrimHex, "feedface01020304")

        XCTAssertEqual(snap.latestOneHzRows.count, 5)
        let newest = try XCTUnwrap(snap.latestOneHzRows.first)
        XCTAssertEqual(newest.tsMs, Int64(baseTs + 6) * 1000)
        XCTAssertEqual(newest.tsSubsec, 1600)
        XCTAssertEqual(newest.hr, 61)
        XCTAssertEqual(newest.skinTempRaw, 3425)
        XCTAssertEqual(try XCTUnwrap(newest.skinTempC), 34.25, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(newest.ax), 0.12, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(newest.ay), -0.34, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(newest.az), 0.91, accuracy: 0.01)

        XCTAssertEqual(snap.latestRrRows.count, 5)
        let newestRr = try XCTUnwrap(snap.latestRrRows.first)
        XCTAssertEqual(newestRr.rrMs, 960)
        XCTAssertNotNil(newestRr.beatTsMs)

        let exportDir = tempDir.appendingPathComponent("exports", isDirectory: true)
        let exportedURL = try fileSvc.exportCheckpointedSnapshot(from: store, timestampTag: "2026-11-27-100000", to: exportDir)
        XCTAssertEqual(exportedURL.lastPathComponent, "whoop-diagnostic-2026-11-27-100000.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))

        // Verify PRAGMA wal_checkpoint(TRUNCATE) truncated the -wal file to 0 bytes (or removed it)
        let walPath = fileSvc.databaseURL.path + "-wal"
        if FileManager.default.fileExists(atPath: walPath) {
            let attrs = try FileManager.default.attributesOfItem(atPath: walPath)
            XCTAssertEqual(attrs[.size] as? Int, 0, "PRAGMA wal_checkpoint(TRUNCATE) must truncate -wal to 0 bytes")
        }

        // Verify exported file opens cleanly on an independent read-only connection with all 7 rows intact
        let verifyDB = try Database(path: exportedURL.path, readOnly: true)
        let integrity = try verifyDB.query("PRAGMA integrity_check").first?.text("integrity_check")
        XCTAssertEqual(integrity, "ok")
        let exportedCount = try verifyDB.query("SELECT COUNT(*) AS c FROM decoded_onehz").first?.int("c")
        XCTAssertEqual(exportedCount, 7)
    }

    func testInterleavedNotificationsAcrossDataAndEventsCharacteristicsDoNotCorruptSplitMtuFrames() throws {
        let store = try WhoopStore.inMemory()
        var coord = WhoopSessionCoordinator(profile: .gen5)
        let nowSec = 1_795_750_500
        let nowMs = Int64(nowSec) * 1000
        _ = coord.onLinkReady()

        var v18 = [UInt8](repeating: 0, count: 112)
        v18[0] = WhoopPacketType.historicalData
        v18[1] = 18
        v18[3] = 5
        let recTs = UInt32(nowSec - 2)
        v18[7] = UInt8(recTs & 0xFF); v18[8] = UInt8((recTs >> 8) & 0xFF)
        v18[9] = UInt8((recTs >> 16) & 0xFF); v18[10] = UInt8((recTs >> 24) & 0xFF)
        v18[14] = 59
        let fullDataFrame = WhoopFraming.buildFrame(v18, profile: .gen5)
        let halfA = Array(fullDataFrame.prefix(40))
        let halfB = Array(fullDataFrame.dropFirst(40))

        var rtInner = [UInt8](repeating: 0, count: 20)
        rtInner[0] = WhoopPacketType.realtimeData
        rtInner[8] = 72
        rtInner[18] = 1
        let liveHrFrame = WhoopFraming.buildFrame(rtInner, profile: .gen5)

        // Feed first half of v18 on .data, then a complete 0x28 live HR on .events mid-frame, then second half of v18 on .data!
        _ = try coord.receiveRawDataFromStrap(halfA, channel: .data, store: store, nowMs: nowMs)
        let midOut = try coord.receiveRawDataFromStrap(liveHrFrame, channel: .events, store: store, nowMs: nowMs)
        XCTAssertEqual(midOut.liveHr?.hrBpm, 72)
        _ = try coord.receiveRawDataFromStrap(halfB, channel: .data, store: store, nowMs: nowMs)

        XCTAssertEqual(coord.burstTelemetry.rollingCrcErrorCount, 0)
        XCTAssertEqual(coord.burstTelemetry.currentBurstDataPackets, 1)
    }
}
