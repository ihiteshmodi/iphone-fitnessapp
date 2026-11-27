import Foundation

public enum WhoopSleepStage4: String, Codable, Equatable, Sendable {
    case wake = "wake"
    case light = "light"
    case deep = "deep"
    case rem = "rem"
    case unobserved = "unobserved"
}

public struct WhoopSleepUserProfile: Codable, Equatable, Sendable {
    public var nights: Int
    public var enmoStillCut: Double
    public var enmoMoveCut: Double
    public var hrSleepMedian: Double
    public var hrArousal: Double
    public var hrFloorP25: Double

    public init(nights: Int = 0, enmoStillCut: Double = 0.015, enmoMoveCut: Double = 0.050,
                hrSleepMedian: Double = 55.0, hrArousal: Double = 64.0, hrFloorP25: Double = 51.0) {
        self.nights = nights
        self.enmoStillCut = enmoStillCut
        self.enmoMoveCut = enmoMoveCut
        self.hrSleepMedian = hrSleepMedian
        self.hrArousal = hrArousal
        self.hrFloorP25 = hrFloorP25
    }
}

public struct WhoopSleepSegmentation: Equatable, Sendable {
    public let onsetSec: Int64
    public let offsetSec: Int64
    public let bandOffsetTrimSec: Int?
    public let sleepSource: String // "override" | "auto" | "auto_fallback"
    public let stages4: [WhoopSleepStage4]
    public let observedSec: Int
    public let tstSec: Int
    public let lightSec: Int
    public let deepSec: Int
    public let remSec: Int
    public let wasoSec: Int
    public let efficiencyPct: Double
    public let sustainedAwakenings: Int
    public let confidence: Double
}

public struct WhoopDetectedNap: Equatable, Sendable {
    public let startSec: Int64
    public let endSec: Int64
    public let tstSec: Int
    public let medianHr: Double
    public let awakeHrBaseline: Double
    public let confidence: Double
    public let startsAtRecordEdge: Bool
}

public enum WhoopSleepAndNapEngine {
    // MARK: - §3.3.1 Van Hees Z-Angle Immobility (`immobilityMask`)

    public static func zAngleDegrees(ax: Double?, ay: Double?, az: Double?) -> Double? {
        guard WhoopSubstrateGates.accelPlausible(ax: ax, ay: ay, az: az),
              let ax, let ay, let az else { return nil }
        return atan2(az, sqrt(ax * ax + ay * ay)) * 180.0 / .pi
    }

    public static func immobilityMask(
        ax: [Double?], ay: [Double?], az: [Double?],
        smoothSec: Int = 5, sustainedSec: Int = 300, angleThresholdDeg: Double = 5.0
    ) -> (immobile: [Bool], deltaDeg: [Double?], accelPresentFraction: Double) {
        let n = min(ax.count, min(ay.count, az.count))
        guard n > 0 else { return ([], [], 0) }

        var rawZ = [Double?](repeating: nil, count: n)
        var validCount = 0
        for i in 0..<n {
            if let z = zAngleDegrees(ax: ax[i], ay: ay[i], az: az[i]) {
                rawZ[i] = z
                validCount += 1
            }
        }
        let presentFrac = Double(validCount) / Double(n)
        guard presentFrac >= 0.50 else {
            return ([Bool](repeating: false, count: n), [Double?](repeating: nil, count: n), presentFrac)
        }

        // 5-second centered rolling median (`smoothSec = 5`, radius = 2)
        let r = smoothSec / 2
        var smoothZ = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            let lo = max(0, i - r)
            let hi = min(n - 1, i + r)
            var vals: [Double] = []
            for k in lo...hi {
                if let v = rawZ[k] { vals.append(v) }
            }
            if vals.count == (hi - lo + 1) {
                smoothZ[i] = WhoopMath.median(vals)
            }
        }

        var deltaDeg = [Double?](repeating: nil, count: n)
        for i in smoothSec..<n {
            var allValid = true
            for k in (i - smoothSec)...i where smoothZ[k] == nil {
                allValid = false
                break
            }
            if allValid, let cur = smoothZ[i], let prev = smoothZ[i - smoothSec] {
                deltaDeg[i] = abs(cur - prev)
            }
        }

