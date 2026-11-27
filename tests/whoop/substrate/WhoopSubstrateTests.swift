import XCTest
@testable import FitnessCore

final class WhoopSubstrateTests: XCTestCase {
    func testAtomicCommitReplacesOneHzCleansOrphanRRBeatsDeduplicatesArchiveAndUpdatesSyncCursor() throws {
        let store = try WhoopStore.inMemory()

        // Batch 1: second 1795113155 with 3 RR beats + battery + backlog
        var v18First = [UInt8](repeating: 0, count: 112)
        v18First[0] = WhoopPacketType.historicalData
        v18First[1] = 18
        // counter = 100
        v18First[3] = 100
        // unix = 1795113155 (0x6B000083)
        let ts: UInt32 = 1_795_113_155
        v18First[7] = UInt8(ts & 0xFF)
        v18First[8] = UInt8((ts >> 8) & 0xFF)
        v18First[9] = UInt8((ts >> 16) & 0xFF)
        v18First[10] = UInt8((ts >> 24) & 0xFF)
        // subsec = 27197
        v18First[11] = UInt8(27197 & 0xFF)
        v18First[12] = UInt8((27197 >> 8) & 0xFF)
        v18First[14] = 60 // HR
        v18First[15] = 3  // 3 RR beats: 800, 820, 840
        for (i, rr) in [800, 820, 840].enumerated() {
            v18First[16 + 2 * i] = UInt8(rr & 0xFF)
            v18First[17 + 2 * i] = UInt8((rr >> 8) & 0xFF)
        }
        let sample1 = try XCTUnwrap(WhoopGen5Decoder.decodeV18(v18First))

        let batch1 = WhoopSyncBatch(
            gen5Samples: [sample1],
            batteryRows: [WhoopBatteryRow(ts: Int(ts), batteryPct: 81.5, charging: false, wristOn: true, millivolts: 4010, chargeUnits: nil, source: "band_event")],
            backlogRows: [WhoopBacklogRow(ts: Int(ts), written: 1200, used: 40, capacity: 131072, trimPage: 1198, wrapCount: 2, freeRecords: 1900000, deviceFamily: "gen5")],
            trimTokenHex: "0102030405060708",
            capturedAtMs: 1_795_113_200_000)
        try store.commitSyncBatch(batch1)

        XCTAssertEqual(try store.count("decoded_onehz"), 1)
        XCTAssertEqual(try store.count("decoded_rr"), 3)
        XCTAssertEqual(try store.cursorValue("strap_trim"), "0102030405060708")
        XCTAssertEqual(try store.cursorValue("rec_ts_hw"), "1795113155")

        // Batch 2: re-delivers SAME second 1795113155 with only 2 RR beats (839, 876) and HR = 0 (off-skin -> NULL in DB), plus duplicate raw v26 archive
        var v18Second = v18First
        v18Second[3] = 101 // newer counter
        v18Second[14] = 0  // HR = 0 -> stored as NULL!
        v18Second[15] = 2  // 2 RR beats -> old beat_index = 2 MUST be deleted!
        for (i, rr) in [839, 876].enumerated() {
            v18Second[16 + 2 * i] = UInt8(rr & 0xFF)
            v18Second[17 + 2 * i] = UInt8((rr >> 8) & 0xFF)
        }
        let sample2 = try XCTUnwrap(WhoopGen5Decoder.decodeV18(v18Second))
        let rawV26 = Data([0x2F, 0x1A, 0x80, 0x01, 0x02, 0x03, 0x04])
        let archive = WhoopRawArchiveRow(counter: 102, packetType: 0x2F, recTs: Int(ts), capturedAtMs: 1_795_113_210_000, reason: "undecodable_rec_v26", frame: rawV26)

        let batch2 = WhoopSyncBatch(
            gen5Samples: [sample2],
            archives: [archive, archive], // duplicate SHA-1 in same batch -> 1 stored
            liveCoverageSpans: [WhoopLiveCoverageRow(startTs: Int(ts), endTs: Int(ts) + 60, steps: 42, day: "2026-11-20", source: "band")],
            trimTokenHex: "a0a700000a000000",
            capturedAtMs: 1_795_113_210_000)
        try store.commitSyncBatch(batch2)

        XCTAssertEqual(try store.count("decoded_onehz"), 1)
        let oneHzRow = try XCTUnwrap(try store.db.query("SELECT hr, counter FROM decoded_onehz WHERE rec_ts = ?", [.int(Int64(ts))]).first)
        XCTAssertNil(oneHzRow.optionalInt("hr"), "HR = 0 must persist as SQL NULL, never 0")
        XCTAssertEqual(oneHzRow.int("counter"), 101)

        // Verify orphan beat_index = 2 was atomically deleted and beat_ts_ms matches oracle [1795113154953, 1795113155829]
        let rrRows = try store.db.query("SELECT beat_index, rr_ms, beat_ts_ms FROM decoded_rr WHERE rec_ts = ? ORDER BY beat_index", [.int(Int64(ts))])
        XCTAssertEqual(rrRows.map { $0.int("beat_index") }, [0, 1])
        XCTAssertEqual(rrRows.map { $0.int("rr_ms") }, [839, 876])
        XCTAssertEqual(rrRows.compactMap { $0.optionalInt64("beat_ts_ms") }, [1795113154953, 1795113155829])

        XCTAssertEqual(try store.count("raw_archive_frames"), 1, "SHA-1 unique constraint deduplicates raw archive")
        XCTAssertEqual(try store.count("live_coverage"), 1)
        XCTAssertEqual(try store.cursorValue("strap_trim"), "a0a700000a000000")
        XCTAssertEqual(try store.cursorValue("counter_hw"), "101")
    }

