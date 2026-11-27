import XCTest
@testable import FitnessCore

final class WhoopCoreAnalyticsTests: XCTestCase {
    func testSubstratePlausibilityGatesAndDstCalendarWindowing() {
        XCTAssertEqual(WhoopCoreConstants.algoVersion, 133)
        XCTAssertEqual(WhoopSubstrateGates.plausibleHrOrZero(nil), 0)
        XCTAssertEqual(WhoopSubstrateGates.plausibleHrOrZero(24), 0)
        XCTAssertEqual(WhoopSubstrateGates.plausibleHrOrZero(231), 0)
        XCTAssertEqual(WhoopSubstrateGates.plausibleHrOrZero(58), 58)

        XCTAssertNil(WhoopSubstrateGates.plausibleRrOrNil(240))
        XCTAssertNil(WhoopSubstrateGates.plausibleRrOrNil(2450))
        XCTAssertEqual(WhoopSubstrateGates.plausibleRrOrNil(1020), 1020)

        // Exact (0,0,0) must NEVER be valid (would fake zAngle = 0 deg -> 100% immobility).
        XCTAssertFalse(WhoopSubstrateGates.accelPlausible(ax: 0, ay: 0, az: 0))
        XCTAssertFalse(WhoopSubstrateGates.accelPlausible(ax: 3.0, ay: 3.0, az: 0.0)) // m^2 = 18 > 16
        XCTAssertTrue(WhoopSubstrateGates.accelPlausible(ax: 0.0, ay: 0.0, az: -1.0))

        // Skin temp sensor units stay separated by device family.
        XCTAssertEqual(WhoopSubstrateGates.consistentSkinTempUnit(family: "gen4", skinTempRaw: 18420, skinTempC: nil), 18420)
        XCTAssertEqual(WhoopSubstrateGates.consistentSkinTempUnit(family: "gen5", skinTempRaw: nil, skinTempC: 34.56), 3456)

        // Wake exclusion masks both morning sleep and tonightSleepOnsetSec.
        XCTAssertTrue(WhoopSubstrateGates.isAsleep(tsSec: 1_000, morningSleep: (900, 1_200), tonightSleepOnsetSec: 3_000))
        XCTAssertFalse(WhoopSubstrateGates.isAsleep(tsSec: 2_000, morningSleep: (900, 1_200), tonightSleepOnsetSec: 3_000))
        XCTAssertTrue(WhoopSubstrateGates.isAsleep(tsSec: 3_000, morningSleep: (900, 1_200), tonightSleepOnsetSec: 3_000))
    }

    func testRrCorrectionHeadlineRmssdJitterGatesAndNocturnalRhr() throws {
        // Generate 400 physiologically realistic RSA beats around 1000 ms (60 bpm, ~15 br/min -> smooth sinusoidal oscillation).
        var rrMs: [Double] = []
        var rrTsMs: [Int64] = []
        var tMs: Int64 = 1_795_700_000_000
        for i in 0..<400 {
            let clean = 1000.0 + 45.0 * sin(2.0 * .pi * Double(i) / 4.2)
            rrMs.append(clean)
            tMs += Int64(clean.rounded())
            rrTsMs.append(tMs)
        }
        // Inject 1 isolated extra-short artifact at beat 120 -> should be spline-interpolated, keeping timestamp.
        rrMs[120] = 260.0
        // Inject a 3-beat missed/artifact run at 220..222 -> must be dropped (never interpolated across run >= 2).
        rrMs[220] = 2150.0
        rrMs[221] = 2180.0
        rrMs[222] = 2120.0

        let corrected = WhoopHrvAndRhrEngine.correctRr(rrMs: rrMs, rrTsMs: rrTsMs)
        XCTAssertLessThan(corrected.artifactFraction, 0.05)
        // Beat 120 interpolated near ~1000 ms; 3-beat run dropped -> total kept beats = 400 - 3 = 397.
        XCTAssertEqual(corrected.nnMs.count, 397)

        // Headline RMSSD over a 15-minute window succeeds and clears ACF1 >= -0.35.
        let startSec: Int64 = 1_795_700_000
        let endSec: Int64 = startSec + 900
        let detail = WhoopHrvAndRhrEngine.sleepSessionRmssdDetail(rrMs: rrMs, rrTsMs: rrTsMs, startSec: startSec, endSec: endSec)
        XCTAssertNotNil(detail.rmssd)
        XCTAssertFalse(detail.overCounted)
        XCTAssertGreaterThan(try XCTUnwrap(detail.rmssd), 25.0)

        // Overcounted RR intervals (> 1.10x wall span) must be refused!
        let overTs = (0..<700).map { Int64(startSec * 1000 + $0 * 900) } // 630s span
        let overRr = [Double](repeating: 1150.0, count: 700) // sums to 805s -> 805/631 = 1.27 > 1.10
        let refusedOver = WhoopHrvAndRhrEngine.sleepSessionRmssdDetail(rrMs: overRr, rrTsMs: overTs, startSec: startSec, endSec: startSec + 631)
        XCTAssertTrue(refusedOver.overCounted)
        XCTAssertNil(refusedOver.rmssd)

        // Pure alternating white timing jitter (+40, -40, +40, -40 => ACF1 ~ -0.99 < -0.35 and Nyquist bin 32) must be refused!
        var jitterRr: [Double] = []
        var jitterTs: [Int64] = []
        var jt: Int64 = startSec * 1000
        for i in 0..<650 {
            let v = 1000.0 + ((i % 2 == 0) ? 40.0 : -40.0)
            jitterRr.append(v)
            jt += Int64(v)
            jitterTs.append(jt)
        }
        let refusedJitter = WhoopHrvAndRhrEngine.sleepSessionRmssdDetail(rrMs: jitterRr, rrTsMs: jitterTs, startSec: startSec, endSec: startSec + 650)
        XCTAssertNil(refusedJitter.rmssd)

        // Nocturnal RHR: abstains when TST < 3h (10,800s); finds lowest 30-min >=90%-covered trough when TST >= 3h.
        let shortTs = (0..<7200).map { Int64(1_000_000 + $0) }
        let shortHr = [Int](repeating: 52, count: 7200)
        XCTAssertNil(WhoopHrvAndRhrEngine.nocturnalRhr(sleepTsSec: shortTs, sleepHr: shortHr, tstSec: 7200))

        let fullTs = (0..<12_000).map { Int64(1_000_000 + $0) }
        var fullHr = [Int](repeating: 56, count: 12_000)
        for i in 4_000..<5_800 { fullHr[i] = 48 } // 30-min trough at 48 bpm
        let rhr = try XCTUnwrap(WhoopHrvAndRhrEngine.nocturnalRhr(sleepTsSec: fullTs, sleepHr: fullHr, tstSec: 11_400))
        XCTAssertEqual(rhr.low30Mean, 48.0, accuracy: 0.01)
    }

