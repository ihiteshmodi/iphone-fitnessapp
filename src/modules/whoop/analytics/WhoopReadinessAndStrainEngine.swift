import Foundation

public struct WhoopReadinessResult: Equatable, Sendable {
    public let compositeZ: Double?
    public let rawScore: Double?
    public let headlineScore: Int?
    public let usedInputs: [String]
    public let calibrated: Bool
    public let refusalReason: String?
}

public enum WhoopTempFlag: String, Codable, Equatable, Sendable {
    case normal = "normal"
    case lutealConfound = "luteal_confound"
    case elevated = "elevated"
}

public struct WhoopTempNightInput: Equatable, Sendable {
    public let dayIndex: Int
    public let date: String
    public let tempUnit: Double?
    public let luteal: Bool

    public init(dayIndex: Int, date: String, tempUnit: Double?, luteal: Bool) {
        self.dayIndex = dayIndex
        self.date = date
        self.tempUnit = tempUnit
        self.luteal = luteal
    }
}

public struct WhoopTempIllnessDay: Equatable, Sendable {
    public let date: String
    public let flag: WhoopTempFlag
    public let z: Double?
    public let luteal: Bool
    public let confidence: Double
    public let note: String?
}

public struct WhoopStrainResult: Equatable, Sendable {
    public let grossTrimp: Double
    public let quietHrrToday: Double?
    public let personalQuietHrr: Double
    public let exerciseNetTrimp: Double
    public let livingNetTrimp: Double
    public let guardedNetTrimp: Double
    public let strain: Double
    public let confidence: Double
}

public struct WhoopCtlAtlTsb: Equatable, Sendable {
    public let ctl: Double
    public let atl: Double
    public let tsb: Double
}

public struct WhoopTrainingZones: Equatable, Sendable {
    public let source: String // "manual" | "karvonen" | "observed" | "tanaka"
    /// 5 ascending BPM bounds: [Z1_floor, Z2_floor, Z3_floor, Z4_floor, Z5_floor], with maxHr ceiling.
    public let boundsBpm: [Int]
    public let maxHrBpm: Int

    public init(source: String, boundsBpm: [Int], maxHrBpm: Int) {
        self.source = source
        self.boundsBpm = boundsBpm
        self.maxHrBpm = maxHrBpm
    }
}

public struct WhoopDailyEnergyResult: Equatable, Sendable {
    public let basalKcal: Double
    public let activeKcal: Double
    public let totalKcal: Double
}

public enum WhoopReadinessAndStrainEngine {
    // MARK: - §3.4.1 Strict Self-Excluded Trailing 28d Baseline (`valuesBefore`)

    public static func valuesBefore(key: String, dayId: String, history: [WhoopDatedMetric], maxDays: Int = 28) -> [Double] {
        let filtered = history
            .filter { $0.key == key && $0.date < dayId && $0.value.isFinite }
            .sorted { $0.date < $1.date }
        if filtered.count <= maxDays { return filtered.map(\.value) }
        return Array(filtered.suffix(maxDays)).map(\.value)
    }

    public static func dispersionBelowQuantum(baseline: [Double], quantum: Double) -> Bool {
        guard quantum > 0, baseline.count >= 2 else { return false }
        let onGrid = baseline.filter { v in
            let ratio = v / quantum
            return abs(ratio - ratio.rounded()) < 1e-6
        }.count
        let fracOnGrid = Double(onGrid) / Double(baseline.count)
        let sd = WhoopMath.sampleStdDev(baseline) ?? 0
        return fracOnGrid >= 0.50 && sd < quantum
    }

