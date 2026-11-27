import XCTest
@testable import FitnessCore

final class WhoopWorkoutAndHiitTests: XCTestCase {
    func testLiveWorkoutSessionSetTimestampCorrelationZoneThrottleAndEditableEndTs() throws {
        let fitnessDb = try Database.inMemory()
        let service = WorkoutSessionService(fitnessDb: fitnessDb)
        let zones = WhoopTrainingZones(source: "manual", boundsBpm: [110, 130, 150, 170, 185], maxHrBpm: 195)
        let day = try XCTUnwrap(ISODate("2026-11-27"))

        // Start session -> emits 0x03 realtime HR ON
        let started = try service.startSession(id: "sess-1", performedOn: day, kind: .lifting, sport: "Strength", startTs: 1_000, profile: .gen5)
        let startFrame = try XCTUnwrap(WhoopFraming.parseFrame(started.toggleHrFrame, profile: .gen5))
        XCTAssertEqual(startFrame.opcode, WhoopCmd.toggleRealtimeHr)
        XCTAssertEqual(startFrame.body.first, 0x01)

        // Log 2 sets of Bench Press stamped at t=1200 and t=1400
        let logger = LogSets(fitnessDb)
        _ = try logger.logSets(
            .named("Barbell Bench Press", muscle: "Chest"),
            on: day,
            sets: [
                SetEntry(weightKg: 80, reps: 8, loggedAtTs: 1_200),
                SetEntry(weightKg: 80, reps: 8, loggedAtTs: 1_400),
            ],
            sessionId: "sess-1"
        )

        // Build synthetic 1 Hz HR stream: 1000..3600 active lifting (115..158 bpm), 3601..7000 forgot-to-stop sitting (62 bpm)
        var hrSamples: [(tsSec: Int64, bpm: Int)] = []
        for t in 1_000...7_000 {
            let bpm: Int
            if t >= 1_170 && t <= 1_460 {
                bpm = 154 // During Bench Press window
            } else if t <= 3_600 {
                bpm = 124 // Zone 1-2 between exercises
            } else {
                bpm = 62  // Forgot to stop workout!
            }
            hrSamples.append((Int64(t), bpm))
        }

        // Finish late at t=7000 -> emits 0x03 realtime HR OFF
        let finishedLate = try service.finishSession(id: "sess-1", endTs: 7_000, hrSamples: hrSamples, zones: zones, rhr: 50, isFemale: false, profile: .gen5)
        let stopFrame = try XCTUnwrap(WhoopFraming.parseFrame(finishedLate.toggleHrFrame, profile: .gen5))
        XCTAssertEqual(stopFrame.opcode, WhoopCmd.toggleRealtimeHr)
        XCTAssertEqual(stopFrame.body.first, 0x00)
        XCTAssertLessThan(try XCTUnwrap(finishedLate.session.avgHr), 100) // dragged down by 3601..7000 sitting

        // Edit end_ts in place back to 3600 -> recomputes avgHr & zone seconds strictly over 1000..3600!
        let corrected = try service.updateSession(
            id: "sess-1",
            performedOn: day,
            kind: .lifting,
            sport: "Push Hypertrophy",
            startTs: 1_000,
            endTs: 3_600,
            longEnduranceExempt: false,
            notes: "Trimmed post-gym commute",
            hrSamples: hrSamples,
            zones: zones,
            rhr: 50,
            isFemale: false
        )
        XCTAssertGreaterThan(try XCTUnwrap(corrected.avgHr), 120)
        XCTAssertEqual(corrected.sport, "Push Hypertrophy")

        // Per-exercise HR correlation from set timestamps
        let loggedSets = try logger.sets(on: day)
        let exerciseSummaries = WorkoutSessionService.correlateExerciseHeartRates(sets: loggedSets, hrSamples: hrSamples, zones: zones)
        XCTAssertEqual(exerciseSummaries.count, 1)
        XCTAssertEqual(exerciseSummaries[0].exerciseName, "Barbell Bench Press")
        XCTAssertEqual(exerciseSummaries[0].peakHr, 154)
        XCTAssertGreaterThan(exerciseSummaries[0].avgHr ?? 0, 150)

        // Throttled zone notification check (LiveContainer-safe, no ActivityKit)
        var throttle = WorkoutZoneNotificationThrottle(minIntervalSec: 30)
        XCTAssertNotNil(throttle.onBpmSample(tsSec: 1_000, bpm: 135, zones: zones)) // Zone 2 initial
        XCTAssertNil(throttle.onBpmSample(tsSec: 1_010, bpm: 155, zones: zones))    // Zone 3 within 30s throttle -> suppressed
        XCTAssertNotNil(throttle.onBpmSample(tsSec: 1_035, bpm: 155, zones: zones)) // Zone 3 after 35s -> fires!
    }

