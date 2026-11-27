import Foundation

public enum WhoopHoopTone: String, Equatable, Sendable {
    case green
    case greenSoft
    case gold
    case amber
    case red
    case muted
}

public struct WhoopTriadHoopViewModel: Identifiable, Equatable, Sendable {
    public var id: String { title }
    public let title: String        // Strictly ordered: "Recovery", "Strain", "Sleep"
    public let progress: Double     // 0.0 ... 1.0
    public let ringLabel: String
    public let ringSubLabel: String
    public let footerText: String
    public let tone: WhoopHoopTone
}

public struct WhoopContributorRowViewModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let ringProgress: Double
    public let ringLabel: String
    public let badgeText: String
    public let tone: WhoopHoopTone
    public let sparkline: [Double]
}

public struct WhoopSleepBreakdownViewModel: Equatable, Sendable {
    public let scoredDayId: String
    public let totalSleepMinutes: Int
    public let deepMinutes: Int
    public let remMinutes: Int
    public let lightMinutes: Int
    public let wasoMinutes: Int
    public let efficiencyPct: Int
    public let awakenings: Int
    public let onsetSec: Int64?
    public let offsetSec: Int64?
    public let hasManualOverride: Bool
    public let targetBedtimeHm: String
    public let dynamicSleepNeedHours: Double
}

public struct WhoopLongevityViewModel: Equatable, Sendable {
    public let chronoAge: Double
    public let waistCm: Double?
    public let fitnessAge: WhoopFitnessAgeResult?
    public let vitality: WhoopVitalityResult?
    public let treadmillLogs: [TreadmillVo2Log]
}

public struct WhoopCoachingSeriesPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let ctl: Double
    public let atl: Double
}

public struct WhoopCoachingDashboardViewModel: Equatable, Sendable {
    public let evaluation: WhoopCoachingEvaluation
    public let weeklyLiftingHours: Double
    public let ctlAtlTsb: WhoopCtlAtlTsb?
    public let ctlSeries: [WhoopCoachingSeriesPoint]
}

public struct WhoopDashboardSnapshot: Equatable, Sendable {
    public let shownDay: ISODate
    public let scoredRecoveryDayId: String
    public let readinessScore: Int?
    public let readinessHeadline: String
    public let readinessDetail: String
    public let readinessPill: String
    public let readinessTone: WhoopHoopTone
    public let strain: Double
    public let steps: Int
    public let totalKcal: Int?
    public let activeKcal: Int?
    /// Strictly ordered: `["Recovery", "Strain", "Sleep"]`.
    public let triad: [WhoopTriadHoopViewModel]
    public let contributors: [WhoopContributorRowViewModel]
    public let sleep: WhoopSleepBreakdownViewModel
    public let illnessDay: WhoopTempIllnessDay?
    public let pendingNapProposals: [WhoopActivityProposal]
    public let pendingWorkoutProposals: [WhoopActivityProposal]
    public let effectiveNaps: [WhoopNapRecord]
    public let longevity: WhoopLongevityViewModel
    public let coaching: WhoopCoachingDashboardViewModel
    public let zones: WhoopTrainingZones
}

