import XCTest
@testable import FitnessCore

final class WhoopGpsVo2AndStepBreakdownTests: XCTestCase {
    func testAcsmSwitchoverBetweenWalkingAndRunningAndGpsOneKmSplitSubmaxVo2Max() {
        // 5.4 km/h (1.5 m/s = 90 m/min) walking at 10% grade -> VO2 = 0.1*90 + 1.8*90*0.10 + 3.5 = 9 + 16.2 + 3.5 = 28.7
        let walk = AcsmTreadmillVo2Service.calculate(speedKmh: 5.4, gradePct: 10.0)
        XCTAssertEqual(walk.vo2MlKgMin, 28.7, accuracy: 0.05)

        // 10.8 km/h (3.0 m/s = 180 m/min) running at 0% grade -> VO2 = 0.2*180 + 3.5 = 39.5
        let run = AcsmTreadmillVo2Service.calculate(speedKmh: 10.8, gradePct: 0.0)
        XCTAssertEqual(run.vo2MlKgMin, 39.5, accuracy: 0.05)

        // GPS 1-km split submaximal VO2max (Spec §5.3.2): 330s (>=300s), 1005m, +10m net alt (G = 0.00995), avgHr 146, RHR 50, HRmax 190
        let splits = [
            WhoopGpsSplit(meters: 1002, durationSec: 280, avgHrBpm: 162, startAltM: 100, endAltM: 102), // < 300s rejected by bout gate if standalone, or shorter duration
            WhoopGpsSplit(meters: 1005, durationSec: 330, avgHrBpm: 146, startAltM: 100, endAltM: 110),
        ]
        let gpsEst = WhoopOutdoorGpsVo2Engine.fromOneKmSplits(splits, restingHrBpm: 50, hrMaxBpm: 190)
        XCTAssertNotNil(gpsEst)
        XCTAssertGreaterThan(gpsEst?.vo2MaxMlKgMin ?? 0, 45.0)
        XCTAssertLessThanOrEqual(gpsEst?.confidence ?? 1.0, 0.60)
    }

    func testStepBreakdownByActivityClassAndHeartRateZones() throws {
        let store = try WhoopStore.inMemory()
        // Class 0 (non-gait arm motion: +10 ticks), Class 1 (walk at 118 bpm Z2: +20 ticks), Class 2 (run at 165 bpm Z4: +30 ticks)
        let rows: [(Int64, Int, Int, Int, Int)] = [
            (1000, 1, 72, 100, 0),
            (1005, 2, 75, 110, 0),
            (1010, 3, 118, 130, 1),
            (1020, 4, 165, 160, 2),
        ]
        for (ts, cnt, hr, steps, cls) in rows {
            try store.db.execute(
                "INSERT INTO decoded_onehz (device_id, ts_ms, rec_ts, counter, hr, step_count, activity_class) VALUES ('', ?, ?, ?, ?, ?, ?)",
                [.int(ts * 1000), .int(ts), .int(Int64(cnt)), .int(Int64(hr)), .int(Int64(steps)), .int(Int64(cls))]
            )
        }

        let zones = WhoopTrainingZones(source: "manual", boundsBpm: [100, 115, 135, 155, 175], maxHrBpm: 190)
        let bd = try WhoopStepsEngine.stepBreakdownFromDatabase(
            whoopDb: store.db, startSec: 990, endSec: 1030, zones: zones, stepTicksPerStep: 1.0, filterGaitOnly: true
        )
        XCTAssertEqual(bd.rejectedNonGaitTicks, 10)
        XCTAssertEqual(bd.walkSteps, 20)
        XCTAssertEqual(bd.runSteps, 30)
        XCTAssertEqual(bd.zoneSteps[2], 20) // 118 bpm in Zone 2 (115..135)
        XCTAssertEqual(bd.zoneSteps[4], 30) // 165 bpm in Zone 4 (155..175)
    }

    func testTimelineExercisePinsOverlayLoggedSetsOntoHeartRateCurve() {
        let sets: [LoggedSet] = [
            LoggedSet(id: 1, exerciseId: 10, exerciseName: "Squat", date: ISODate("2026-11-27")!, weightKg: 120, reps: 6, loggedAtTs: 1_030, sessionId: nil),
            LoggedSet(id: 2, exerciseId: 11, exerciseName: "RDLs", date: ISODate("2026-11-27")!, weightKg: 100, reps: 8, loggedAtTs: 1_090, sessionId: nil),
        ]
        let hr: [(tsSec: Int64, bpm: Int)] = [
            (1_000, 112), (1_030, 154), (1_060, 128), (1_090, 161), (1_120, 122),
        ]
        let pins = WorkoutSessionService.exerciseTimelinePins(sets: sets, hrSamples: hr, startTs: 1_000, endTs: 1_120)
        XCTAssertEqual(pins.count, 2)
        XCTAssertEqual(pins[0].exerciseName, "Squat")
        XCTAssertEqual(pins[0].bpmAtPin, 154)
        XCTAssertEqual(pins[1].exerciseName, "RDLs")
        XCTAssertEqual(pins[1].bpmAtPin, 161)
    }
}
