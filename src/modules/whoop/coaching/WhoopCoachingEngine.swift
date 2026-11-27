import Foundation

public struct WhoopCoachingPrinciple: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
}

public enum WhoopDayLoadKind: String, Codable, Equatable, Sendable {
    case rest
    case lifting
    case endurance
}

public enum WhoopCardioSessionKind: String, Codable, Equatable, Sendable {
    case easyCardio = "easy_cardio"
    case intervals = "intervals"
    case tempo = "tempo"
    case longEndurance = "long_endurance"
    case lifting = "lifting"
}

public struct WhoopLoggedCardioSummary: Equatable, Sendable {
    public let kind: WhoopCardioSessionKind
    public let durationMin: Double
    public let avgHr: Int?
    public let longEnduranceExempt: Bool

    public init(kind: WhoopCardioSessionKind, durationMin: Double, avgHr: Int?, longEnduranceExempt: Bool = false) {
        self.kind = kind
        self.durationMin = durationMin
        self.avgHr = avgHr
        self.longEnduranceExempt = longEnduranceExempt
    }
}

public struct WhoopIntensitySplit: Equatable, Sendable {
    public let easyPct: Int
    public let moderateOrAnaerobicPct: Int
    public let hardOrSprintPct: Int

    public init(easyPct: Int, moderateOrAnaerobicPct: Int, hardOrSprintPct: Int) {
        self.easyPct = easyPct
        self.moderateOrAnaerobicPct = moderateOrAnaerobicPct
        self.hardOrSprintPct = hardOrSprintPct
    }
}

public enum WhoopHrvReboundStage: String, Equatable, Sendable {
    case inactive = "inactive"
    case day1StimulusConfirmed = "day1_stimulus_confirmed"
    case day1UnderStimulated = "day1_under_stimulated"
    case day2EasyFlush = "day2_easy_flush"
    case day2TooEasyFlatStress = "day2_too_easy_flat_stress"
    case day3To4ReboundWindow = "day3_to_4_rebound_window"
}

public struct WhoopCoachingInput: Equatable, Sendable {
    public var mode: WhoopCoachingMode
    public var vo2Limiter: Vo2LimiterMode
    public var readinessScore: Int?
    public var consecutiveRedDays: Int
    public var sleepHoursLastNight: Double?
    public var yesterdayStrain: Double?
    public var lastMealGapHours: Double?
    public var alcoholWithinCutoff: Bool?
    public var caffeineCompliant: Bool?
    public var dayLoadKind: WhoopDayLoadKind
    public var sleepRestHours: Double
    public var sleepLiftingHours: Double
    public var sleepEnduranceHours: Double
    public var sleepDebtHours: Double
    public var validNapMinutesToday: Int
    public var targetWakeHm: String
    public var wakeDriftMinutes: Int?
    public var oneMileTrialMaxHr: Int?
    public var weeklyZone2Min: Double
    public var weeklyZone4And5Min: Double
    public var weeklyTotalCardioMin: Double
    public var priorWeekCardioMin: Double
    public var weeklyLiftingMin: Double
    public var sameDayCardioLiftingGapHours: Double?
    public var hardTrainingToSleepHours: Double?
    public var backToBackHardDays: Bool
    public var recentCardioSessions: [WhoopLoggedCardioSummary]
    public var daysSinceLongEndurance: Int?
    public var hrvDropPctVsBaseline: Double?
    public var day2StressCompletelyFlat: Bool
    public var consecutiveCardioRestDays: Int
    public var todaySteps: Int?
    public var trainingBlockWeek: Int
    public var scheduledDeloadWeeks: Int