    public static func robustStandardizedZ(value: Double, baseline: [Double], quantum: Double) -> Double? {
        guard baseline.count >= 14 else { return nil }
        if quantum > 0 && dispersionBelowQuantum(baseline: baseline, quantum: quantum) {
            return nil
        }
        guard let med = WhoopMath.median(baseline), let madVal = WhoopMath.mad(baseline, center: med) else {
            return nil
        }
        let scale = 1.4826 * madVal
        if scale > 1e-9 {
            return (value - med) / scale
        }
        guard let m = WhoopMath.mean(baseline), let sd = WhoopMath.sampleStdDev(baseline), sd > 1e-9 else {
            return nil
        }
        return (value - m) / sd
    }

    // MARK: - §3.4.2 Canonical Glass-Box Readiness Composite (`readinessComposite`)

    public static func readinessComposite(
        dayId: String,
        sleepSessionRmssd: Double?,
        nocturnalRhr: Double?,
        respRateBrpm: Double?,
        settledGen4TempAdc: Double?,
        history: [WhoopDatedMetric]
    ) -> WhoopReadinessResult {
        var used: [String] = []
        var autoZs: [Double] = []

        if let rmssd = sleepSessionRmssd, rmssd > 0 {
            let base = valuesBefore(key: "ln_rmssd", dayId: dayId, history: history)
            if let z = robustStandardizedZ(value: log(rmssd), baseline: base, quantum: 0) {
                autoZs.append(+1.0 * z)
                used.append("hrv")
            }
        }
        if let rhr = nocturnalRhr, rhr > 0 {
            let base = valuesBefore(key: "rhr", dayId: dayId, history: history)
            if let z = robustStandardizedZ(value: rhr, baseline: base, quantum: 1.0) {
                autoZs.append(-1.0 * z)
                used.append("rhr")
            }
        }

        var nonAutoTerms: [(zOriented: Double, weight: Double)] = []
        if let rr = respRateBrpm, rr > 0 {
            let base = valuesBefore(key: "resp_rate", dayId: dayId, history: history)
            if let z = robustStandardizedZ(value: rr, baseline: base, quantum: 0) {
                nonAutoTerms.append((-1.0 * z, 0.20))
                used.append("resp_rate")
            }
        }
        if let temp = settledGen4TempAdc, temp > 0 {
            let base = valuesBefore(key: "skin_temp_adc", dayId: dayId, history: history)
            if let z = robustStandardizedZ(value: temp, baseline: base, quantum: 1.0) {
                nonAutoTerms.append((-1.0 * z, 0.10))
                used.append("temp")
            }
        }

        let wAuto = autoZs.isEmpty ? 0.0 : 0.70
        let wSum = wAuto + nonAutoTerms.reduce(0.0) { $0 + $1.weight }
        guard used.count >= 2, wSum >= 0.50 else {
            return WhoopReadinessResult(compositeZ: nil, rawScore: nil, headlineScore: nil, usedInputs: used,
                                        calibrated: false, refusalReason: "insufficient_inputs_or_baseline")
        }

        var weightedSum = 0.0
        if !autoZs.isEmpty {
            let eachW = 0.70 / Double(autoZs.count)
            for z in autoZs { weightedSum += eachW * z }
        }
        for t in nonAutoTerms { weightedSum += t.weight * t.zOriented }
        let zComp = weightedSum / wSum

        let zHist = valuesBefore(key: "readiness_z", dayId: dayId, history: history)
        let calibrated = (zHist.count >= 14)
        let score: Double
        if !calibrated {
            score = 100.0 / (1.0 + exp(-zComp))
        } else {
            let medZ = WhoopMath.median(zHist) ?? 0.0
            let madZ = WhoopMath.mad(zHist, center: medZ) ?? 0.0
            let sigmaHat = max(0.30, 1.4826 * madZ)
            let cHat = min(0.50, max(-0.50, medZ))
            score = 100.0 / (1.0 + exp(-0.65 * (zComp - cHat) / sigmaHat))
        }

        if abs(zComp) > WhoopCoreConstants.readinessZCap {
            return WhoopReadinessResult(compositeZ: zComp, rawScore: score, headlineScore: nil, usedInputs: used,
                                        calibrated: calibrated, refusalReason: "unstable_baseline")
        }
        let roundedHeadline = min(100, max(1, Int(score.rounded())))
        return WhoopReadinessResult(compositeZ: zComp, rawScore: score, headlineScore: roundedHeadline,
                                    usedInputs: used, calibrated: calibrated, refusalReason: nil)
    }