    func testOpensAndSummarizesRealOpenStrapExportDatabaseAndExportsCleanSnapshot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let exportDB = root.appendingPathComponent("docs/design/whoop_protocol/openstrap_export_1795700891234.db")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: exportDB.path), "openstrap_export DB not present")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("whoop-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileSvc = WhoopDatabaseFileService(location: AppDatabaseLocation(directory: tempDir))
        try fileSvc.importDatabase(from: exportDB)

        let store = try XCTUnwrap(try fileSvc.openLiveStore())
        let summary = try store.summary()

        XCTAssertEqual(summary.oneHzCount, 547_574)
        XCTAssertEqual(summary.rrCount, 328_371)
        XCTAssertEqual(summary.rawArchiveCount, 121_686)
        XCTAssertEqual(summary.liveCoverageCount, 126)
        XCTAssertEqual(summary.latestRecTs, 1_795_666_401)
        XCTAssertEqual(summary.strapTrimHex, "a0a700000a000000")

        let exportedURL = try fileSvc.export(from: store.db, today: date("2026-11-26"), to: tempDir)
        XCTAssertEqual(exportedURL.lastPathComponent, "whoop-2026-11-26.sqlite")
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
    }

    func testProvenanceTracksLiveAppSyncedRowsAndNonDestructivelyMergesOpenStrapHistoryWithoutOverwritingLiveRows() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("whoop-merge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileSvc = WhoopDatabaseFileService(location: AppDatabaseLocation(directory: tempDir))
        let liveStore = try fileSvc.openOrCreateLiveStore()

        // 1. Sync 2 live seconds (1795750966 with HR 72, 1795750967 with HR 74) directly in FitnessApp
        func makeV18(ts: UInt32, counter: UInt8, hr: UInt8, rr: Int) throws -> WhoopGen5HistorySample {
            var b = [UInt8](repeating: 0, count: 112)
            b[0] = WhoopPacketType.historicalData
            b[1] = 18
            b[3] = counter
            b[7] = UInt8(ts & 0xFF); b[8] = UInt8((ts >> 8) & 0xFF)
            b[9] = UInt8((ts >> 16) & 0xFF); b[10] = UInt8((ts >> 24) & 0xFF)
            b[11] = 0x00; b[12] = 0x40
            b[14] = hr
            b[15] = 1
            b[16] = UInt8(rr & 0xFF); b[17] = UInt8((rr >> 8) & 0xFF)
            return try XCTUnwrap(WhoopGen5Decoder.decodeV18(b))
        }

        let live1 = try makeV18(ts: 1_795_750_966, counter: 201, hr: 72, rr: 830)
        let live2 = try makeV18(ts: 1_795_750_967, counter: 202, hr: 74, rr: 810)
        try liveStore.commitSyncBatch(WhoopSyncBatch(
            deviceID: "",
            gen5Samples: [live1, live2],
            trimTokenHex: "c1be00000a000000",
            capturedAtMs: 1_795_751_000_000))

        let preMergeSummary = try liveStore.summary()
        XCTAssertEqual(preMergeSummary.oneHzCount, 2)
        XCTAssertEqual(preMergeSummary.appSyncedOneHzCount, 2)
        XCTAssertEqual(preMergeSummary.importedBaselineOneHzCount, 0)
        XCTAssertEqual(preMergeSummary.lastAppSyncAtSec, 1_795_751_000)

        // 2. Build an external historical DB with older second 1795100000 (HR 58) + overlapping second 1795750966 (stale HR 60)
        let extPath = tempDir.appendingPathComponent("openstrap-old.db")
        do {
            let extStore = try WhoopStore(try Database(path: extPath.path))
            let histOld = try makeV18(ts: 1_795_100_000, counter: 10, hr: 58, rr: 1020)
            let histOverlapStale = try makeV18(ts: 1_795_750_966, counter: 99, hr: 60, rr: 999)
            try extStore.commitSyncBatch(WhoopSyncBatch(
                deviceID: "",
                gen5Samples: [histOld, histOverlapStale],
                trimTokenHex: "0000000000000001",
                capturedAtMs: 1_795_100_010_000))
        }

        // 3. Non-destructively merge external history into liveStore
        let mergeRes = try fileSvc.mergeDatabase(from: extPath, into: liveStore, nowSec: 1_795_751_100)
        XCTAssertEqual(mergeRes.addedOneHzRows, 1, "Only the non-overlapping historical second is inserted")
        XCTAssertEqual(mergeRes.addedRrRows, 1)

        // Verify overlapping live second 1795750966 kept live HR 72 (not overwritten by stale 60!) and live strap_trim stayed intact
        let keptHr = try liveStore.db.query("SELECT hr FROM decoded_onehz WHERE rec_ts = 1795750966").first?.int("hr")
        XCTAssertEqual(keptHr, 72)

        let postSummary = try liveStore.summary()
        XCTAssertEqual(postSummary.oneHzCount, 3)
        XCTAssertEqual(postSummary.appSyncedOneHzCount, 2)
        XCTAssertEqual(postSummary.importedBaselineOneHzCount, 1)
        XCTAssertEqual(postSummary.importedBaselineMaxRecTs, 1_795_750_966)
        XCTAssertEqual(postSummary.strapTrimHex, "c1be00000a000000")
    }
}