        var immobile = [Bool](repeating: false, count: n)
        if n > sustainedSec {
            for i in 0..<(n - sustainedSec) {
                var ok = true
                for k in (i + 1)..<(i + sustainedSec) {
                    guard let d = deltaDeg[k], d < angleThresholdDeg else {
                        ok = false
                        break
                    }
                }
                immobile[i] = ok
            }
        }
        return (immobile, deltaDeg, presentFrac)
    }

    // MARK: - §3.3.1 Habitual Midsleep Selector & Gen5 Band-State Lie-In Trim

    public static func habitualMidsleepSecOfDay(priorMidsleepSecsOfDay: [Double]) -> Double {
        guard priorMidsleepSecsOfDay.count >= 14 else {
            return 3.5 * 3600.0 // 03:30 local cold-start
        }
        var sumSin = 0.0
        var sumCos = 0.0
        for s in priorMidsleepSecsOfDay {
            let ang = 2.0 * .pi * (s / 86400.0)
            sumSin += sin(ang)
            sumCos += cos(ang)
        }
        var meanAng = atan2(sumSin, sumCos)
        if meanAng < 0 { meanAng += 2.0 * .pi }
        return (meanAng / (2.0 * .pi)) * 86400.0
    }

    public static func groupSelectionScore(asleepMin: Double, midsleepSecOfDay: Double, targetMidsleepSecOfDay: Double) -> Double {
        let rawDiff = abs(midsleepSecOfDay - targetMidsleepSecOfDay)
        let circDiff = min(rawDiff, 86400.0 - rawDiff)
        let twoH = 2.0 * 3600.0
        let fiveH = 5.0 * 3600.0
        let bonus: Double
        if circDiff <= twoH {
            bonus = 90.0
        } else if circDiff >= fiveH {
            bonus = 0.0
        } else {
            bonus = 90.0 * (1.0 - (circDiff - twoH) / (fiveH - twoH))
        }
        return asleepMin + bonus
    }

    /// Gen5 lie-in trim (`bandTrimmedOffsetSec`): trims >= 10m wake tail when `state == 2` covers >= 80%,
    /// remaining sleep >= 3h, tail coverage >= 95%, max tail gap <= 300s, and `state == 1` (`STILL`) in tail <= 60s.
    public static func bandTrimmedOffsetSec(startSec: Int64, endSec: Int64, bandStates: [Int?]) -> (trimmedEndSec: Int64, trimmedSec: Int?) {
        let n = Int(endSec - startSec)
        guard n >= 10_800, bandStates.count >= n else { return (endSec, nil) }
        let presentTotal = (0..<n).filter { bandStates[$0] != nil }.count
        guard Double(presentTotal) / Double(n) >= 0.80 else { return (endSec, nil) }

        guard let lastSleepIdx = (0..<n).last(where: { bandStates[$0] == 2 }) else {
            return (endSec, nil)
        }
        let candidateEnd = startSec + Int64(lastSleepIdx + 1)
        let trimLen = Int(endSec - candidateEnd)
        guard trimLen >= 600, (candidateEnd - startSec) >= 10_800 else {
            return (endSec, nil)
        }

        var tailPresent = 0
        var stillCount = 0
        var curGap = 0
        var maxGap = 0
        for k in (lastSleepIdx + 1)..<n {
            if let st = bandStates[k] {
                tailPresent += 1
                if st == 1 { stillCount += 1 }
                curGap = 0
            } else {
                curGap += 1
                maxGap = max(maxGap, curGap)
            }
        }
        guard Double(tailPresent) / Double(trimLen) >= 0.95, maxGap <= 300, stillCount <= 60 else {
            return (endSec, nil)
        }
        return (candidateEnd, trimLen)
    }

    /// HR-led sleep fallback (`hrLedSleepWindow`) when accel is absent/insufficient.
    public static func hrLedSleepWindow(tsSec: [Int64], hr: [Int], daytimeBaselineHr: Double?, calendar: Calendar = .current) -> (onsetSec: Int64, offsetSec: Int64)? {
        let n = min(tsSec.count, hr.count)
        guard n >= 10_800 else { return nil }
        let validHrs = hr.map(WhoopSubstrateGates.plausibleHrOrZero).filter { $0 > 0 }.map(Double.init)
        guard !validHrs.isEmpty else { return nil }
        let thresh: Double
        if let base = daytimeBaselineHr, base > 0 {
            thresh = 0.90 * base
        } else if let p30 = WhoopMath.percentile(validHrs, p: 30.0) {
            thresh = p30
        } else {
            return nil
        }

        // 300s rolling median HR
        var lowMask = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let lo = max(0, i - 150)
            let hi = min(n - 1, i + 150)
            var vals: [Double] = []
            for k in lo...hi {
                let v = WhoopSubstrateGates.plausibleHrOrZero(hr[k])
                if v > 0 { vals.append(Double(v)) }
            }
            if let med = WhoopMath.median(vals), med <= thresh {
                lowMask[i] = true
            }
        }

        var runs: [(Int, Int)] = []
        var i = 0
        while i < n {
            guard lowMask[i] else { i += 1; continue }
            var j = i + 1
            while j < n && lowMask[j] && (tsSec[j] - tsSec[j - 1]) <= 300 { j += 1 }
            runs.append((i, j - 1))
            i = j
        }
        guard !runs.isEmpty else { return nil }

        // Bridge gaps < 30 min (1800s) when no >5m sample hole
        var bridged: [(Int, Int)] = [runs[0]]
        for r in runs.dropFirst() {
            let prev = bridged[bridged.count - 1]
            if (tsSec[r.0] - tsSec[prev.1]) < 1800 {
                var hole = false
                for k in (prev.1 + 1)...r.0 where (tsSec[k] - tsSec[k - 1]) > 300 { hole = true; break }
                if !hole {
                    bridged[bridged.count - 1] = (prev.0, r.1)
                    continue
                }
            }
            bridged.append(r)
        }

        guard let longest = bridged.max(by: { (tsSec[$0.1] - tsSec[$0.0]) < (tsSec[$1.1] - tsSec[$1.0]) }) else {
            return nil
        }
        let onset = tsSec[longest.0]
        let offset = tsSec[longest.1]
        guard (offset - onset) >= 10_800 else { return nil }
        let localHour = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(onset)))
        if (10...19).contains(localHour) { return nil }
        return (onset, offset)
    }

    // MARK: - §3.3.2 4-Class Cardiorespiratory Stager (`cardioStager`)

    public static func stageSleepWindow(
        onsetSec: Int64,
        offsetSec: Int64,
        bandOffsetTrimSec: Int? = nil,
        sleepSource: String = "auto",
        ax: [Double?],
        ay: [Double?],
        az: [Double?],
        hr: [Int],
        rrMs: [Double],
        rrTsMs: [Int64],
        profile: WhoopSleepUserProfile = WhoopSleepUserProfile()
    ) -> WhoopSleepSegmentation? {
        let inBed = Int(offsetSec - onsetSec)
        guard inBed >= 1800, ax.count >= inBed, ay.count >= inBed, az.count >= inBed, hr.count >= inBed else {
            return nil
        }

        let numEpochs = inBed / 30
        guard numEpochs >= 10 else { return nil }

        // Precompute |a_i|_2
        var mag = [Double?](repeating: nil, count: inBed)
        var validHrBool = [Bool](repeating: false, count: inBed)
        for s in 0..<inBed {
            if WhoopSubstrateGates.accelPlausible(ax: ax[s], ay: ay[s], az: az[s]),
               let x = ax[s], let y = ay[s], let z = az[s] {
                mag[s] = sqrt(x * x + y * y + z * z)
            }
            validHrBool[s] = WhoopSubstrateGates.plausibleHrOrZero(hr[s]) > 0
        }

        var epMotion = [Double](repeating: 0, count: numEpochs)
        var epHr = [Double?](repeating: nil, count: numEpochs)
        var epHrSd = [Double](repeating: 0, count: numEpochs)
        var hrCoveredEpochs = 0

        for e in 0..<numEpochs {
            let s0 = e * 30
            let s1 = s0 + 30
            let refLo = max(0, (s0 + 15) - 150)
            let refHi = min(inBed - 1, (s0 + 15) + 150)
            let gRef = WhoopMath.median((refLo...refHi).compactMap { mag[$0] }) ?? 1.0
            var mSum = 0.0
            for s in s0..<s1 {
                if let m = mag[s] { mSum += max(0.0, m - gRef) }
            }
            epMotion[e] = mSum / 30.0

            let hrs = (s0..<s1).compactMap { s -> Double? in
                let v = WhoopSubstrateGates.plausibleHrOrZero(hr[s])
                return v > 0 ? Double(v) : nil
            }
            if let mHr = WhoopMath.mean(hrs) {
                epHr[e] = mHr
                epHrSd[e] = WhoopMath.sampleStdDev(hrs) ?? 0
                hrCoveredEpochs += 1
            }
        }

        guard Double(hrCoveredEpochs) / Double(numEpochs) >= 0.50 else { return nil }

        // RR features per epoch
        let monoRrTs = WhoopSubstrateGates.monotonizeBeatAxis(rrTsMs)
        var epSdnn = [Double?](repeating: nil, count: numEpochs)
        var epRk = [Double?](repeating: nil, count: numEpochs)
        var epLfhf = [Double?](repeating: nil, count: numEpochs)
        var rrCoveredEpochs = 0

        for e in 0..<numEpochs {
            let centerMs = (onsetSec + Int64(e * 30 + 15)) * 1000
            var beats5m: [Double] = []
            var beats3m: [Double] = []
            var times3mSec: [Double] = []
            for i in 0..<min(rrMs.count, monoRrTs.count) {
                let v = rrMs[i]
                guard v >= 300.0 && v <= 2000.0 else { continue }
                if i > 0 && abs(v - rrMs[i - 1]) > 200.0 { continue }
                let dt = abs(monoRrTs[i] - centerMs)
                if dt <= 150_000 {
                    beats5m.append(v)
                    if dt <= 90_000 {
                        beats3m.append(v)
                        times3mSec.append(Double(monoRrTs[i] - (centerMs - 90_000)) / 1000.0)
                    }
                }
            }
            if beats5m.count >= 5 {
                epSdnn[e] = WhoopMath.sampleStdDev(beats5m)
                rrCoveredEpochs += 1
            }
            if beats3m.count >= 16 {
                var ihrDiffs: [Double] = []
                for k in 1..<beats3m.count {
                    let ihr1 = 60000.0 / beats3m[k]
                    let ihr0 = 60000.0 / beats3m[k - 1]
                    ihrDiffs.append(abs(ihr1 - ihr0))
                }
                if ihrDiffs.count >= 15 { epRk[e] = WhoopMath.mean(ihrDiffs) }
                if let m3 = WhoopMath.mean(beats3m) {
                    let centered = beats3m.map { $0 - m3 }
                    var lf = 0.0, hf = 0.0
                    var f = 0.04
                    while f <= 0.40 {
                        let p = WhoopMath.lombScarglePower(timesSec: times3mSec, centeredValues: centered, freqHz: f)
                        if f <= 0.15 { lf += p } else { hf += p }
                        f += 0.01
                    }
                    if hf > 1e-9 { epLfhf[e] = lf / hf }
                }
            }
        }

        // Local & blended baselines
        let pw = min(0.5, max(0.0, Double(profile.nights) / 28.0))
        func blend(_ local: Double, _ personal: Double) -> Double { (1.0 - pw) * local + pw * personal }

        let motMed = WhoopMath.median(epMotion) ?? 0
        let motMad = 1.4826 * (WhoopMath.mad(epMotion, center: motMed) ?? 0)
        let stillCut = motMad > 0 ? blend(motMed + 1.5 * motMad, profile.enmoStillCut) : profile.enmoStillCut
        let bigMoveCut = motMad > 0 ? blend(motMed + 5.0 * motMad, profile.enmoMoveCut) : profile.enmoMoveCut

        let isStill = epMotion.map { $0 <= stillCut }
        let isBigMove = epMotion.map { $0 > bigMoveCut }

        func robustScale(_ arr: [Double?]) -> [Double?] {
            let stillVals = (0..<numEpochs).compactMap { isStill[$0] ? arr[$0] : nil }
            guard stillVals.count >= 4,
                  let med = WhoopMath.median(stillVals),
                  let madRaw = WhoopMath.mad(stillVals, center: med) else {
                return [Double?](repeating: nil, count: numEpochs)
            }
            let scale = 1.4826 * madRaw
            guard scale > 1e-9 else { return [Double?](repeating: nil, count: numEpochs) }
            return arr.map { v in v.map { ($0 - med) / scale } }
        }

        let zRk = robustScale(epRk)
        let zSdnn = robustScale(epSdnn)
        let zLfhf = robustScale(epLfhf)
        let zHrSd = robustScale(epHrSd.map { $0 > 0 ? Optional($0) : nil })

        enum CoarseStage { case wake, rem, nrem }
        var coarse = [CoarseStage](repeating: .nrem, count: numEpochs)
        var deepFlag = [Bool](repeating: false, count: numEpochs)

        for e in 0..<numEpochs {
            let lo = max(0, e - 180)
            let hi = min(numEpochs - 1, e + 180)
            var winHrs = (lo...hi).compactMap { isStill[$0] ? epHr[$0] : nil }
            if winHrs.isEmpty { winHrs = epHr.compactMap { $0 } }
            let p50 = WhoopMath.median(winHrs) ?? profile.hrSleepMedian
            let sd = WhoopMath.sampleStdDev(winHrs) ?? 6.0
            let p25 = WhoopMath.percentile(winHrs, p: 25.0) ?? profile.hrFloorP25

            let hrMedLocal = blend(p50, profile.hrSleepMedian)
            let hrArousalLocal = blend(p50 + max(6.0, sd), profile.hrArousal)
            let hrP25Local = blend(p25, profile.hrFloorP25)
            let curHr = epHr[e] ?? hrMedLocal

            let prevBig = e > 0 ? isBigMove[e - 1] : false
            if curHr >= hrArousalLocal || (isBigMove[e] && (curHr >= hrMedLocal || prevBig)) {
                coarse[e] = .wake
                continue
            }

            func weightedScore(_ terms: [(Double?, Double)]) -> Double {
                var num = 0.0, den = 0.0
                for (z, w) in terms {
                    if let z { num += w * z; den += abs(w) }
                }
                return den > 0 ? (num / den) : 0
            }

            let sRem = weightedScore([(zRk[e], 0.43), (zSdnn[e], 0.32), (zHrSd[e], 0.27), (zLfhf[e], 0.12)])
            let sDeep = weightedScore([(zRk[e], -0.53), (zHrSd[e], -0.43), (zSdnn[e], -0.41), (zLfhf[e], -0.33)])

            if sRem > 0.50 && !isBigMove[e] && curHr >= hrP25Local {
                coarse[e] = .rem
            } else {
                coarse[e] = .nrem
                deepFlag[e] = (sDeep > 0.30)
            }
        }

        // Continuity Pass 1: 3-epoch mode filter
        if numEpochs >= 3 {
            let snap = coarse
            for e in 1..<(numEpochs - 1) where snap[e - 1] == snap[e + 1] && snap[e] != snap[e - 1] {
                coarse[e] = snap[e - 1]
            }
        }

        // Continuity Pass 2: Webster arousal rescore against immutable snapshot
        let preWebster = coarse
        if let firstSleep = preWebster.firstIndex(where: { $0 != .wake }),
           let lastSleep = preWebster.lastIndex(where: { $0 != .wake }), firstSleep < lastSleep {
            var e = firstSleep
            while e <= lastSleep {
                guard preWebster[e] == .wake else { e += 1; continue }
                var wEnd = e
                while wEnd <= lastSleep && preWebster[wEnd] == .wake { wEnd += 1 }
                let wakeEpochs = wEnd - e
                var before = 0
                var bIdx = e - 1
                while bIdx >= 0 && preWebster[bIdx] != .wake { before += 1; bIdx -= 1 }
                var after = 0
                var aIdx = wEnd
                while aIdx < numEpochs && preWebster[aIdx] != .wake { after += 1; aIdx += 1 }
                let maxFlankMin = Double(max(before, after)) * 0.5
                let wakeMin = Double(wakeEpochs) * 0.5
                if (maxFlankMin >= 15.0 && wakeMin <= 4.0)
                    || (maxFlankMin >= 10.0 && wakeMin <= 3.0)
                    || (maxFlankMin >= 4.0 && wakeMin <= 1.0) {
                    for k in e..<wEnd { coarse[k] = .nrem }
                }
                e = wEnd
            }
        }

        // Continuity Pass 4: Clear deepFlag outside NREM & merge short deep (< 6 epochs = 3 min) -> light
        for e in 0..<numEpochs where coarse[e] != .nrem { deepFlag[e] = false }
        var idx = 0
        while idx < numEpochs {
            guard deepFlag[idx] else { idx += 1; continue }
            var end = idx
            while end < numEpochs && deepFlag[end] { end += 1 }
            if (end - idx) < 6 {
                for k in idx..<end { deepFlag[k] = false }
            }
            idx = end
        }

        // Expand 30s epochs to per-second `stages4` & apply observed mask
        var stages4 = [WhoopSleepStage4](repeating: .unobserved, count: inBed)
        var observedCount = 0
        for s in 0..<inBed {
            let e = min(numEpochs - 1, s / 30)
            let accelOk = (mag[s] != nil)
            let hrLo = max(0, s - 15)
            let hrHi = min(inBed - 1, s + 15)
            var hrNear = false
            for k in hrLo...hrHi where validHrBool[k] { hrNear = true; break }
            guard accelOk && hrNear else {
                stages4[s] = .unobserved
                continue
            }
            observedCount += 1
            switch coarse[e] {
            case .wake: stages4[s] = .wake
            case .rem: stages4[s] = .rem
            case .nrem: stages4[s] = deepFlag[e] ? .deep : .light
            }
        }

        guard Double(observedCount) >= 0.50 * Double(inBed) else { return nil }

        var lightSec = 0, deepSec = 0, remSec = 0
        var firstSleepSec: Int?
        var lastSleepSec: Int?
        for s in 0..<inBed {
            switch stages4[s] {
            case .light:
                lightSec += 1
                if firstSleepSec == nil { firstSleepSec = s }
                lastSleepSec = s
            case .deep:
                deepSec += 1
                if firstSleepSec == nil { firstSleepSec = s }
                lastSleepSec = s
            case .rem:
                remSec += 1
                if firstSleepSec == nil { firstSleepSec = s }
                lastSleepSec = s
            default:
                break
            }
        }
        let tstSec = lightSec + deepSec + remSec
        var wasoSec = 0
        var sustainedAwakenings = 0
        if let fs = firstSleepSec, let ls = lastSleepSec, fs < ls {
            var wakeRun = 0
            for s in fs...ls {
                if stages4[s] == .wake {
                    wasoSec += 1
                    wakeRun += 1
                } else {
                    if wakeRun >= 300 { sustainedAwakenings += 1 }
                    wakeRun = 0
                }
            }
            if wakeRun >= 300 { sustainedAwakenings += 1 }
        }

        let eff = 100.0 * Double(tstSec) / Double(max(1, observedCount))
        let rrCov = Double(rrCoveredEpochs) / Double(numEpochs)
        let hrCov = Double(hrCoveredEpochs) / Double(numEpochs)
        let stagingConf = (0.35 + 0.25 * rrCov) * hrCov
        let windowConf = min(0.95, max(0.30, Double(inBed) / 25200.0))
        let conf = min(0.60, max(0.0, 0.5 * (windowConf + stagingConf)))

        return WhoopSleepSegmentation(
            onsetSec: onsetSec,
            offsetSec: offsetSec,
            bandOffsetTrimSec: bandOffsetTrimSec,
            sleepSource: sleepSource,
            stages4: stages4,
            observedSec: observedCount,
            tstSec: tstSec,
            lightSec: lightSec,
            deepSec: deepSec,
            remSec: remSec,
            wasoSec: wasoSec,
            efficiencyPct: eff,
            sustainedAwakenings: sustainedAwakenings,
            confidence: conf
        )
    }

    // MARK: - §3.6.3 Daytime Nap Detection (`detectNaps`)

    public static func detectNaps(
        tsSec: [Int64],
        ax: [Double?],
        ay: [Double?],
        az: [Double?],
        hr: [Int],
        onWrist: [Bool],
        charging: [Bool],
        dayStartSec: Int64,
        dayEndSec: Int64,
        mainSleepUntrimmed: (onsetSec: Int64, offsetSec: Int64)?,
        tonightSleepOnsetSec: Int64?
    ) -> [WhoopDetectedNap] {
        let n = min(tsSec.count, min(hr.count, min(ax.count, min(ay.count, az.count))))
        guard n >= WhoopCoreConstants.minNapSec else { return [] }

        let imm = immobilityMask(ax: ax, ay: ay, az: az)
        var stillAt = [Bool](repeating: false, count: n)
        for k in 0..<n {
            if let d = imm.deltaDeg[k], d < 5.0 {
                let dtOk = k == 0 || (tsSec[k] > tsSec[k - 1] && (tsSec[k] - tsSec[k - 1]) <= 5)
                stillAt[k] = dtOk
            }
        }

        // Collect contiguous still runs >= 300s and bridge gaps < 300s
        var runs: [(Int, Int)] = []
        var idx = 0
        while idx < n {
            guard stillAt[idx] else { idx += 1; continue }
            var end = idx + 1
            while end < n && stillAt[end] { end += 1 }
            if (tsSec[end - 1] - tsSec[idx]) >= 300 {
                runs.append((idx, end - 1))
            }
            idx = end
        }
        guard !runs.isEmpty else { return [] }

        var bridged: [(Int, Int)] = [runs[0]]
        for r in runs.dropFirst() {
            let prev = bridged[bridged.count - 1]
            if (tsSec[r.0] - tsSec[prev.1]) < 300 {
                bridged[bridged.count - 1] = (prev.0, r.1)
            } else {
                bridged.append(r)
            }
        }

        var detected: [WhoopDetectedNap] = []
        for cand in bridged {
            let sSec = tsSec[cand.0]
            let eSec = tsSec[cand.1]
            let tib = Int(eSec - sSec)
            guard tib >= WhoopCoreConstants.minNapSec && tib <= WhoopCoreConstants.maxNapSec else { continue }
            guard sSec < dayEndSec else { continue }
            if cand.1 >= n - 1 { continue } // unfinished at record tail
            let startsAtEdge = (cand.0 == 0)
            if startsAtEdge && tsSec[0] <= dayStartSec + WhoopCoreConstants.napLeadingEdgeContiguitySec {
                continue // owned by yesterday
            }
            if let ms = mainSleepUntrimmed {
                if sSec < ms.offsetSec && ms.onsetSec < eSec { continue }
                if tib <= 3600 && sSec >= ms.offsetSec && (sSec - ms.offsetSec) <= 5400 { continue }
            }
            if let tonight = tonightSleepOnsetSec, eSec > tonight { continue }

            let spanLen = cand.1 - cand.0 + 1
            var accelValid = 0, hrValid = 0, offWristCount = 0, chgCount = 0, stillSamples = 0
            var boutHrs: [Double] = []
            for k in cand.0...cand.1 {
                if WhoopSubstrateGates.accelPlausible(ax: ax[k], ay: ay[k], az: az[k]) { accelValid += 1 }
                let h = WhoopSubstrateGates.plausibleHrOrZero(hr[k])
                if h > 0 { hrValid += 1; boutHrs.append(Double(h)) }
                if k < onWrist.count && !onWrist[k] { offWristCount += 1 }
                if k < charging.count && charging[k] { chgCount += 1 }
                if stillAt[k] { stillSamples += 1 }
            }
            let covAccel = Double(accelValid) / Double(max(1, spanLen))
            let covHr = Double(hrValid) / Double(max(1, spanLen))
            let fOff = Double(offWristCount) / Double(max(1, spanLen))
            let fChg = Double(chgCount) / Double(max(1, spanLen))
            guard covAccel >= 0.50 && covHr >= 0.50 && fOff < 0.50 && fChg < 0.50 else { continue }

            // Leave-candidate-out awake HR dip gate (<= 0.95x awake HR median)
            var awakePool: [Double] = []
            for k in 0..<n {
                if k >= cand.0 && k <= cand.1 { continue }
                let t = tsSec[k]
                if WhoopSubstrateGates.isAsleep(tsSec: t, morningSleep: mainSleepUntrimmed, tonightSleepOnsetSec: tonightSleepOnsetSec) {
                    continue
                }
                let h = WhoopSubstrateGates.plausibleHrOrZero(hr[k])
                if h > 0 { awakePool.append(Double(h)) }
            }
            guard awakePool.count >= 600,
                  let awakeMed = WhoopMath.median(awakePool),
                  let boutMed = WhoopMath.median(boutHrs),
                  boutMed <= 0.95 * awakeMed else {
                continue
            }

            let tst = min(tib, stillSamples)
            let dipTerm = min(1.0, max(0.0, (awakeMed - boutMed) / max(1e-6, 0.20 * awakeMed)))
            let wearTerm = min(1.0, max(0.0, 1.0 - max(fOff, fChg) / 0.50))
            let conf = min(0.85, max(0.20, 0.20 + 0.30 * dipTerm + 0.25 * covHr + 0.15 * (Double(tst) / Double(tib)) + 0.10 * wearTerm))
            detected.append(WhoopDetectedNap(
                startSec: sSec, endSec: eSec, tstSec: tst,
                medianHr: boutMed, awakeHrBaseline: awakeMed,
                confidence: conf, startsAtRecordEdge: startsAtEdge
            ))
        }
        return detected
    }
}
