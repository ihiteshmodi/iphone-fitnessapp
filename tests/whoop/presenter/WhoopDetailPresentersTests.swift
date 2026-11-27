import XCTest
@testable import FitnessCore

final class WhoopDetailPresentersTests: XCTestCase {
    func testTrueWeeklyZoneMinutesCountsGenuineHeartRateZonesNotActiveMinutes() throws {
        let store = try WhoopStore.inMemory()
        let day = ISODate("2026-11-26")!
        let bounds = try XCTUnwrap(WhoopSubstrateGates.calendarDayBounds(for: day))

        // Insert 20 minutes (1,200 seconds) at 124 bpm (Zone 2) and 10 minutes (600 seconds) at 168 bpm (Zone 4),
        // plus 300 minutes of active_min in metric_series that MUST NOT inflate Zone 2!
        try store.db.execute("INSERT INTO metric_series (date, key, value) VALUES ('2026-11-26', 'active_min', 300)", [])
        for s in 0..<1200 {
            let ts = bounds.dayStartSec + 36_000 + Int64(s)
            try store.db.execute(
                "INSERT INTO decoded_onehz (device_id, ts_ms, rec_ts, counter, hr) VALUES ('', ?, ?, ?, 124)",
                [.int(ts * 1000), .int(ts), .int(Int64(s + 1))]
            )
        }
        for s in 0..<600 {
            let ts = bounds.dayStartSec + 40_200 + Int64(s)
            try store.db.execute(
                "INSERT INTO decoded_onehz (device_id, ts_ms, rec_ts, counter, hr) VALUES ('', ?, ?, ?, 168)",
                [.int(ts * 1000), .int(ts), .int(Int64(2000 + s))]
            )
        }

        let zones = WhoopTrainingZones(source: "manual", boundsBpm: [100, 115, 140, 160, 178], maxHrBpm: 190)
        let wk = try WhoopDetailPresenters.trueWeeklyZoneMinutes(whoopDb: store.db, fitnessDb: nil, endingOn: day, zones: zones)
        XCTAssertEqual(wk.zone2Minutes, 20)
        XCTAssertEqual(wk.zone4And5Minutes, 10)
    }

    func testSleepDetailBuildsHypnogramConfidenceRangesAgainstUsualAndFourOvernightSignals() throws {
        let store = try WhoopStore.inMemory()
        let day = ISODate("2026-11-26")!
        let onset: Int64 = 1_795_622_820
        let offset: Int64 = onset + 7200 // 2h test sleep slice
        try store.db.execute(
            "INSERT INTO day_result (day_id, algo_version, payload_json, window_json, computed_at) VALUES (?, 133, '{}', ?, ?)",
            [.text(day.string), .text("{\"onset_ms\":\(onset * 1000).0,\"offset_ms\":\(offset * 1000).0}"), .int(offset)]
        )
        try store.db.execute("INSERT INTO metric_series (date, key, value) VALUES ('2026-11-26', 'tst_min', 110)", [])
        try store.db.execute("INSERT INTO metric_series (date, key, value) VALUES ('2026-11-26', 'deep_min', 28)", [])
        try store.db.execute("INSERT INTO metric_series (date, key, value) VALUES ('2026-11-26', 'rem_min', 24)", [])
        try store.db.execute("INSERT INTO metric_series (date, key, value) VALUES ('2026-11-26', 'light_min', 58)", [])
        try store.db.execute("INSERT INTO metric_series (date, key, value) VALUES ('2026-11-26', 'efficiency', 92)", [])

        for i in stride(from: 0, to: 7200, by: 60) {
            let ts = onset + Int64(i)
            try store.db.execute(
                "INSERT INTO decoded_onehz (device_id, ts_ms, rec_ts, counter, hr, ax, ay, az, skin_temp_c) VALUES ('', ?, ?, ?, ?, 0.0, 0.1, 0.99, 35.4)",
                [.int(ts * 1000), .int(ts), .int(Int64(i + 1)), .int(Int64(52 + (i / 600) % 6))]
            )
            try store.db.execute(
                "INSERT INTO decoded_rr (device_id, ts_ms, rec_ts, beat_index, rr_ts_ms, rr_ms, beat_ts_ms) VALUES ('', ?, ?, 0, ?, ?, ?)",
                [.int(ts * 1000), .int(ts), .int(ts * 1000), .int(Int64(1080 + (i % 180))), .int(ts * 1000)]
            )
        }

        let detail = try WhoopDetailPresenters.buildSleepDetail(whoopDb: store.db, dayId: day.string, tempUnit: .celsius)
        XCTAssertFalse(detail.hypnogramBlocks.isEmpty)
        XCTAssertEqual(detail.stageRanges.count, 4) // Deep, REM, Light, Awake
        XCTAssertLessThan(detail.stageRanges[0].lowMinutes, detail.stageRanges[0].highMinutes)
        XCTAssertFalse(detail.hrSignal.isEmpty)
        XCTAssertFalse(detail.tempSignal.isEmpty)
    }
}