    func testGen5LieInTrimSleepStagingNapDetectionAndEditableSleepStore() throws {
        // Gen5 bandTrimmedOffsetSec trims >= 10 min wake tail when prior sleep >= 3h and tail coverage >= 95%.
        let start: Int64 = 1_795_700_000
        let sleepDur = 4 * 3600 // 4h asleep (state == 2)
        let lieInDur = 900      // 15m awake in bed (state == 0)
        let total = sleepDur + lieInDur
        var states = [Int?](repeating: 2, count: sleepDur) + [Int?](repeating: 0, count: lieInDur)
        let trim = WhoopSleepAndNapEngine.bandTrimmedOffsetSec(startSec: start, endSec: start + Int64(total), bandStates: states)
        XCTAssertEqual(trim.trimmedEndSec, start + Int64(sleepDur))
        XCTAssertEqual(trim.trimmedSec, lieInDur)

        // If STILL (state == 1) in tail exceeds 60s, do NOT trim.
        for i in sleepDur..<(sleepDur + 120) { states[i] = 1 }
        let noTrim = WhoopSleepAndNapEngine.bandTrimmedOffsetSec(startSec: start, endSec: start + Int64(total), bandStates: states)
        XCTAssertEqual(noTrim.trimmedEndSec, start + Int64(total))
        XCTAssertNil(noTrim.trimmedSec)

        // Editable sleep override & manual/review-gated naps in WhoopAnalyticsStore.
        let whoopDb = try Database(path: ":memory:")
        try WhoopSubstrateSchema.apply(to: whoopDb)
        let store = WhoopAnalyticsStore(whoopDb)

        try store.upsertSleepOverride(dayId: "2026-11-27", startTs: start, endTs: start + 27_000, note: "Read in bed first")
        try store.upsertSleepOverride(dayId: "2026-11-27", startTs: start + 900, endTs: start + 27_000, note: "Adjusted onset +15m")
        let ov = try XCTUnwrap(try store.sleepOverride(for: "2026-11-27"))
        XCTAssertEqual(ov.startTs, start + 900)
        XCTAssertEqual(ov.note, "Adjusted onset +15m")

        // Manual nap add, edit in place, and oversized (>3h) guard.
        try store.upsertNap(dayId: "2026-11-27", startTs: start + 50_000, endTs: start + 52_700, source: "manual")
        try store.updateNapSpan(dayId: "2026-11-27", oldStartTs: start + 50_000, newStartTs: start + 50_300, newEndTs: start + 53_000)
        let naps = try store.effectiveNaps(for: "2026-11-27")
        XCTAssertEqual(naps.count, 1)
        XCTAssertEqual(naps[0].durationSec, 2_700)
    }