    public init(
        mode: WhoopCoachingMode = .generalHealth,
        vo2Limiter: Vo2LimiterMode = .aerobicPower,
        readinessScore: Int? = nil,
        consecutiveRedDays: Int = 0,
        sleepHoursLastNight: Double? = nil,
        yesterdayStrain: Double? = nil,
        lastMealGapHours: Double? = nil,
        alcoholWithinCutoff: Bool? = nil,
        caffeineCompliant: Bool? = nil,
        dayLoadKind: WhoopDayLoadKind = .rest,
        sleepRestHours: Double = 7.0,
        sleepLiftingHours: Double = 7.5,
        sleepEnduranceHours: Double = 8.0,
        sleepDebtHours: Double = 0.0,
        validNapMinutesToday: Int = 0,
        targetWakeHm: String = "07:00",
        wakeDriftMinutes: Int? = nil,
        oneMileTrialMaxHr: Int? = nil,
        weeklyZone2Min: Double = 0,
        weeklyZone4And5Min: Double = 0,
        weeklyTotalCardioMin: Double = 0,
        priorWeekCardioMin: Double = 0,
        weeklyLiftingMin: Double = 0,
        sameDayCardioLiftingGapHours: Double? = nil,
        hardTrainingToSleepHours: Double? = nil,
        backToBackHardDays: Bool = false,
        recentCardioSessions: [WhoopLoggedCardioSummary] = [],
        daysSinceLongEndurance: Int? = nil,
        hrvDropPctVsBaseline: Double? = nil,
        day2StressCompletelyFlat: Bool = false,
        consecutiveCardioRestDays: Int = 0,
        todaySteps: Int? = nil,
        trainingBlockWeek: Int = 1,
        scheduledDeloadWeeks: Int = 5
    ) {
        self.mode = mode
        self.vo2Limiter = vo2Limiter
        self.readinessScore = readinessScore
        self.consecutiveRedDays = consecutiveRedDays
        self.sleepHoursLastNight = sleepHoursLastNight
        self.yesterdayStrain = yesterdayStrain
        self.lastMealGapHours = lastMealGapHours
        self.alcoholWithinCutoff = alcoholWithinCutoff
        self.caffeineCompliant = caffeineCompliant
        self.dayLoadKind = dayLoadKind
        self.sleepRestHours = sleepRestHours
        self.sleepLiftingHours = sleepLiftingHours
        self.sleepEnduranceHours = sleepEnduranceHours
        self.sleepDebtHours = sleepDebtHours
        self.validNapMinutesToday = validNapMinutesToday
        self.targetWakeHm = targetWakeHm
        self.wakeDriftMinutes = wakeDriftMinutes
        self.oneMileTrialMaxHr = oneMileTrialMaxHr
        self.weeklyZone2Min = weeklyZone2Min
        self.weeklyZone4And5Min = weeklyZone4And5Min
        self.weeklyTotalCardioMin = weeklyTotalCardioMin
        self.priorWeekCardioMin = priorWeekCardioMin
        self.weeklyLiftingMin = weeklyLiftingMin
        self.sameDayCardioLiftingGapHours = sameDayCardioLiftingGapHours
        self.hardTrainingToSleepHours = hardTrainingToSleepHours
        self.backToBackHardDays = backToBackHardDays
        self.recentCardioSessions = recentCardioSessions
        self.daysSinceLongEndurance = daysSinceLongEndurance
        self.hrvDropPctVsBaseline = hrvDropPctVsBaseline
        self.day2StressCompletelyFlat = day2StressCompletelyFlat
        self.consecutiveCardioRestDays = consecutiveCardioRestDays
        self.todaySteps = todaySteps
        self.trainingBlockWeek = max(1, trainingBlockWeek)
        self.scheduledDeloadWeeks = max(4, scheduledDeloadWeeks)
    }
}

public struct WhoopCoachingEvaluation: Equatable, Sendable {
    public let activeMode: WhoopCoachingMode
    public let zone2FloorBpm: Int
    public let zone2CeilingBpm: Int
    public let zone2WeeklyMinimumMet: Bool
    public let grayZoneSessionCount: Int
    public let intensitySplitTarget: WhoopIntensitySplit
    public let weeklyProgressionExceeded: Bool
    public let spacingViolation: Bool
    public let sameDayInterferenceWarning: Bool
    public let strengthBenchmarkProgressRatio: Double
    public let keepNormalStrainOverride: Bool
    public let deloadTriggered: Bool
    public let dynamicSleepNeedHours: Double
    public let targetBedtimeHm: String
    public let wakeConsistencyJetLagWarning: Bool
    public let hardTrainingTooLateWarning: Bool
    // Mode A (`Maximizing VO2 Max`)
    public let promptsOneMileCalibration: Bool
    public let vo2WeeklyHighIntensityMet: Bool
    public let weeklyCardioCeilingExceeded: Bool
    // Mode B (`Maximizing HRV`)
    public let reboundStage: WhoopHrvReboundStage
    public let plasmaVolumeDropWarning: Bool
    // Mode C (`Reducing RHR`)
    public let stepAdjustedEasyCardioMin: Int?
    public let secondaryEasyDayBonusMin: Int
    public let strictCaffeineViolation: Bool
    public let microcycleVolumeMultiplier: Double
    // Human-readable actionable coaching notes
    public let coachingNotes: [String]
}