    func testDualModeHiitTimeAndHrThresholdHapticsWith10sHysteresis() throws {
        // 1) HR-Threshold mode on Gen5 (`0x13` runHapticPatternMaverick)
        let hrPreset = HiitPreset(id: "hr-1", name: "VO2 Peak/Recover", mode: .hrThreshold,
                                  workSec: 60, restSec: 60, rounds: 2, highBpm: 172, lowBpm: 130)
        var engine = DualModeHiitEngine(preset: hrPreset, profile: .gen5, startSec: 1_000)
        XCTAssertEqual(engine.phase, .workOrPushUpper)

        // Reaching 173 bpm at t=1040 -> emits Gen5 0x13 buzz and switches to recovery!
        let hitHigh = engine.ingestHeartRate(tsSec: 1_040, bpm: 173)
        XCTAssertEqual(hitHigh.count, 1)
        let buzz1 = try XCTUnwrap(WhoopFraming.parseFrame(hitHigh[0], profile: .gen5))
        XCTAssertEqual(buzz1.opcode, WhoopCmd.runHapticPatternMaverick) // 0x13
        XCTAssertEqual(engine.phase, .restOrRecoverLower)

        // Rapid artifact drop to 128 bpm only 4 seconds later (t=1044 < 10s hysteresis) -> MUST NOT buzz!
        let suppressed = engine.ingestHeartRate(tsSec: 1_044, bpm: 128)
        XCTAssertTrue(suppressed.isEmpty)
        XCTAssertEqual(engine.phase, .restOrRecoverLower)

        // Sustained drop <= 130 bpm at t=1095 (>= 10s after 1040) -> emits buzz & starts Round 2!
        let recovered = engine.ingestHeartRate(tsSec: 1_095, bpm: 129)
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(engine.currentRound, 2)
        XCTAssertEqual(engine.phase, .workOrPushUpper)

        // 2) Time-Interval mode on Gen4 (`0x4F` runHapticsPattern)
        let timePreset = HiitPreset(id: "t-1", name: "30/30", mode: .time, workSec: 30, restSec: 30, rounds: 1)
        var timeEngine = DualModeHiitEngine(preset: timePreset, profile: .gen4, startSec: 2_000)
        let workDone = timeEngine.tick(nowSec: 2_030)
        XCTAssertEqual(workDone.count, 1)
        let gen4Buzz = try XCTUnwrap(WhoopFraming.parseFrame(workDone[0], profile: .gen4))
        XCTAssertEqual(gen4Buzz.opcode, WhoopCmd.runHapticsPattern) // 0x4F
    }

    func testAutoWorkoutDetectorPhase2CardiacOnsetBypassSavedOverlapAndEditableAccept() throws {
        // Stationary-wrist bike workout:
        // t = 0..299: baseline pre-workout HR = 85 bpm, low wrist motion (0.04g)
        // t = 300..1600 (21.6 min): elevated HR = 152 bpm (>= floor), wrist motion still low (0.05g < 0.15g),
        //   BUT 3-min onset rise = 152 - 85 = +67 bpm >= +25 bpm -> MUST BE DETECTED!
        // t = 2500..3500: elevated HR = 155 bpm overlapping a SavedWorkoutSpan(2400..3600) -> MUST BE SUPPRESSED!
        var ts: [Int64] = []
        var hr: [Int] = []
        var motion: [Double?] = []
        for t in 0...3_700 {
            ts.append(Int64(10_000 + t))
            if t < 300 {
                hr.append(85)
                motion.append(0.04)
            } else if t <= 1_600 {
                hr.append(152)
                motion.append(0.05) // stationary handlebars!
            } else if t >= 2_500 && t <= 3_500 {
                hr.append(155)
                motion.append(0.25)
            } else {
                hr.append(78)
                motion.append(0.03)
            }
        }

        let detected = WhoopAutoWorkoutDetector.detect(
            dayId: "2026-11-27",
            tsSec: ts,
            hr: hr,
            motionIntensityG: motion,
            rhr: 52,
            maxHr: 190,
            savedSpans: [WhoopSavedWorkoutSpan(startSec: 12_400, endSec: 13_600)]
        )
        XCTAssertEqual(detected.count, 1)
        XCTAssertEqual(detected[0].startSec, 10_300)
        XCTAssertEqual(detected[0].endSec, 11_600)

        // Queue into WhoopAnalyticsStore and accept with edited sport & endTs into fitnessDb!
        let whoopDb = try Database(path: ":memory:")
        try WhoopSubstrateSchema.apply(to: whoopDb)
        let fitnessDb = try Database.inMemory()
        let analyticsStore = WhoopAnalyticsStore(whoopDb)
        let sessionService = WorkoutSessionService(fitnessDb: fitnessDb)

        try WhoopAutoWorkoutDetector.queueProposals(detected, into: analyticsStore, nowSec: 20_000)
        let pending = try analyticsStore.activityProposals(status: "pending")
        XCTAssertEqual(pending.count, 1)

        let created = try sessionService.acceptWorkoutProposal(
            proposalId: pending[0].id,
            analyticsStore: analyticsStore,
            editedStartTs: 10_300,
            editedEndTs: 11_500,
            kind: .intervals,
            sport: "Indoor Cycling",
            notes: "Accepted & trimmed cooldown"
        )
        XCTAssertEqual(created.sport, "Indoor Cycling")
        XCTAssertEqual(created.endTs, 11_500)
        XCTAssertEqual(try analyticsStore.activityProposals(status: "accepted").count, 1)
    }
}
