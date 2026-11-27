import XCTest
@testable import FitnessCore

final class WhoopLongevityAndStepsTests: XCTestCase {
    func testGen5StepCounterWraparoundActivityClassFilterAndSleepBoutCoherence() {
        // Build time-ordered Gen5 step samples:
        // 1) t=100 -> 65530 (walk=1)
        // 2) t=105 -> 6     (walk=1, u16 wrap delta = (6 - 65530) & 0xFFFF = 12 ticks)
        // 3) t=110 -> 26    (still/non-gait=0 -> 20 ticks REJECTED!)
        // 4) t=115 -> 46    (run=2 -> 20 ticks ACCEPTED!)
        // 5) t=200..201 -> asleep context=2 isolated 2-tick toss -> REJECTED!
        // 6) t=300..305 -> asleep context=2 coherent 5-sample 5s 10-tick bathroom walk -> ACCEPTED!
        let samples: [WhoopStepSample] = [
            WhoopStepSample(tsSec: 100, counter: 65530, activityClass: 1, sleepContext: .awake),
            WhoopStepSample(tsSec: 105, counter: 6,     activityClass: 1, sleepContext: .awake), // +12
            WhoopStepSample(tsSec: 110, counter: 26,    activityClass: 0, sleepContext: .awake), // +20 rejected (class 0)
            WhoopStepSample(tsSec: 115, counter: 46,    activityClass: 2, sleepContext: .awake), // +20 accepted (run)
            WhoopStepSample(tsSec: 200, counter: 48,    activityClass: 1, sleepContext: .asleepStage), // +2 toss
            WhoopStepSample(tsSec: 300, counter: 50,    activityClass: 1, sleepContext: .asleepStage), // bout start (+2)
            WhoopStepSample(tsSec: 301, counter: 52,    activityClass: 1, sleepContext: .asleepStage), // +2
            WhoopStepSample(tsSec: 302, counter: 54,    activityClass: 1, sleepContext: .asleepStage), // +2
            WhoopStepSample(tsSec: 303, counter: 56,    activityClass: 1, sleepContext: .asleepStage), // +2
            WhoopStepSample(tsSec: 304, counter: 58,    activityClass: 1, sleepContext: .asleepStage), // +2 (5 samples, 4s dur, 10 ticks >= 6)
        ]

        // Total valid ticks = 12 + 20 + 10 = 42 ticks.
        let stepsDefault = WhoopStepsEngine.countSteps(samples: samples, stepTicksPerStep: 1.0)
        XCTAssertEqual(stepsDefault.totalTicks, 42)
        XCTAssertEqual(stepsDefault.steps, 42)

        // With divisor 2.0 -> 21 steps.
        let stepsDiv2 = WhoopStepsEngine.countSteps(samples: samples, stepTicksPerStep: 2.0)
        XCTAssertEqual(stepsDiv2.steps, 21)
    }

