import XCTest
@testable import FitnessCore

final class WhoopCoachingEngineTests: XCTestCase {
    func testLayer1PrinciplesAndRedRecoveryContextOverride() {
        XCTAssertGreaterThanOrEqual(WhoopCoachingEngine.layer1Principles.count, 5)

        // Single Red day (28%) caused by late meal (2.1h < 3.0h) with moderate yesterday strain (9.5) -> keep normal strain!
        var input = WhoopCoachingInput(
            mode: .generalHealth,
            readinessScore: 28,
            consecutiveRedDays: 1,
            sleepHoursLastNight: 7.2,
            yesterdayStrain: 9.5,
            lastMealGapHours: 2.1,
            alcoholWithinCutoff: false
        )
        let singleRed = WhoopCoachingEngine.evaluate(input)
        XCTAssertTrue(singleRed.keepNormalStrainOverride)
        XCTAssertFalse(singleRed.deloadTriggered)

        // 3 consecutive Red days -> acute Rest / Deload banner fires!
        input.consecutiveRedDays = 3
        let tripleRed = WhoopCoachingEngine.evaluate(input)
        XCTAssertFalse(tripleRed.keepNormalStrainOverride)
        XCTAssertTrue(tripleRed.deloadTriggered)
    }

    func testDynamicSleepNeedNapCreditAndTargetBedtime() {
        let input = WhoopCoachingInput(
            mode: .generalHealth,
            dayLoadKind: .endurance,
            sleepDebtHours: 0.5,
            validNapMinutesToday: 30,
            targetWakeHm: "07:00"
        )
        let out = WhoopCoachingEngine.evaluate(input)
        // Base 8.0h + 0.5h debt - 0.5h valid nap = 8.0h => 07:00 - 8h = 23:00!
        XCTAssertEqual(out.dynamicSleepNeedHours, 8.0, accuracy: 0.01)
        XCTAssertEqual(out.targetBedtimeHm, "23:00")
    }

    func testModeAVo2MaxModeBHrvLongRunExemptionAndModeCReducingRhrOverrides() {
        // Mode A: Maximizing VO2 Max with Anaerobic Battery (60/30/10), 55m >85% HRmax, 450m total cardio (>420m ceiling), no 1-mile trial yet
        let modeA = WhoopCoachingEngine.evaluate(WhoopCoachingInput(
            mode: .maximizingVo2Max,
            vo2Limiter: .anaerobicBattery,
            oneMileTrialMaxHr: nil,
            weeklyZone4And5Min: 55,
            weeklyTotalCardioMin: 450
        ))
        XCTAssertEqual(modeA.intensitySplitTarget, WhoopIntensitySplit(easyPct: 60, moderateOrAnaerobicPct: 30, hardOrSprintPct: 10))
        XCTAssertTrue(modeA.vo2WeeklyHighIntensityMet)
        XCTAssertTrue(modeA.weeklyCardioCeilingExceeded)
        XCTAssertTrue(modeA.promptsOneMileCalibration)

        // 10K limiter classifier under (180 - age)
        XCTAssertEqual(WhoopCoachingEngine.classifyVo2Limiter(tenKMinutes: 64.0, fadesOnIntervals: false), .aerobicPower)
        XCTAssertEqual(WhoopCoachingEngine.classifyVo2Limiter(tenKMinutes: 54.0, fadesOnIntervals: true), .anaerobicBattery)
        XCTAssertEqual(WhoopCoachingEngine.classifyVo2Limiter(tenKMinutes: 52.0, fadesOnIntervals: false), .processingPower)

        // Mode B: Maximizing HRV suppresses Gray-Zone drift on the weekly 90-180m Zone 3-5 long run, whereas General Health flags it!
        let longSession = WhoopLoggedCardioSummary(kind: .longEndurance, durationMin: 120, avgHr: 152, longEnduranceExempt: true)
        let genHealthGray = WhoopCoachingEngine.evaluate(WhoopCoachingInput(
            mode: .generalHealth,
            recentCardioSessions: [longSession]
        ))
        XCTAssertEqual(genHealthGray.grayZoneSessionCount, 1)

        let modeB = WhoopCoachingEngine.evaluate(WhoopCoachingInput(
            mode: .maximizingHrv,
            recentCardioSessions: [longSession],
            daysSinceLongEndurance: 1,
            hrvDropPctVsBaseline: 42.0,
            consecutiveCardioRestDays: 3
        ))
        XCTAssertEqual(modeB.grayZoneSessionCount, 0) // Exempted!
        XCTAssertEqual(modeB.reboundStage, .day1StimulusConfirmed)
        XCTAssertTrue(modeB.plasmaVolumeDropWarning) // > 2 consecutive cardio-rest days

        // Mode C: Reducing RHR scales easy cardio by steps at 110-130 bpm, flags noon caffeine violation, and applies 3-week microcycle
        let modeCLowSteps = WhoopCoachingEngine.evaluate(WhoopCoachingInput(
            mode: .reducingRhr,
            caffeineCompliant: false,
            todaySteps: 3_800,
            trainingBlockWeek: 2
        ))
        XCTAssertEqual(modeCLowSteps.zone2FloorBpm, 110)
        XCTAssertEqual(modeCLowSteps.zone2CeilingBpm, 130)
        XCTAssertEqual(modeCLowSteps.stepAdjustedEasyCardioMin, 40)
        XCTAssertTrue(modeCLowSteps.strictCaffeineViolation)
        XCTAssertEqual(modeCLowSteps.microcycleVolumeMultiplier, 1.10, accuracy: 0.001)

        let modeCHighStepsWk3 = WhoopCoachingEngine.evaluate(WhoopCoachingInput(
            mode: .reducingRhr,
            caffeineCompliant: true,
            todaySteps: 11_200,
            trainingBlockWeek: 3
        ))
        XCTAssertEqual(modeCHighStepsWk3.stepAdjustedEasyCardioMin, 0)
        XCTAssertEqual(modeCHighStepsWk3.secondaryEasyDayBonusMin, 30)
        XCTAssertFalse(modeCHighStepsWk3.strictCaffeineViolation)
        XCTAssertEqual(modeCHighStepsWk3.microcycleVolumeMultiplier, 0.50, accuracy: 0.001)
        XCTAssertTrue(modeCHighStepsWk3.deloadTriggered)
    }
}