public enum WhoopCoachingEngine {
    // MARK: - Layer 1: Static Non-Obsessive Daily Principles

    public static let layer1Principles: [WhoopCoachingPrinciple] = [
        WhoopCoachingPrinciple(
            id: "diurnal-stress",
            title: "Diurnal Stress Curve",
            detail: "Frontload intense physical, metabolic, and cognitive stress into the morning or early afternoon so cortisol and autonomic stress taper down before night."
        ),
        WhoopCoachingPrinciple(
            id: "modality-matching",
            title: "Cardio Modality ('Vehicle') Matching",
            detail: "Use low-impact modalities (cycling, brisk incline walk, swimming) on easy Zone 2 days; prefer running or rowing (~86% muscle recruitment) on Zone 4–5 days so the heart hits ceiling before local quad fatigue."
        ),
        WhoopCoachingPrinciple(
            id: "fueling-by-intensity",
            title: "Fueling by Intensity",
            detail: "Easy Zone 1–2: fasted is fine. Moderate: add sodium/electrolytes. Hard intervals/long runs: 30–60g fast carbs (low fat/fiber) pre-session + 30g carbs/hour past 60 min."
        ),
        WhoopCoachingPrinciple(
            id: "progression-ceiling",
            title: "+5% Weekly Progression Ceiling",
            detail: "Keep week-over-week cardio duration increases at or below +5% in standard blocks so connective tissue adapts alongside aerobic capacity."
        ),
        WhoopCoachingPrinciple(
            id: "strides-and-tempo",
            title: "Strides & Threshold Definitions",
            detail: "Strides: 6–8 × 20s fast bursts (30s walk recovery) after easy runs. Tempo/Threshold: 20–40 min at the fastest pace sustainable for ~1 hour."
        ),
        WhoopCoachingPrinciple(
            id: "pre-bed-protein",
            title: "Optional Slow Pre-Bed Protein",
            detail: "Around 40g slow-digesting protein before sleep is an optional recovery tool—never a mandatory pass/fail rule."
        ),
    ]

    public static func classifyVo2Limiter(tenKMinutes: Double, fadesOnIntervals: Bool) -> Vo2LimiterMode {
        if tenKMinutes > 60.0 { return .aerobicPower }
        if fadesOnIntervals { return .anaerobicBattery }
        return .processingPower
    }

    // MARK: - Layer 2 & Layer 3 Stateful Evaluation