    func testReadinessCompositeSelfExclusionTempIllnessAndExerciseProtectedStrain() throws {
        // Build 20 prior days strictly before 2026-11-27.
        var history: [WhoopDatedMetric] = []
        for d in 1...20 {
            let day = String(format: "2026-11-%02d", d)
            let wave = Double((d % 5) - 2)
            history.append(WhoopDatedMetric(date: day, key: "ln_rmssd", value: 4.10 + 0.08 * wave))
            history.append(WhoopDatedMetric(date: day, key: "rhr", value: 52.0 + 1.8 * wave))
            history.append(WhoopDatedMetric(date: day, key: "resp_rate", value: 14.5 + 0.3 * wave))
            history.append(WhoopDatedMetric(date: day, key: "readiness_z", value: 0.15 * wave))
        }
        // Also insert a poisoned entry ON 2026-11-27 to prove self-exclusion (`date < D`) ignores today!
        history.append(WhoopDatedMetric(date: "2026-11-27", key: "ln_rmssd", value: 99.0))

        let readiness = WhoopReadinessAndStrainEngine.readinessComposite(
            dayId: "2026-11-27",
            sleepSessionRmssd: exp(4.22), // higher HRV = good (+z)
            nocturnalRhr: 49.5,           // lower RHR = good (+z)
            respRateBrpm: 14.3,           // lower RR = good (+z)
            settledGen4TempAdc: nil,
            history: history
        )
        XCTAssertNotNil(readiness.headlineScore)
        XCTAssertGreaterThan(try XCTUnwrap(readiness.headlineScore), 65)

        // Z-cap: |Z_comp| > 5.0 must withhold headlineScore (null) as unstable_baseline.
        let saturated = WhoopReadinessAndStrainEngine.readinessComposite(
            dayId: "2026-11-27",
            sleepSessionRmssd: exp(6.8),
            nocturnalRhr: 26.0,
            respRateBrpm: 9.0,
            settledGen4TempAdc: nil,
            history: history
        )
        XCTAssertNil(saturated.headlineScore)
        XCTAssertEqual(saturated.refusalReason, "unstable_baseline")

        // tempIllnessFlag: 10 baseline nights around 3400, then 2 consecutive elevated nights (3520, 3530) -> elevated (or lutealConfound).
        var tempDays: [WhoopTempNightInput] = (1...10).map { d in
            WhoopTempNightInput(dayIndex: d, date: String(format: "2026-11-%02d", d),
                                tempUnit: 3400.0 + Double((d % 3) - 1) * 8.0, luteal: false)
        }
        tempDays.append(WhoopTempNightInput(dayIndex: 11, date: "2026-11-11", tempUnit: 3520.0, luteal: false))
        tempDays.append(WhoopTempNightInput(dayIndex: 12, date: "2026-11-12", tempUnit: 3530.0, luteal: false))
        let illness = WhoopReadinessAndStrainEngine.evaluateTempIllness(tempDays)
        XCTAssertEqual(illness.dropLast().last?.flag, .normal) // 1st night only -> normal (0.30 conf)
        XCTAssertEqual(illness.last?.flag, .elevated)          // 2nd consecutive night -> elevated (0.70 conf)

        // Exercise-protected Banister Net TRIMP & 0-21 Strain:
        // 45 min morning run at 162 bpm + 600 min quiet afternoon sitting BELOW Q must NEVER debit the morning workout!
        let priorQuiet = [0.12, 0.13, 0.11, 0.12, 0.13]
        let runOnlyWake = [Double](repeating: 162.0, count: 45)
        let runPlusQuietSitting = runOnlyWake + [Double](repeating: 54.0, count: 600)
        let strainRunOnly = try XCTUnwrap(WhoopReadinessAndStrainEngine.computeDailyStrain(
            wakeMinuteHr: runOnlyWake, rhr: 50.0, maxHr: 190.0, isFemale: false, priorQuietHrr: priorQuiet, sessionMaxStrain: nil
        ))
        let strainWithAfternoonSitting = try XCTUnwrap(WhoopReadinessAndStrainEngine.computeDailyStrain(
            wakeMinuteHr: runPlusQuietSitting, rhr: 50.0, maxHr: 190.0, isFemale: false, priorQuietHrr: priorQuiet, sessionMaxStrain: nil
        ))
        XCTAssertEqual(strainWithAfternoonSitting.strain, strainRunOnly.strain, accuracy: 0.001)
        XCTAssertGreaterThan(strainWithAfternoonSitting.strain, 10.0)
        XCTAssertLessThanOrEqual(strainWithAfternoonSitting.strain, 21.0)

        // Daily energy invariant: total == basal + active.
        let energy = try XCTUnwrap(WhoopReadinessAndStrainEngine.computeDailyEnergy(
            wakeMinuteHr: runPlusQuietSitting, coveredMinutes: 1440,
            ageYears: 28, isFemale: false, weightKg: 75.0, heightCm: 178.0,
            rhr: 50.0, maxHr: 190.0
        ))
        XCTAssertEqual(energy.totalKcal, energy.basalKcal + energy.activeKcal, accuracy: 0.001)
    }
}