/// Pure Swift presenter combining `whoop.sqlite` (`metric_series`, `day_result`, `decoded_onehz`, `sleep_override`,
/// `sleep_nap`, `activity_suggestions`) with `fitness.sqlite` (`AppDefaultsStore`, `LastMealToSleepEvaluator`, `body_measurements`, `set_logs`).
public enum WhoopDashboardPresenter {
    public static func build(whoopDb: Database?, fitnessDb: Database, on day: ISODate, calendar: Calendar = .current) throws -> WhoopDashboardSnapshot {
        let defaults = try AppDefaultsStore(fitnessDb).load()
        let prefs = try LabSettings(fitnessDb).load()
        let ageYears: Double = prefs.birthDate.map { max(18.0, Double(day.days(since: $0)) / 365.25) } ?? 30.0
        let isFemale = (prefs.sex == .female)
        let waistCm = try WhoopLongevityEngines.latestWaistCm(from: fitnessDb)
        let treadmillLogs = try AcsmTreadmillVo2Service(fitnessDb).logs()

        // Weekly lifting minutes: explicit workout_sessions (`kind == .lifting`) or estimated 3.5 min per logged lifting set
        let weekStart = day.adding(days: -6)
        let liftingSessions = try WorkoutSessionService(fitnessDb: fitnessDb).sessions()
            .filter { $0.performedOn >= weekStart && $0.performedOn <= day && $0.kind == .lifting }
        let sessionLiftMin = liftingSessions.reduce(0.0) { acc, s in
            guard let end = s.endTs, end > s.startTs else { return acc }
            return acc + Double(end - s.startTs) / 60.0
        }
        let setCount7d = try fitnessDb.query(
            "SELECT COUNT(*) AS n FROM set_logs WHERE performed_on BETWEEN ? AND ?",
            [.text(weekStart.string), .text(day.string)]
        ).first?.int("n") ?? 0
        let weeklyLiftingMin = max(sessionLiftMin, Double(setCount7d) * 3.5)

        // Cardio sessions in last 7d & prior 7d
        let allCardio = try WorkoutSessionService(fitnessDb: fitnessDb).sessions()
            .filter { $0.kind != .lifting && $0.endTs != nil }
        let weekCardio = allCardio.filter { $0.performedOn >= weekStart && $0.performedOn <= day }
        let priorWeekStart = day.adding(days: -13)
        let priorWeekEnd = day.adding(days: -7)
        let priorCardioMin = allCardio
            .filter { $0.performedOn >= priorWeekStart && $0.performedOn <= priorWeekEnd }
            .reduce(0.0) { $0 + Double(max(0, ($1.endTs ?? $1.startTs) - $1.startTs)) / 60.0 }
        let weeklyCardioMin = weekCardio.reduce(0.0) { $0 + Double(max(0, ($1.endTs ?? $1.startTs) - $1.startTs)) / 60.0 }
        let weeklyZ2MinFromSessions = weekCardio.reduce(0.0) { $0 + Double($1.zoneSeconds[2]) / 60.0 }
        let weeklyZ45MinFromSessions = weekCardio.reduce(0.0) { $0 + Double($1.zoneSeconds[4] + $1.zoneSeconds[5]) / 60.0 }

        guard let whoopDb else {
            let zones = WhoopReadinessAndStrainEngine.trainingZones(
                ageYears: ageYears, manualBounds: defaults.manualHrZoneBounds, oneMileMaxHr: defaults.oneMileTrialMaxHr
            )
            let eval = WhoopCoachingEngine.evaluate(WhoopCoachingInput(
                mode: defaults.whoopCoachingMode,
                vo2Limiter: defaults.vo2LimiterMode,
                sleepRestHours: defaults.sleepRestHours,
                sleepLiftingHours: defaults.sleepLiftingHours,
                sleepEnduranceHours: defaults.sleepEnduranceHours,
                targetWakeHm: defaults.targetWakeHm,
                oneMileTrialMaxHr: defaults.oneMileTrialMaxHr,
                weeklyLiftingMin: weeklyLiftingMin,
                scheduledDeloadWeeks: defaults.deloadScheduleWeeks
            ))
            let emptyTriad = makeTriad(readiness: nil, readinessTone: .muted, rmssd: nil, rhr: nil,
                                       strain: 0, steps: 0, sleepMin: 0, effPct: 0, targetBedHm: eval.targetBedtimeHm)
            return WhoopDashboardSnapshot(
                shownDay: day, scoredRecoveryDayId: day.string,
                readinessScore: nil, readinessHeadline: "Connect WHOOP Band",
                readinessDetail: "Pair or load your WHOOP database to view nightly HRV, RHR, 4-stage sleep, and Strain.",
                readinessPill: "No data", readinessTone: .muted,
                strain: 0, steps: 0, totalKcal: nil, activeKcal: nil,
                triad: emptyTriad, contributors: [],
                sleep: WhoopSleepBreakdownViewModel(
                    scoredDayId: day.string, totalSleepMinutes: 0, deepMinutes: 0, remMinutes: 0,
                    lightMinutes: 0, wasoMinutes: 0, efficiencyPct: 0, awakenings: 0,
                    onsetSec: nil, offsetSec: nil, hasManualOverride: false,
                    targetBedtimeHm: eval.targetBedtimeHm, dynamicSleepNeedHours: eval.dynamicSleepNeedHours
                ),
                illnessDay: nil, pendingNapProposals: [], pendingWorkoutProposals: [], effectiveNaps: [],
                longevity: WhoopLongevityViewModel(chronoAge: ageYears, waistCm: waistCm, fitnessAge: nil, vitality: nil, treadmillLogs: treadmillLogs),
                coaching: WhoopCoachingDashboardViewModel(evaluation: eval, weeklyLiftingHours: weeklyLiftingMin / 60.0, ctlAtlTsb: nil, ctlSeries: []),
                zones: zones
            )
        }

        let analyticsStore = WhoopAnalyticsStore(whoopDb)

        // Load all metric_series up to shownDay
        let metricRows = try whoopDb.query(
            "SELECT date, key, value FROM metric_series WHERE date <= ? AND value IS NOT NULL ORDER BY date ASC",
            [.text(day.string)]
        )
        var byDate: [String: [String: Double]] = [:]
        var datedHistory: [WhoopDatedMetric] = []
        for r in metricRows {
            let d = r.text("date")
            let k = r.text("key")
            guard let v = r.optionalDouble("value"), v.isFinite else { continue }
            byDate[d, default: [:]][k] = v
            datedHistory.append(WhoopDatedMetric(date: d, key: k, value: v))
        }

        let sortedDates = byDate.keys.sorted()
        // Pick `day.string` if it has overnight sleep/readiness, else latest available scored night <= day
        let scoredDayId: String = {
            if let m = byDate[day.string], m["tst_min"] != nil || m["rmssd"] != nil || m["readiness"] != nil {
                return day.string
            }
            return sortedDates.last(where: { d in
                let m = byDate[d] ?? [:]
                return m["tst_min"] != nil || m["rmssd"] != nil || m["readiness"] != nil
            }) ?? day.string
        }()
        let curMetrics = byDate[scoredDayId] ?? [:]
        let todayMetrics = byDate[day.string] ?? [:]

        // Live 1Hz supplement on `day` when `decoded_onehz` has newer records than `metric_series`
        var liveSteps = Int((todayMetrics["steps"] ?? curMetrics["steps"] ?? 0).rounded())
        var liveStrain = todayMetrics["strain"] ?? curMetrics["strain"] ?? 0.0
        if let bounds = WhoopSubstrateGates.calendarDayBounds(for: day, calendar: calendar) {
            let stepRes = try WhoopStepsEngine.countStepsFromDatabase(
                whoopDb: whoopDb, startSec: bounds.dayStartSec, endSec: bounds.dayEndSec,
                stepTicksPerStep: defaults.stepTicksPerStep
            )
            if stepRes.steps > liveSteps { liveSteps = stepRes.steps }

            if todayMetrics["strain"] == nil {
                let hrRows = try whoopDb.query(
                    "SELECT rec_ts, hr FROM decoded_onehz WHERE rec_ts >= ? AND rec_ts < ? AND hr IS NOT NULL",
                    [.int(bounds.dayStartSec), .int(bounds.dayEndSec)]
                )
                var byMin: [Int64: [Int]] = [:]
                for r in hrRows {
                    let b = WhoopSubstrateGates.plausibleHrOrZero(r.optionalInt("hr"))
                    if b > 0, let ts = r.optionalInt64("rec_ts") {
                        byMin[ts / 60, default: []].append(b)
                    }
                }
                if !byMin.isEmpty {
                    let wakeMins = byMin.values.map { Double($0.reduce(0, +)) / Double($0.count) }
                    let rhrAnchor = curMetrics["rhr"] ?? 52.0
                    let maxHrAnchor = Double(defaults.oneMileTrialMaxHr ?? Int(WhoopReadinessAndStrainEngine.estimatedTanakaMaxHr(ageYears: ageYears).rounded()))
                    let priorQ = WhoopReadinessAndStrainEngine.valuesBefore(key: "quiet_hrr", dayId: day.string, history: datedHistory)
                    if let sRes = WhoopReadinessAndStrainEngine.computeDailyStrain(
                        wakeMinuteHr: wakeMins, rhr: rhrAnchor, maxHr: maxHrAnchor,
                        isFemale: isFemale, priorQuietHrr: priorQ.count >= 3 ? priorQ : [0.12, 0.12, 0.12],
                        sessionMaxStrain: nil
                    ) {
                        liveStrain = max(liveStrain, sRes.strain)
                    }
                }
            }
        }

        // Readiness composite (`kAlgoVersion = 133` glass-box recomputation, falling back to stored `readiness` if <14 prior days)
        let rmssdVal = curMetrics["rmssd"]
        let rhrVal = curMetrics["rhr"]
        let respVal = curMetrics["resp_rate"]
        let composite = WhoopReadinessAndStrainEngine.readinessComposite(
            dayId: scoredDayId,
            sleepSessionRmssd: rmssdVal,
            nocturnalRhr: rhrVal,
            respRateBrpm: respVal,
            settledGen4TempAdc: nil,
            history: datedHistory
        )
        let readinessInt: Int? = composite.headlineScore ?? curMetrics["readiness"].map { min(100, max(1, Int($0.rounded()))) }

        // Consecutive Red days (< 34%)
        var consecutiveRed = 0
        for d in sortedDates.reversed() where d <= scoredDayId {
            let rScore = byDate[d]?["readiness"]
            if let rScore, rScore < 34.0 {
                consecutiveRed += 1
            } else {
                break
            }
        }
        if let r = readinessInt, r < 34 && consecutiveRed == 0 { consecutiveRed = 1 }

        // Sleep window & manual override check
        let manualOverride = try analyticsStore.sleepOverride(for: scoredDayId)
        var onsetSec: Int64? = manualOverride?.startTs ?? curMetrics["sleep_onset_sec"].map(Int64.init)
        var offsetSec: Int64? = manualOverride?.endTs
        if onsetSec == nil || offsetSec == nil {
            if let winJson = try whoopDb.query("SELECT window_json FROM day_result WHERE day_id = ? ORDER BY algo_version DESC LIMIT 1", [.text(scoredDayId)]).first?.optionalText("window_json"),
               let winObj = (try? JSONSerialization.jsonObject(with: Data(winJson.utf8))) as? [String: Any] {
                if onsetSec == nil, let onMs = winObj["onset_ms"] as? Double { onsetSec = Int64(onMs / 1000.0) }
                if offsetSec == nil, let offMs = winObj["offset_ms"] as? Double { offsetSec = Int64(offMs / 1000.0) }
            }
        }

        let tstMin: Int = {
            if let ov = manualOverride { return max(0, Int((ov.endTs - ov.startTs) / 60)) }
            return Int((curMetrics["tst_min"] ?? 0).rounded())
        }()
        let deepMin = Int((curMetrics["deep_min"] ?? 0).rounded())
        let remMin = Int((curMetrics["rem_min"] ?? 0).rounded())
        let lightMin = max(0, Int((curMetrics["light_min"] ?? Double(max(0, tstMin - deepMin - remMin))).rounded()))
        let effRaw = curMetrics["efficiency"] ?? 0
        let effPct = Int((effRaw <= 1.05 && effRaw > 0 ? effRaw * 100.0 : effRaw).rounded())
        let wasoMin = effPct > 0 ? max(0, Int((Double(tstMin) * (100.0 / Double(max(50, effPct)) - 1.0)).rounded())) : 0
        let awakenings = Int((curMetrics["awakenings"] ?? 0).rounded())

        // Meal-to-sleep & check-in flags on scoredDay
        let mealEvalDate = ISODate(scoredDayId)?.adding(days: -1) ?? day.adding(days: -1)
        let mealSleep = try LastMealToSleepEvaluator(db: fitnessDb, calendar: calendar)
            .evaluate(day: mealEvalDate, sleepOnsetEpochSec: onsetSec)
        let checkInToday = try CheckInService(fitnessDb).day(day)

        // Effective naps & pending proposals
        let effectiveNaps = try analyticsStore.effectiveNaps(for: day.string)
        let validNapMin = effectiveNaps.reduce(0) { $0 + ($1.durationSec / 60) } + Int((todayMetrics["nap_min"] ?? 0).rounded())
        let pendingAll = try analyticsStore.activityProposals(status: "pending")
        let pendingNaps = Array(pendingAll.filter { $0.kind == "nap" }.prefix(3))
        let pendingWorkouts = Array(pendingAll.filter { $0.kind == "workout" }.prefix(3))

        // Day load kind for dynamic sleep need
        let todayHasEndurance = weekCardio.contains { $0.performedOn == day }
        let todaySets = try fitnessDb.query("SELECT COUNT(*) AS n FROM set_logs WHERE performed_on = ?", [.text(day.string)]).first?.int("n") ?? 0
        let loadKind: WhoopDayLoadKind = todayHasEndurance ? .endurance : (todaySets > 0 ? .lifting : .rest)

        // Yesterday strain
        let prevDayId = (ISODate(scoredDayId)?.adding(days: -1) ?? day.adding(days: -1)).string
        let yesterdayStrain = byDate[prevDayId]?["strain"]

        // Estimate Zone 2 weekly minutes from metric_series `active_min` if explicit cardio sessions are empty
        let activeMin7d = sortedDates.suffix(7).reduce(0.0) { $0 + (byDate[$1]?["active_min"] ?? 0) }
        let resolvedWeeklyZ2 = weeklyZ2MinFromSessions > 0 ? weeklyZ2MinFromSessions : activeMin7d * 0.65

        let coachEval = WhoopCoachingEngine.evaluate(WhoopCoachingInput(
            mode: defaults.whoopCoachingMode,
            vo2Limiter: defaults.vo2LimiterMode,
            readinessScore: readinessInt,
            consecutiveRedDays: consecutiveRed,
            sleepHoursLastNight: tstMin > 0 ? Double(tstMin) / 60.0 : nil,
            yesterdayStrain: yesterdayStrain,
            lastMealGapHours: mealSleep.gapHours,
            alcoholWithinCutoff: mealSleep.alcoholWithinCutoff,
            caffeineCompliant: checkInToday.caffeineBeforeNoon,
            dayLoadKind: loadKind,
            sleepRestHours: defaults.sleepRestHours,
            sleepLiftingHours: defaults.sleepLiftingHours,
            sleepEnduranceHours: defaults.sleepEnduranceHours,
            sleepDebtHours: tstMin > 0 ? max(0.0, defaults.sleepLiftingHours - Double(tstMin) / 60.0) : 0.0,
            validNapMinutesToday: validNapMin,
            targetWakeHm: defaults.targetWakeHm,
            oneMileTrialMaxHr: defaults.oneMileTrialMaxHr,
            weeklyZone2Min: resolvedWeeklyZ2,
            weeklyZone4And5Min: weeklyZ45MinFromSessions,
            weeklyTotalCardioMin: max(weeklyCardioMin, resolvedWeeklyZ2),
            priorWeekCardioMin: priorCardioMin,
            weeklyLiftingMin: weeklyLiftingMin,
            recentCardioSessions: weekCardio.map {
                WhoopLoggedCardioSummary(
                    kind: $0.kind,
                    durationMin: Double(max(0, ($0.endTs ?? $0.startTs) - $0.startTs)) / 60.0,
                    avgHr: $0.avgHr,
                    longEnduranceExempt: $0.longEnduranceExempt
                )
            },
            todaySteps: liveSteps,
            scheduledDeloadWeeks: defaults.deloadScheduleWeeks
        ))

        // Readiness tone & copy
        let rTone: WhoopHoopTone
        let rHeadline: String
        let rPill: String
        let rDetail: String
        if let r = readinessInt {
            if r >= 67 {
                rTone = .green
                rHeadline = "Optimal recovery"
                rPill = "Normal strain"
                rDetail = "Autonomic HRV & RHR sit above your 28-day self-excluded baseline (\(scoredDayId))."
            } else if r >= 34 {
                rTone = .amber
                rHeadline = "Moderate recovery"
                rPill = "Steady load"
                rDetail = "Within normal 28-day variation (\(scoredDayId)) — train as planned."
            } else if coachEval.keepNormalStrainOverride {
                rTone = .amber
                rHeadline = "Red · Context override"
                rPill = "Keep normal strain"
                rDetail = "1st Red score aligns with sleep/meal timing rather than training overload. Deload triggers only at 3+ Red days."
            } else {
                rTone = .red
                rHeadline = coachEval.deloadTriggered ? "Rest / Deload advised" : "Low recovery"
                rPill = coachEval.deloadTriggered ? "3+ Red · Deload" : "Easy day"
                rDetail = "Autonomic recovery suppressed below your 28-day baseline (\(scoredDayId))."
            }
        } else {
            rTone = .muted
            rHeadline = "Calibrating baseline"
            rPill = "Collecting nights"
            rDetail = "Wear your WHOOP overnight to populate 28-day HRV & RHR baselines."
        }

        // Strict Triad Order: 1. Recovery (0-100%), 2. Strain (0-21), 3. Sleep (hours/%)
        let triad = makeTriad(
            readiness: readinessInt, readinessTone: rTone, rmssd: rmssdVal, rhr: rhrVal,
            strain: liveStrain, steps: liveSteps,
            sleepMin: tstMin, effPct: effPct, targetBedHm: coachEval.targetBedtimeHm
        )

        // 4 Glass-box contributor rows with 7-day sparklines
        let recent7Dates = Array(sortedDates.suffix(7))
        func spark(_ key: String) -> [Double] { recent7Dates.compactMap { byDate[$0]?[key] } }

        let hrvMed = WhoopMath.median(WhoopReadinessAndStrainEngine.valuesBefore(key: "rmssd", dayId: scoredDayId, history: datedHistory))
        let rhrMed = WhoopMath.median(WhoopReadinessAndStrainEngine.valuesBefore(key: "rhr", dayId: scoredDayId, history: datedHistory))
        let respMed = WhoopMath.median(WhoopReadinessAndStrainEngine.valuesBefore(key: "resp_rate", dayId: scoredDayId, history: datedHistory))

        // Temp illness evaluation
        let tempInputs: [WhoopTempNightInput] = sortedDates.enumerated().map { idx, d in
            WhoopTempNightInput(dayIndex: idx, date: d, tempUnit: byDate[d]?["skin_temp_adc"], luteal: false)
        }
        let illness = WhoopReadinessAndStrainEngine.evaluateTempIllness(tempInputs).last

        var contributors: [WhoopContributorRowViewModel] = []
        if let v = rmssdVal {
            let deltaPct = hrvMed.map { Int(((v - $0) / max(1.0, $0) * 100.0).rounded()) } ?? 0
            contributors.append(WhoopContributorRowViewModel(
                id: "hrv", title: "HRV (5m mean)",
                subtitle: hrvMed.map { "\(Int(v.rounded())) ms · 28d med \(Int($0.rounded())) ms" } ?? "\(Int(v.rounded())) ms",
                ringProgress: min(1.0, max(0.15, v / 110.0)),
                ringLabel: "\(Int(v.rounded()))",
                badgeText: deltaPct >= 0 ? "+\(deltaPct)%" : "\(deltaPct)%",
                tone: deltaPct >= -5 ? .green : .amber,
                sparkline: spark("rmssd")
            ))
        }
        if let v = rhrVal {
            let diff = rhrMed.map { v - $0 } ?? 0
            contributors.append(WhoopContributorRowViewModel(
                id: "rhr", title: "Nocturnal RHR",
                subtitle: rhrMed.map { String(format: "%.1f bpm · 28d med %.1f", v, $0) } ?? String(format: "%.1f bpm", v),
                ringProgress: min(1.0, max(0.15, (85.0 - v) / 45.0)),
                ringLabel: "\(Int(v.rounded()))",
                badgeText: String(format: "%+.1f bpm", diff),
                tone: diff <= 1.5 ? .green : .amber,
                sparkline: spark("rhr")
            ))
        }
        if let v = respVal {
            contributors.append(WhoopContributorRowViewModel(
                id: "resp", title: "Respiration",
                subtitle: respMed.map { String(format: "%.1f brpm · med %.1f", v, $0) } ?? String(format: "%.1f brpm", v),
                ringProgress: min(1.0, max(0.2, (22.0 - v) / 12.0)),
                ringLabel: String(format: "%.1f", v),
                badgeText: "Steady",
                tone: .greenSoft,
                sparkline: spark("resp_rate")
            ))
        }
        let tempZ = illness?.z ?? curMetrics["skin_temp_z"] ?? 0.0
        contributors.append(WhoopContributorRowViewModel(
            id: "temp", title: "Skin temp",
            subtitle: illness?.flag == .elevated ? "Elevated ≥2 nights — rest" : "Illness flag: Normal",
            ringProgress: illness?.flag == .elevated ? 0.35 : 0.88,
            ringLabel: String(format: "%+.1fσ", tempZ),
            badgeText: illness?.flag == .elevated ? "Elevated" : "Clear",
            tone: illness?.flag == .elevated ? .red : .green,
            sparkline: spark("skin_temp_adc")
        ))

        // Weekly Longevity (last 7 calendar days up to scoredDayId)
        let anchorDate = ISODate(scoredDayId) ?? day
        let days7: [WhoopLongevityDayInput] = (0..<7).reversed().map { off in
            let d = anchorDate.adding(days: -off).string
            let m = byDate[d] ?? [:]
            return WhoopLongevityDayInput(
                date: d,
                restingHr: m["rhr"],
                strain0To21: m["strain"],
                sleepMinutes: m["tst_min"],
                rmssdMs: m["rmssd"],
                steps: m["steps"]
            )
        }
        let fitAge = WhoopLongevityEngines.computeFitnessAge(
            days7: days7, chronoAge: ageYears, sex: isFemale ? "female" : "male", waistCm: waistCm
        )
        let vit = WhoopLongevityEngines.computeVitality(days7: days7, chronoAge: ageYears)

        // CTL / ATL / TSB series
        let trimpDates = sortedDates.filter { byDate[$0]?["trimp"] != nil }
        let trimpVals = trimpDates.compactMap { byDate[$0]?["trimp"] }
        let ctlAtl = WhoopReadinessAndStrainEngine.computeCtlAtlTsb(dailyTrimpSeries: trimpVals)
        var ctlPoints: [WhoopCoachingSeriesPoint] = []
        if trimpVals.count >= 7 {
            let seed = trimpVals.prefix(7).reduce(0, +) / 7.0
            var ctl = seed, atl = seed
            let lCtl = 1.0 - exp(-1.0 / 42.0)
            let lAtl = 1.0 - exp(-1.0 / 7.0)
            var allPts: [WhoopCoachingSeriesPoint] = []
            for (idx, v) in trimpVals.enumerated() {
                ctl += lCtl * (v - ctl)
                atl += lAtl * (v - atl)
                let dStr = trimpDates[idx]
                let shortLbl = String(dStr.suffix(5)) // MM-DD
                allPts.append(WhoopCoachingSeriesPoint(id: dStr, label: shortLbl, ctl: ctl, atl: atl))
            }
            ctlPoints = Array(allPts.suffix(8))
        }

        let ceilingObs = WhoopReadinessAndStrainEngine.valuesBefore(key: "hr_ceiling_bpm", dayId: day.string, history: datedHistory).max().map(Int.init)
        let rhr28 = WhoopReadinessAndStrainEngine.valuesBefore(key: "rhr", dayId: day.string, history: datedHistory)
        let zones = WhoopReadinessAndStrainEngine.trainingZones(
            ageYears: ageYears, manualBounds: defaults.manualHrZoneBounds,
            oneMileMaxHr: defaults.oneMileTrialMaxHr, observedCeilingBpm: ceilingObs, rhrHistory28d: rhr28
        )

        let totalKcal = (todayMetrics["calories_total"] ?? curMetrics["calories_total"]).map { Int($0.rounded()) }
        let activeKcal = (todayMetrics["calories"] ?? curMetrics["calories"]).map { Int($0.rounded()) }

        return WhoopDashboardSnapshot(
            shownDay: day,
            scoredRecoveryDayId: scoredDayId,
            readinessScore: readinessInt,
            readinessHeadline: rHeadline,
            readinessDetail: rDetail,
            readinessPill: rPill,
            readinessTone: rTone,
            strain: liveStrain,
            steps: liveSteps,
            totalKcal: totalKcal,
            activeKcal: activeKcal,
            triad: triad,
            contributors: contributors,
            sleep: WhoopSleepBreakdownViewModel(
                scoredDayId: scoredDayId,
                totalSleepMinutes: tstMin,
                deepMinutes: deepMin,
                remMinutes: remMin,
                lightMinutes: lightMin,
                wasoMinutes: wasoMin,
                efficiencyPct: effPct,
                awakenings: awakenings,
                onsetSec: onsetSec,
                offsetSec: offsetSec,
                hasManualOverride: manualOverride != nil,
                targetBedtimeHm: coachEval.targetBedtimeHm,
                dynamicSleepNeedHours: coachEval.dynamicSleepNeedHours
            ),
            illnessDay: illness,
            pendingNapProposals: pendingNaps,
            pendingWorkoutProposals: pendingWorkouts,
            effectiveNaps: effectiveNaps,
            longevity: WhoopLongevityViewModel(
                chronoAge: ageYears, waistCm: waistCm, fitnessAge: fitAge, vitality: vit, treadmillLogs: treadmillLogs
            ),
            coaching: WhoopCoachingDashboardViewModel(
                evaluation: coachEval,
                weeklyLiftingHours: weeklyLiftingMin / 60.0,
                ctlAtlTsb: ctlAtl,
                ctlSeries: ctlPoints
            ),
            zones: zones
        )
    }