    public static func evaluate(_ input: WhoopCoachingInput) -> WhoopCoachingEvaluation {
        var notes: [String] = []

        // 1. Zone 2 bounds (`110–140 bpm`, overridden to `110–130 bpm` in Reducing RHR)
        let z2Ceiling = (input.mode == .reducingRhr) ? 130 : 140
        let z2Bounds = (110, z2Ceiling)
        let z2Met = input.weeklyZone2Min >= 150.0

        // 2. Gray-Zone Drift check (exempting weekly 90–180m Zone 3–5 long run in Maximizing HRV mode)
        var grayCount = 0
        var exemptedHrvLongRunUsed = false
        for s in input.recentCardioSessions {
            guard s.kind == .easyCardio || s.kind == .longEndurance else { continue }
            guard let hr = s.avgHr, hr > z2Ceiling else { continue }
            if input.mode == .maximizingHrv && !exemptedHrvLongRunUsed
                && (s.kind == .longEndurance || s.longEnduranceExempt)
                && s.durationMin >= 90.0 && s.durationMin <= 180.0 {
                exemptedHrvLongRunUsed = true
                continue
            }
            grayCount += 1
        }
        if grayCount > 0 {
            notes.append("\(grayCount) easy session(s) drifted above \(z2Ceiling) bpm into the Gray Zone — slow down so easy days stay genuinely aerobic.")
        }

        // 3. Intensity Split Target (`80/20` default; overridden by Mode A VO2 limiter)
        let split: WhoopIntensitySplit
        if input.mode == .maximizingVo2Max {
            switch input.vo2Limiter {
            case .aerobicPower:
                split = WhoopIntensitySplit(easyPct: 80, moderateOrAnaerobicPct: 0, hardOrSprintPct: 20)
            case .anaerobicBattery:
                split = WhoopIntensitySplit(easyPct: 60, moderateOrAnaerobicPct: 30, hardOrSprintPct: 10)
            case .processingPower:
                split = WhoopIntensitySplit(easyPct: 75, moderateOrAnaerobicPct: 15, hardOrSprintPct: 10)
            }
        } else {
            split = WhoopIntensitySplit(easyPct: 80, moderateOrAnaerobicPct: 0, hardOrSprintPct: 20)
        }

        // 4. Mode C 3-Week Microcycle vs Standard 4–6 Week Deload
        let microMult: Double
        let scheduledDeloadNow: Bool
        if input.mode == .reducingRhr {
            let cyclePos = ((input.trainingBlockWeek - 1) % 3) + 1
            switch cyclePos {
            case 1:
                microMult = 1.00
                scheduledDeloadNow = false
            case 2:
                microMult = 1.10
                scheduledDeloadNow = false
            default:
                microMult = 0.50
                scheduledDeloadNow = true
                notes.append("Reducing RHR Week 3 microcycle deload: drop cardio volume -50% (Zone 2 at 110–130 bpm only).")
            }
        } else {
            microMult = 1.00
            scheduledDeloadNow = (input.trainingBlockWeek % input.scheduledDeloadWeeks == 0)
        }

        // 5. Weekly Progression Cap (`+5%` standard; `+10%` permitted in Mode C Week 2)
        let allowedGrowth = (input.mode == .reducingRhr && microMult > 1.0) ? 1.10 : 1.05
        let progressionExceeded = input.priorWeekCardioMin >= 60.0
            && input.weeklyTotalCardioMin > (allowedGrowth * input.priorWeekCardioMin + 0.5)

        // 6. Spacing & Strength Longevity Benchmark (`3.0 h/wk = 180 min`)
        let sameDayWarn = (input.sameDayCardioLiftingGapHours != nil && input.sameDayCardioLiftingGapHours! < 3.0)
        let hardLateWarn = (input.hardTrainingToSleepHours != nil && input.hardTrainingToSleepHours! < 2.0)
        let strengthRatio = min(2.0, max(0.0, input.weeklyLiftingMin / 180.0))

        // 7. Red Recovery Context Override & 3+ Consecutive Red Deload
        let baseSleepHours: Double
        switch input.dayLoadKind {
        case .rest: baseSleepHours = input.sleepRestHours
        case .lifting: baseSleepHours = input.sleepLiftingHours
        case .endurance: baseSleepHours = input.sleepEnduranceHours
        }

        let isRed = (input.readinessScore != nil && input.readinessScore! < 34)
        let acuteRedOverload = (input.consecutiveRedDays >= 3)
        let deloadTriggered = acuteRedOverload || scheduledDeloadNow

        var keepNormalStrain = false
        if isRed && !acuteRedOverload {
            let lateMealCause = (input.lastMealGapHours != nil && input.lastMealGapHours! < 3.0)
            let poorSleepCause = (input.sleepHoursLastNight != nil && input.sleepHoursLastNight! < (baseSleepHours - 0.75))
            let alcoholCause = (input.alcoholWithinCutoff == true)
            let notPhysicallyOverloaded = (input.yesterdayStrain ?? 0.0) < 14.0
            if (lateMealCause || poorSleepCause || alcoholCause) && notPhysicallyOverloaded {
                keepNormalStrain = true
                notes.append("Red Recovery Override: suppressed HRV/RHR aligns with sleep duration or <3h meal/alcohol timing rather than training overload — keep normal strain target.")
            }
        }
        if acuteRedOverload {
            notes.append("3+ consecutive Red recoveries: take a rest or deload day before resuming hard intervals.")
        }

        // 8. Dynamic Sleep Need & Target Bedtime
        let napCreditHours = Double(max(0, min(90, input.validNapMinutesToday))) / 60.0
        let dynamicNeed = min(10.5, max(6.0, baseSleepHours + max(0.0, input.sleepDebtHours) - napCreditHours))
        let bedtimeHm = subtractHours(fromHm: input.targetWakeHm, hours: dynamicNeed)
        let jetLagWarn = (input.wakeDriftMinutes != nil && abs(input.wakeDriftMinutes!) >= 120)

        // 9. Mode A (`Maximizing VO2 Max`) checks
        let promptMile = (input.mode == .maximizingVo2Max && input.oneMileTrialMaxHr == nil)
        let vo2HiMet = (input.mode == .maximizingVo2Max) ? (input.weeklyZone4And5Min >= 50.0) : false
        let ceilingExceeded = (input.mode == .maximizingVo2Max && input.weeklyTotalCardioMin > 420.0)
        if ceilingExceeded {
            notes.append("Maximizing VO2 Max 7h/week ceiling exceeded (\(Int(input.weeklyTotalCardioMin)) min) — cap aerobic volume to protect lean mass & hormones.")
        }

        // 10. Mode B (`Maximizing HRV`) 4-Day Rebound & Plasma Volume Guard
        var reboundStage: WhoopHrvReboundStage = .inactive
        var plasmaWarn = false
        if input.mode == .maximizingHrv {
            if let d = input.daysSinceLongEndurance {
                switch d {
                case 1:
                    if let drop = input.hrvDropPctVsBaseline, drop >= 30.0 {
                        reboundStage = .day1StimulusConfirmed
                    } else {
                        reboundStage = .day1UnderStimulated
                    }
                case 2:
                    reboundStage = input.day2StressCompletelyFlat ? .day2TooEasyFlatStress : .day2EasyFlush
                case 3, 4:
                    reboundStage = .day3To4ReboundWindow
                default:
                    reboundStage = .inactive
                }
            }
            if input.consecutiveCardioRestDays > 2 {
                plasmaWarn = true
                notes.append("Maximizing HRV: >2 consecutive cardio-rest days — add a light aerobic session by Day 3 to prevent 48–72h plasma volume loss.")
            }
        }

        // 11. Mode C (`Reducing RHR`) Step-Adjusted Easy Cardio & Strict Caffeine Check
        var stepCardioMin: Int?
        var secondaryBonus = 0
        var cafViolation = false
        if input.mode == .reducingRhr {
            if let steps = input.todaySteps {
                if steps < 5_000 {
                    stepCardioMin = 40
                } else if steps <= 10_000 {
                    stepCardioMin = 25
                } else {
                    stepCardioMin = 0
                    secondaryBonus = 30
                }
            }
            if input.caffeineCompliant == false {
                cafViolation = true
                notes.append("Reducing RHR: caffeine exceeded 100 mg or occurred after 12:00 PM — late adenosine blockade elevates evening HR and nocturnal RHR.")
            }
        }

        return WhoopCoachingEvaluation(
            activeMode: input.mode,
            zone2FloorBpm: 110,
            zone2CeilingBpm: z2Ceiling,
            zone2WeeklyMinimumMet: z2Met,
            grayZoneSessionCount: grayCount,
            intensitySplitTarget: split,
            weeklyProgressionExceeded: progressionExceeded,
            spacingViolation: input.backToBackHardDays,
            sameDayInterferenceWarning: sameDayWarn,
            strengthBenchmarkProgressRatio: strengthRatio,
            keepNormalStrainOverride: keepNormalStrain,
            deloadTriggered: deloadTriggered,
            dynamicSleepNeedHours: dynamicNeed,
            targetBedtimeHm: bedtimeHm,
            wakeConsistencyJetLagWarning: jetLagWarn,
            hardTrainingTooLateWarning: hardLateWarn,
            promptsOneMileCalibration: promptMile,
            vo2WeeklyHighIntensityMet: vo2HiMet,
            weeklyCardioCeilingExceeded: ceilingExceeded,
            reboundStage: reboundStage,
            plasmaVolumeDropWarning: plasmaWarn,
            stepAdjustedEasyCardioMin: stepCardioMin,
            secondaryEasyDayBonusMin: secondaryBonus,
            strictCaffeineViolation: cafViolation,
            microcycleVolumeMultiplier: microMult,
            coachingNotes: notes
        )
    }

    private static func subtractHours(fromHm wakeHm: String, hours: Double) -> String {
        let parts = wakeHm.split(separator: ":").compactMap { Int($0) }
        let wakeMinutes = (parts.count == 2) ? (parts[0] * 60 + parts[1]) : (7 * 60)
        let needMinutes = Int((hours * 60.0).rounded())
        var bedMinutes = (wakeMinutes - needMinutes) % 1440
        if bedMinutes < 0 { bedMinutes += 1440 }
        return String(format: "%02d:%02d", bedMinutes / 60, bedMinutes % 60)
    }
}