    // MARK: - §3.6.1 Cycle-Aware Skin-Temperature Illness Flag (`tempIllnessFlag`)

    public static func skinTempAmbientCorrelation(skinMinuteMeans: [Double], ambientMinuteMeans: [Double]) -> Double? {
        let n = min(skinMinuteMeans.count, ambientMinuteMeans.count)
        guard n >= 31 else { return nil }
        var dSkin: [Double] = []
        var dAmb: [Double] = []
        for i in 1..<n {
            dSkin.append(skinMinuteMeans[i] - skinMinuteMeans[i - 1])
            dAmb.append(ambientMinuteMeans[i] - ambientMinuteMeans[i - 1])
        }
        guard dSkin.count >= 30,
              let ms = WhoopMath.mean(dSkin), let ma = WhoopMath.mean(dAmb) else { return nil }
        var num = 0.0, ss = 0.0, sa = 0.0
        for k in 0..<dSkin.count {
            let xs = dSkin[k] - ms
            let xa = dAmb[k] - ma
            num += xs * xa
            ss += xs * xs
            sa += xa * xa
        }
        guard ss > 1e-12 && sa > 1e-12 else { return 0 }
        return num / sqrt(ss * sa)
    }

    public static func evaluateTempIllness(_ nights: [WhoopTempNightInput]) -> [WhoopTempIllnessDay] {
        var out: [WhoopTempIllnessDay] = []
        var elevatedRun = 0
        var lastScoredDay: Int?

        for i in 0..<nights.count {
            let cur = nights[i]
            let priorWindow = (0..<i).compactMap { j -> Double? in
                guard (cur.dayIndex - nights[j].dayIndex) <= 21 else { return nil }
                return nights[j].tempUnit
            }

            guard let val = cur.tempUnit else {
                out.append(WhoopTempIllnessDay(date: cur.date, flag: .normal, z: nil, luteal: cur.luteal, confidence: 0.0, note: nil))
                continue
            }
            guard priorWindow.count >= 7 else {
                out.append(WhoopTempIllnessDay(date: cur.date, flag: .normal, z: nil, luteal: cur.luteal, confidence: 0.0,
                                               note: "need_baseline:have=\(priorWindow.count),need=7"))
                continue
            }
            guard let med = WhoopMath.median(priorWindow),
                  let madRaw = WhoopMath.mad(priorWindow, center: med) else {
                out.append(WhoopTempIllnessDay(date: cur.date, flag: .normal, z: nil, luteal: cur.luteal, confidence: 0.0, note: nil))
                continue
            }
            let scale = 1.4826 * madRaw
            guard scale > 1e-9 else {
                out.append(WhoopTempIllnessDay(date: cur.date, flag: .normal, z: nil, luteal: cur.luteal, confidence: 0.0, note: "zero_mad"))
                continue
            }

            if let last = lastScoredDay, (cur.dayIndex - last) > 3 {
                elevatedRun = 0
            }
            lastScoredDay = cur.dayIndex

            let z = (val - med) / scale
            if z >= 2.0 {
                elevatedRun += 1
            } else {
                elevatedRun = 0
            }

            let flag: WhoopTempFlag
            let conf: Double
            if z < 2.0 {
                flag = .normal
                conf = 0.60
            } else if elevatedRun < 2 {
                flag = .normal
                conf = 0.30
            } else if cur.luteal {
                flag = .lutealConfound
                conf = 0.35
            } else {
                flag = .elevated
                conf = 0.70
            }
            out.append(WhoopTempIllnessDay(date: cur.date, flag: flag, z: z, luteal: cur.luteal, confidence: conf, note: nil))
        }
        return out
    }