    public static func formatHoursMinutes(_ totalMinutes: Int) -> String {
        guard totalMinutes > 0 else { return "—" }
        return "\(totalMinutes / 60)h\(String(format: "%02d", totalMinutes % 60))"
    }

    private static func makeTriad(
        readiness: Int?, readinessTone: WhoopHoopTone, rmssd: Double?, rhr: Double?,
        strain: Double, steps: Int,
        sleepMin: Int, effPct: Int, targetBedHm: String
    ) -> [WhoopTriadHoopViewModel] {
        // 1. Recovery (0–100%, leftmost)
        let recProgress = readiness.map { Double($0) / 100.0 } ?? 0.02
        let recLabel = readiness.map { "\($0)%" } ?? "—"
        let recFooter: String
        if let rmssd, let rhr {
            recFooter = "\(Int(rmssd.rounded())) ms · \(Int(rhr.rounded())) bpm"
        } else {
            recFooter = "No sleep yet"
        }

        // 2. Strain (0.0–21.0, middle)
        let clampedStrain = min(21.0, max(0.0, strain))
        let strainLabel = String(format: "%.1f", clampedStrain)
        let stepsText = steps > 0 ? "\(steps) steps" : "0–21 load"

        // 3. Sleep (hours / %, rightmost)
        let sleepProgress = sleepMin > 0 ? min(1.0, Double(sleepMin) / 480.0) : 0.02
        let sleepLabel = formatHoursMinutes(sleepMin)
        let sleepSub = effPct > 0 ? "\(effPct)% eff" : "asleep"

        return [
            WhoopTriadHoopViewModel(
                title: "Recovery",
                progress: recProgress,
                ringLabel: recLabel,
                ringSubLabel: "ready",
                footerText: recFooter,
                tone: readinessTone
            ),
            WhoopTriadHoopViewModel(
                title: "Strain",
                progress: max(0.02, clampedStrain / 21.0),
                ringLabel: strainLabel,
                ringSubLabel: "of 21",
                footerText: stepsText,
                tone: .gold
            ),
            WhoopTriadHoopViewModel(
                title: "Sleep",
                progress: sleepProgress,
                ringLabel: sleepLabel,
                ringSubLabel: sleepSub,
                footerText: "Bed \(targetBedHm)",
                tone: .greenSoft
            ),
        ]
    }
}