    func testFitnessAgeNormalizesStrainAndComputesNesUthVitalityAndBodyAge() throws {
        // 7-day window: 6 days with RHR around 50 bpm, 4 days with 0-21 Strain = 12.6 => normalized 0-100 Effort = 60.0 (>= 30.0 active!)
        let days: [WhoopLongevityDayInput] = [
            WhoopLongevityDayInput(date: "2026-11-21", restingHr: 50, strain0To21: 12.6, sleepMinutes: 460, rmssdMs: 58, steps: 9500),
            WhoopLongevityDayInput(date: "2026-11-22", restingHr: 49, strain0To21: 12.6, sleepMinutes: 450, rmssdMs: 60, steps: 10200),
            WhoopLongevityDayInput(date: "2026-11-23", restingHr: 51, strain0To21: 5.0,  sleepMinutes: 455, rmssdMs: 56, steps: 8200),
            WhoopLongevityDayInput(date: "2026-11-24", restingHr: 50, strain0To21: 12.6, sleepMinutes: 465, rmssdMs: 62, steps: 9800),
            WhoopLongevityDayInput(date: "2026-11-25", restingHr: 50, strain0To21: 4.2,  sleepMinutes: 450, rmssdMs: 59, steps: 8800),
            WhoopLongevityDayInput(date: "2026-11-26", restingHr: 49, strain0To21: 12.6, sleepMinutes: 460, rmssdMs: 61, steps: 10500),
            WhoopLongevityDayInput(date: "2026-11-27", restingHr: nil, strain0To21: 3.0, sleepMinutes: nil, rmssdMs: nil, steps: 7500),
        ]

        // 4 active days -> f = 2.5; meanActiveEffort = 60.0 -> PAI = 2.5 * clamp(60/30, 0, 3) = 5.0!
        let nes = try XCTUnwrap(WhoopLongevityEngines.computeFitnessAge(
            days7: days, chronoAge: 30.0, sex: "male", waistCm: 78.0
        ))
        XCTAssertEqual(nes.estimator, .nes)
        XCTAssertEqual(nes.readiness, .ready) // 6 RHR days >= goodCoverageDays(6)
        XCTAssertEqual(nes.pai, 5.0, accuracy: 0.01)
        XCTAssertGreaterThan(nes.vo2MaxMlKgMin, 48.0)
        XCTAssertLessThan(nes.fitnessAge, 30.0) // RHR ~49.5 < 65 -> younger Fitness Age!

        // Without waistCm -> falls back to Uth et al. 2004 HR-ratio
        let uth = try XCTUnwrap(WhoopLongevityEngines.computeFitnessAge(
            days7: days, chronoAge: 30.0, sex: "male", waistCm: nil
        ))
        XCTAssertEqual(uth.estimator, .uth)
        XCTAssertGreaterThan(uth.vo2MaxMlKgMin, 55.0)

        // Vitality & Body Age (Gompertz mortality log-hazards)
        let vit = try XCTUnwrap(WhoopLongevityEngines.computeVitality(days7: days, chronoAge: 30.0))
        XCTAssertGreaterThanOrEqual(vit.factorsUsed, 5)
        XCTAssertLessThan(vit.bodyAge, 30.0)
        XCTAssertGreaterThan(vit.vitalityScore, 55.0)
    }

    func testAcsmTreadmillVo2CalculatorAndEditablePersistence() throws {
        let db = try Database.inMemory()
        let service = AcsmTreadmillVo2Service(db)

        // 10.8 km/h = 180 m/min, 2% grade (0.02):
        // VO2 = 0.2 * 180 + 0.9 * 180 * 0.02 + 3.5 = 36.0 + 3.24 + 3.5 = 42.74 mL/kg/min
        // %HRR = (158 - 50) / (190 - 50) = 108 / 140 = 0.77142857
        // Estimated VO2max = (42.74 - 3.5) / 0.77142857 + 3.5 = 54.3667 mL/kg/min
        let calc = AcsmTreadmillVo2Service.calculate(
            speedKmh: 10.8, gradePct: 2.0, steadyHr: 158, restingHr: 50, maxHr: 190
        )
        XCTAssertEqual(calc.vo2MlKgMin, 42.74, accuracy: 0.01)
        XCTAssertEqual(calc.estimatedVo2Max, 54.37, accuracy: 0.02)

        let day = try XCTUnwrap(ISODate("2026-11-27"))
        let id = try service.addLog(TreadmillVo2Draft(
            loggedOn: day, speedKmh: 10.8, gradePct: 2.0, durationMin: 20,
            steadyHr: 158, restingHr: 50, maxHr: 190, notes: "Zone 3 steady test"
        ))
        // Edit speed & steady HR in place without deleting
        try service.updateLog(id: id, TreadmillVo2Draft(
            loggedOn: day, speedKmh: 12.0, gradePct: 2.0, durationMin: 20,
            steadyHr: 165, restingHr: 50, maxHr: 190, notes: "Corrected belt calibration"
        ))
        let logs = try service.logs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].speedKmh, 12.0, accuracy: 1e-6)
        XCTAssertEqual(logs[0].notes, "Corrected belt calibration")
        XCTAssertGreaterThan(logs[0].estimatedVo2Max, 54.37)

        try service.deleteLog(id: id)
        XCTAssertTrue(try service.logs().isEmpty)
    }
}