    // MARK: - §3.5.2 Banister TRIMP, Personal Quiet-Waking Baseline & 0–21 Strain

    @inline(__always)
    public static func banisterY(_ x: Double, isFemale: Bool) -> Double {
        isFemale ? (0.86 * exp(1.67 * x)) : (0.64 * exp(1.92 * x))
    }

    @inline(__always)
    public static func strainFromNetTrimp(_ netTrimp: Double) -> Double {
        let u = min(1.0, max(0.0, netTrimp / 400.0))
        let raw = 21.0 * log(1.0 + 14.0 * u) / log(15.0)
        return min(21.0, max(0.0, raw))
    }

    public static func estimatedTanakaMaxHr(ageYears: Double) -> Double {
        208.0 - 0.7 * ageYears
    }

    public static func computeDailyStrain(
        wakeMinuteHr: [Double],
        rhr: Double,
        maxHr: Double,
        isFemale: Bool,
        priorQuietHrr: [Double],
        sessionMaxStrain: Double?
    ) -> WhoopStrainResult? {
        guard maxHr > rhr + 10.0 else { return nil }
        let span = maxHr - rhr
        let xVals = wakeMinuteHr.map { min(1.0, max(0.0, ($0 - rhr) / span)) }
        let gross = xVals.reduce(0.0) { $0 + $1 * banisterY($1, isFemale: isFemale) }

        let quietToday: Double?
        if xVals.count >= 360, let medX = WhoopMath.median(xVals), medX > 0 && medX <= 0.40 {
            quietToday = medX
        } else {
            quietToday = nil
        }

        // Cold-start gate: require >= 3 strictly prior quiet_hrr days (never substitute population 0.20)
        guard priorQuietHrr.count >= 3, let q = WhoopMath.median(Array(priorQuietHrr.suffix(28))) else {
            return nil
        }
        let rQ = q * banisterY(q, isFemale: isFemale)
        var exercise = 0.0
        var living = 0.0
        for x in xVals {
            let excess = x * banisterY(x, isFemale: isFemale) - rQ
            if x >= 0.40 {
                exercise += max(0.0, excess)
            } else {
                living += excess
            }
        }
        let guardedNet = exercise + max(0.0, living)
        var strain = strainFromNetTrimp(guardedNet)
        if let sMax = sessionMaxStrain {
            strain = max(strain, min(21.0, max(0.0, sMax)))
        }
        let conf = priorQuietHrr.count >= 7 ? 0.60 : 0.45
        return WhoopStrainResult(
            grossTrimp: gross,
            quietHrrToday: quietToday,
            personalQuietHrr: q,
            exerciseNetTrimp: exercise,
            livingNetTrimp: living,
            guardedNetTrimp: guardedNet,
            strain: strain,
            confidence: conf
        )
    }

    public static func computeCtlAtlTsb(dailyTrimpSeries: [Double]) -> WhoopCtlAtlTsb? {
        guard dailyTrimpSeries.count >= 14 else { return nil }
        let seed = dailyTrimpSeries.prefix(7).reduce(0, +) / 7.0
        var ctl = seed
        var atl = seed
        let lCtl = 1.0 - exp(-1.0 / 42.0)
        let lAtl = 1.0 - exp(-1.0 / 7.0)
        for v in dailyTrimpSeries {
            ctl += lCtl * (v - ctl)
            atl += lAtl * (v - atl)
        }
        return WhoopCtlAtlTsb(ctl: ctl, atl: atl, tsb: ctl - atl)
    }

    // MARK: - §3.5.3 Training Zones (`trainingZones`)

    public static func trainingZones(
        ageYears: Double,
        manualBounds: [Int]? = nil,
        oneMileMaxHr: Int? = nil,
        observedCeilingBpm: Int? = nil,
        rhrHistory28d: [Double] = []
    ) -> WhoopTrainingZones {
        if let manual = manualBounds, manual.count == 5 {
            let ceiling = max(manual[4] + 10, oneMileMaxHr ?? observedCeilingBpm ?? Int(estimatedTanakaMaxHr(ageYears: ageYears).rounded()))
            return WhoopTrainingZones(source: "manual", boundsBpm: manual, maxHrBpm: ceiling)
        }
        let tanaka = estimatedTanakaMaxHr(ageYears: ageYears)
        let pcts = [0.50, 0.60, 0.70, 0.80, 0.90]
        let ceilingCandidate = max(oneMileMaxHr ?? 0, observedCeilingBpm ?? 0)
        if Double(ceilingCandidate) >= tanaka {
            if rhrHistory28d.count >= 14, let rhrMed = WhoopMath.median(Array(rhrHistory28d.suffix(28))) {
                let bounds = pcts.map { Int((rhrMed + $0 * (Double(ceilingCandidate) - rhrMed)).rounded()) }
                return WhoopTrainingZones(source: "karvonen", boundsBpm: bounds, maxHrBpm: ceilingCandidate)
            }
            let bounds = pcts.map { Int(($0 * Double(ceilingCandidate)).rounded()) }
            return WhoopTrainingZones(source: "observed", boundsBpm: bounds, maxHrBpm: ceilingCandidate)
        }
        let maxBpm = Int(tanaka.rounded())
        let bounds = pcts.map { Int(($0 * tanaka).rounded()) }
        return WhoopTrainingZones(source: "tanaka", boundsBpm: bounds, maxHrBpm: maxBpm)
    }

    // MARK: - §3.5.4 Single-Pass Daily Energy (`wakeDayEnergy`)

    public static func computeDailyEnergy(
        wakeMinuteHr: [Double],
        wakeMinuteCadenceSpm: [Double?] = [],
        coveredMinutes: Int,
        ageYears: Double?,
        isFemale: Bool,
        weightKg: Double?,
        heightCm: Double?,
        rhr: Double?,
        maxHr: Double?,
        zeroHrWorkoutGapKcal: Double = 0.0
    ) -> WhoopDailyEnergyResult? {
        guard let ageYears, let weightKg, let heightCm, let rhr, let maxHr,
              ageYears > 0, weightKg > 0, heightCm > 0, maxHr > rhr else {
            return nil
        }
        let sexOffset = isFemale ? -161.0 : 5.0
        let bmrDay = 10.0 * weightKg + 6.25 * heightCm - 5.0 * ageYears + sexOffset
        let basalPerMin = bmrDay / 1440.0
        let basalKcal = basalPerMin * Double(max(0, coveredMinutes))

        let gateBpm = rhr + 0.40 * (maxHr - rhr)
        var activeKcal = max(0.0, zeroHrWorkoutGapKcal)
        for i in 0..<wakeMinuteHr.count {
            let hr = min(wakeMinuteHr[i], maxHr)
            if hr >= gateBpm {
                let keytelKcalPerMin: Double
                if isFemale {
                    keytelKcalPerMin = (0.4472 * hr - 0.1263 * weightKg + 0.0740 * ageYears - 20.4022) / 4.184
                } else {
                    keytelKcalPerMin = (0.6309 * hr + 0.1988 * weightKg + 0.2017 * ageYears - 55.0969) / 4.184
                }
                activeKcal += max(0.0, keytelKcalPerMin - basalPerMin)
            } else if i < wakeMinuteCadenceSpm.count, let cad = wakeMinuteCadenceSpm[i], cad >= 100.0 {
                let met = min(6.0, 3.0 + 0.1 * (cad - 100.0))
                activeKcal += max(0.0, (met - 1.0) * basalPerMin)
            }
        }
        return WhoopDailyEnergyResult(basalKcal: basalKcal, activeKcal: activeKcal, totalKcal: basalKcal + activeKcal)
    }
}
