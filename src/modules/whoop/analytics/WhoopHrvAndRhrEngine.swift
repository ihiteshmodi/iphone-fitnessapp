import Foundation

public enum WhoopBeatClass: String, Equatable, Sendable {
    case normal
    case ectopic
    case missed
    case extra
    case longShort
    case gap
}

public struct WhoopCorrectedRrResult: Equatable, Sendable {
    public let nnMs: [Double]
    public let nnTsMs: [Int64]
    public let segmentBreaks: Set<Int> // indices in nnMs where a dropped multi-beat run or >32 gap preceded nnMs[idx]
    public let classifications: [WhoopBeatClass]
    public let cleanFraction: Double
    public let artifactFraction: Double
}

public struct WhoopHeadlineRmssdDetail: Equatable, Sendable {
    public let rmssd: Double?
    public let lnRmssd: Double?
    public let confidence: Double?
    public let keptWindows: Int
    public let totalWindows: Int
    public let overCounted: Bool
    public let acf1: Double?
    public let noiseShare: Double?
    public let rescuedBySteadyBreathing: Bool
}

public struct WhoopNocturnalRhrResult: Equatable, Sendable {
    public let low30Mean: Double
    public let nadirP1: Double
}

public enum WhoopHrvAndRhrEngine {
    public static let alpha: Double = 5.2
    public static let windowBeats: Int = 91
    public static let minThresholdMs: Double = 100.0
    public static let reanchorGapMs: Double = 1000.0
    public static let maxArtifactRun: Int = 32
    public static let rrCoverageMinSpanSec: Double = 600.0
    public static let rrCoverageCeiling: Double = 1.10
    public static let nnDiffAcf1Floor: Double = -0.35
    public static let nnDiffNoiseShareCeiling: Double = 0.70
    public static let minDiffsPerRmssdWindow: Int = 20

    // MARK: - §3.2.1 Lipponen & Tarvainen (2019) + Peltola (2012) `correctRr`

    public static func correctRr(rrMs: [Double], rrTsMs: [Int64]) -> WhoopCorrectedRrResult {
        let n = min(rrMs.count, rrTsMs.count)
        guard n > 0 else {
            return WhoopCorrectedRrResult(nnMs: [], nnTsMs: [], segmentBreaks: [], classifications: [], cleanFraction: 0, artifactFraction: 1)
        }
        let monoTs = WhoopSubstrateGates.monotonizeBeatAxis(Array(rrTsMs.prefix(n)))

        // 1. Gap-aware beat clock (`_beatTimes`)
        let origin = Double(monoTs[0]) - rrMs[0]
        var tAll = [Double](repeating: 0, count: n)
        var cur = rrMs[0]
        tAll[0] = origin + cur
        for i in 1..<n {
            let wallStep = Double(monoTs[i] - monoTs[i - 1])
            let anchored = Double(monoTs[i]) - origin
            if (wallStep - rrMs[i]) > reanchorGapMs && anchored > cur {
                cur = anchored
            } else {
                cur += rrMs[i]
            }
            tAll[i] = origin + cur
        }

        // 2. Sliding dispersion thresholds (w = 91, h = 45)
        let h = windowBeats / 2
        var dRr = [Double](repeating: 0, count: n)
        for i in 1..<n { dRr[i] = rrMs[i] - rrMs[i - 1] }

        var med = [Double](repeating: 0, count: n)
        var mRr = [Double](repeating: 0, count: n)
        var th1 = [Double](repeating: minThresholdMs, count: n)
        for i in 0..<n {
            let lo = max(0, i - h)
            let hi = min(n - 1, i + h)
            let dWin = Array(dRr[lo...hi])
            th1[i] = max(alpha * WhoopMath.quartileDeviation(dWin), minThresholdMs)

            var loo: [Double] = []
            loo.reserveCapacity(hi - lo)
            for k in lo...hi where k != i { loo.append(rrMs[k]) }
            let localMed = WhoopMath.median(loo) ?? rrMs[i]
            med[i] = localMed
            let diff = rrMs[i] - localMed
            mRr[i] = diff < 0 ? (2.0 * diff) : diff
        }

        var th2 = [Double](repeating: minThresholdMs, count: n)
        for i in 0..<n {
            let lo = max(0, i - h)
            let hi = min(n - 1, i + h)
            th2[i] = max(alpha * WhoopMath.quartileDeviation(Array(mRr[lo...hi])), minThresholdMs)
        }

        // 3. Beat classification & compensatory pair demotion
        var classes = [WhoopBeatClass](repeating: .normal, count: n)
        for i in 0..<n {
            let v = rrMs[i]
            if v > 2000.0 || (abs(mRr[i]) > th2[i] && mRr[i] > 0) {
                classes[i] = v > 1.5 * med[i] ? .missed : .longShort
            } else if v < 300.0 || (abs(mRr[i]) > th2[i] && mRr[i] < 0) {
                classes[i] = v < 0.6 * med[i] ? .extra : .longShort
            } else if abs(dRr[i]) > th1[i] {
                classes[i] = .ectopic
            } else {
                classes[i] = .normal
            }
        }
        // Compensatory / post-artifact recovery beat demotion: ectopic following non-normal returning to within 20% of local median
        for k in 1..<n where classes[k] == .ectopic && classes[k - 1] != .normal {
            let oppositeStep = (dRr[k] * dRr[k - 1] < 0) || ((rrMs[k - 1] - med[k - 1]) * dRr[k] < 0)
            if oppositeStep && rrMs[k] >= 300.0 && rrMs[k] <= 2000.0 && abs(rrMs[k] - med[k]) <= 0.20 * med[k] {
                classes[k] = .normal
            }
        }

        // 4. Capped run split (>32 -> .gap) & Peltola correction policy
        var idx = 0
        while idx < n {
            if classes[idx] == .normal { idx += 1; continue }
            var end = idx
            while end < n && classes[end] != .normal { end += 1 }
            if (end - idx) > maxArtifactRun {
                for j in idx..<end { classes[j] = .gap }
            }
            idx = end
        }

        var nnMs: [Double] = []
        var nnTsMs: [Int64] = []
        var breaks: Set<Int> = []
        var pendingBreak = false

        var i = 0
        while i < n {
            if classes[i] == .normal {
                if pendingBreak && !nnMs.isEmpty { breaks.insert(nnMs.count) }
                pendingBreak = false
                nnMs.append(rrMs[i])
                nnTsMs.append(Int64(tAll[i].rounded()))
                i += 1
            } else {
                var end = i
                while end < n && classes[end] != .normal { end += 1 }
                let runLen = end - i
                if runLen == 1 {
                    // Isolated single artifact: Catmull-Rom cubic spline at t = 0.5 using up to 2 normal neighbors each side
                    let leftNormals = (0..<i).reversed().filter { classes[$0] == .normal }.prefix(2)
                    let rightNormals = (end..<n).filter { classes[$0] == .normal }.prefix(2)
                    if let l1 = leftNormals.first, let r1 = rightNormals.first {
                        let p1 = rrMs[l1]
                        let p0 = leftNormals.count > 1 ? rrMs[leftNormals[leftNormals.index(after: leftNormals.startIndex)]] : p1
                        let p2 = rrMs[r1]
                        let p3 = rightNormals.count > 1 ? rrMs[rightNormals[rightNormals.index(after: rightNormals.startIndex)]] : p2
                        let interp = 0.5 * (2.0 * p1 + (-p0 + p2) * 0.5 + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * 0.25 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * 0.125)
                        if pendingBreak && !nnMs.isEmpty { breaks.insert(nnMs.count) }
                        pendingBreak = false
                        nnMs.append(min(2000.0, max(300.0, interp)))
                        nnTsMs.append(Int64(tAll[i].rounded()))
                    } else {
                        pendingBreak = true
                    }
                } else {
                    // Multi-beat artifact run (>= 2): drop all beats in run; mark seam break for downstream differences.
                    pendingBreak = true
                }
                i = end
            }
        }

        let normalCount = classes.filter { $0 == .normal }.count
        let cleanFrac = Double(normalCount) / Double(n)
        let artFrac = min(1.0, max(0.0, 1.0 - cleanFrac))
        return WhoopCorrectedRrResult(
            nnMs: nnMs, nnTsMs: nnTsMs, segmentBreaks: breaks,
            classifications: classes, cleanFraction: cleanFrac, artifactFraction: artFrac
        )
    }

    // MARK: - §3.2.2 & §3.2.3 Overcount, ACF1 / RSA Jitter Gate & Canonical 5-Min Headline RMSSD

    public static func rrCoverage(rrMs: [Double], rrTsMs: [Int64]) -> (coverage: Double?, overCounted: Bool) {
        let n = min(rrMs.count, rrTsMs.count)
        guard n >= 2 else { return (nil, false) }
        var sumSec = 0.0
        var firstPlausible: Double?
        var minTs = Int64.max
        var maxTs = Int64.min
        for i in 0..<n {
            let v = rrMs[i]
            guard v >= 300.0 && v <= 2400.0 else { continue }
            if firstPlausible == nil { firstPlausible = v }
            sumSec += v / 1000.0
            minTs = min(minTs, rrTsMs[i])
            maxTs = max(maxTs, rrTsMs[i])
        }
        guard let first = firstPlausible, maxTs > minTs else { return (nil, false) }
        let spanSec = Double(maxTs - minTs) / 1000.0 + first / 1000.0
        guard spanSec >= rrCoverageMinSpanSec else { return (sumSec / max(1.0, spanSec), false) }
        let cov = sumSec / spanSec
        return (cov, cov > rrCoverageCeiling)
    }

    public static func nnDiffAcf1(runs: [[Double]]) -> Double? {
        let diffs: [[Double]] = runs.compactMap { run in
            guard run.count >= 2 else { return nil }
            return (1..<run.count).map { run[$0] - run[$0 - 1] }
        }
        let allDiffs = diffs.flatMap { $0 }
        guard allDiffs.count >= 30, let grandMean = WhoopMath.mean(allDiffs) else { return nil }
        var num = 0.0
        var den = 0.0
        for dRun in diffs {
            for k in 0..<dRun.count {
                let c = dRun[k] - grandMean
                den += c * c
                if k >= 1 {
                    num += (dRun[k - 1] - grandMean) * c
                }
            }
        }
        guard den > 1e-12 else { return 0 }
        return num / den
    }

    public static func sleepSessionRmssdDetail(rrMs: [Double], rrTsMs: [Int64], startSec: Int64, endSec: Int64) -> WhoopHeadlineRmssdDetail {
        let n = min(rrMs.count, rrTsMs.count)
        guard n > 0, endSec > startSec else {
            return WhoopHeadlineRmssdDetail(rmssd: nil, lnRmssd: nil, confidence: nil, keptWindows: 0, totalWindows: 0,
                                            overCounted: false, acf1: nil, noiseShare: nil, rescuedBySteadyBreathing: false)
        }

        // Slice to [startSec, endSec)
        var sRr: [Double] = []
        var sTs: [Int64] = []
        for i in 0..<n {
            let tsSec = Int64((Double(rrTsMs[i]) / 1000.0).rounded())
            if tsSec >= startSec && tsSec < endSec {
                sRr.append(rrMs[i])
                sTs.append(rrTsMs[i])
            }
        }
        let monoTs = WhoopSubstrateGates.monotonizeBeatAxis(sTs)
        let wholeCov = rrCoverage(rrMs: sRr, rrTsMs: monoTs)
        if wholeCov.overCounted {
            return WhoopHeadlineRmssdDetail(rmssd: nil, lnRmssd: nil, confidence: nil, keptWindows: 0, totalWindows: 0,
                                            overCounted: true, acf1: nil, noiseShare: nil, rescuedBySteadyBreathing: false)
        }

        let numBins = max(1, Int((endSec - startSec + 299) / 300))
        var binsRr = [[Double]](repeating: [], count: numBins)
        var binsTs = [[Int64]](repeating: [], count: numBins)
        for i in 0..<sRr.count {
            let tsSec = Int64((Double(monoTs[i]) / 1000.0).rounded())
            let idx = Int((tsSec - startSec) / 300)
            if idx >= 0 && idx < numBins {
                binsRr[idx].append(sRr[i])
                binsTs[idx].append(monoTs[i])
            }
        }

        struct WindowStat {
            let rmssd: Double
            let runs: [[Double]]
        }

        var windows: [WindowStat] = []
        var pooledRuns: [[Double]] = []

        for b in 0..<numBins {
            let wRr = binsRr[b]
            let wTs = binsTs[b]
            guard !wRr.isEmpty else { continue }
            let winStartSec = startSec + Int64(b * 300)
            let winSec = Double(min(Int64(300), endSec - winStartSec))
            let bankedMs = wRr.filter { $0 >= 300.0 && $0 <= 2400.0 }.reduce(0, +)
            let overhangMs = wRr.first ?? 0
            if bankedMs > 1.10 * (winSec * 1000.0 + overhangMs) { continue }

            // _cleanWindowRuns: keep 300..2000ms + 4-neighbor Malik 0.20 filter + break on dropped beat or >1000ms gap
            var plausibleVals: [Double] = []
            var plausibleTs: [Int64] = []
            var plausibleOrigIdx: [Int] = []
            for k in 0..<wRr.count where wRr[k] >= 300.0 && wRr[k] <= 2000.0 {
                plausibleVals.append(wRr[k])
                plausibleTs.append(wTs[k])
                plausibleOrigIdx.append(k)
            }
            guard plausibleVals.count >= 5 else { continue }

            var keepMask = [Bool](repeating: true, count: plausibleVals.count)
            for k in 0..<plausibleVals.count {
                var neighbors: [Double] = []
                for d in [-2, -1, 1, 2] {
                    let nk = k + d
                    if nk >= 0 && nk < plausibleVals.count { neighbors.append(plausibleVals[nk]) }
                }
                if let nMed = WhoopMath.median(neighbors), nMed > 0 {
                    if abs(plausibleVals[k] - nMed) / nMed > 0.20 {
                        keepMask[k] = false
                    }
                }
            }

            var runs: [[Double]] = []
            var currentRun: [Double] = []
            var lastTs: Int64?
            var lastOrig: Int?
            for k in 0..<plausibleVals.count {
                guard keepMask[k] else {
                    if currentRun.count >= 2 { runs.append(currentRun) }
                    currentRun = []
                    lastTs = nil
                    lastOrig = nil
                    continue
                }
                let gapBreak: Bool
                if let lt = lastTs, let lo = lastOrig {
                    gapBreak = (plausibleOrigIdx[k] != lo + 1) || (Double(plausibleTs[k] - lt) > plausibleVals[k] + 1000.0)
                } else {
                    gapBreak = false
                }
                if gapBreak {
                    if currentRun.count >= 2 { runs.append(currentRun) }
                    currentRun = [plausibleVals[k]]
                } else {
                    currentRun.append(plausibleVals[k])
                }
                lastTs = plausibleTs[k]
                lastOrig = plausibleOrigIdx[k]
            }
            if currentRun.count >= 2 { runs.append(currentRun) }

            var sqSum = 0.0
            var diffCount = 0
            for r in runs {
                for j in 1..<r.count {
                    let d = r[j] - r[j - 1]
                    sqSum += d * d
                    diffCount += 1
                }
            }
            guard diffCount >= minDiffsPerRmssdWindow else { continue }
            let winRmssd = sqrt(sqSum / Double(diffCount))
            windows.append(WindowStat(rmssd: winRmssd, runs: runs))
            pooledRuns.append(contentsOf: runs)
        }

        guard !windows.isEmpty else {
            return WhoopHeadlineRmssdDetail(rmssd: nil, lnRmssd: nil, confidence: nil, keptWindows: 0, totalWindows: numBins,
                                            overCounted: false, acf1: nil, noiseShare: nil, rescuedBySteadyBreathing: false)
        }

        let acf1 = nnDiffAcf1(runs: pooledRuns)
        var kept = windows
        var noiseShare: Double?
        if let acf1, acf1 < nnDiffAcf1Floor {
            // Slow-HR RSA Spectral Exemption check (64-beat Hann PSD, peak bin < 31, prominence >= 4.5x median)
            let rsaShare = estimateRsaNoiseShare(runs: pooledRuns)
            noiseShare = rsaShare
            if let rsaShare, rsaShare < nnDiffNoiseShareCeiling {
                kept = windows.filter { w in
                    if let s = estimateRsaNoiseShare(runs: w.runs, minSegments: 1) { return s < nnDiffNoiseShareCeiling }
                    return false
                }
            } else {
                kept = []
            }
        }

        guard !kept.isEmpty else {
            return WhoopHeadlineRmssdDetail(rmssd: nil, lnRmssd: nil, confidence: nil, keptWindows: 0, totalWindows: windows.count,
                                            overCounted: false, acf1: acf1, noiseShare: noiseShare, rescuedBySteadyBreathing: false)
        }

        let headline = kept.map(\.rmssd).reduce(0, +) / Double(kept.count)
        let winFactor = min(1.0, max(0.0, Double(kept.count) / 12.0))
        let acfPenalty = (acf1 ?? 0) < 0 ? max(0.30, 1.0 - ((acf1 ?? 0) / nnDiffAcf1Floor)) : 1.0
        let conf = min(0.95, max(0.30, winFactor * acfPenalty))
        return WhoopHeadlineRmssdDetail(
            rmssd: headline,
            lnRmssd: headline > 0 ? log(headline) : nil,
            confidence: conf,
            keptWindows: kept.count,
            totalWindows: windows.count,
            overCounted: false,
            acf1: acf1,
            noiseShare: noiseShare,
            rescuedBySteadyBreathing: false
        )
    }

    private static func estimateRsaNoiseShare(runs: [[Double]], minSegments: Int = 4) -> Double? {
        let segLen = 64
        let step = 32
        var segments: [[Double]] = []
        for r in runs where r.count >= segLen {
            var s = 0
            while s + segLen <= r.count {
                segments.append(Array(r[s..<(s + segLen)]))
                s += step
            }
        }
        guard segments.count >= minSegments else { return nil }
        // Hann window DFT bins k = 10..32 (0.156..0.50 cycles/beat)
        var avgPsd = [Double](repeating: 0, count: 33)
        for seg in segments {
            let m = WhoopMath.mean(seg) ?? 0
            for k in 10...32 {
                var re = 0.0, im = 0.0
                for n in 0..<segLen {
                    let hann = 0.5 * (1.0 - cos(2.0 * .pi * Double(n) / Double(segLen - 1)))
                    let x = (seg[n] - m) * hann
                    let ang = 2.0 * .pi * Double(k * n) / Double(segLen)
                    re += x * cos(ang)
                    im -= x * sin(ang)
                }
                avgPsd[k] += (re * re + im * im) / Double(segLen)
            }
        }
        for k in 10...32 { avgPsd[k] /= Double(segments.count) }
        let band = Array(avgPsd[10...32])
        guard let medBand = WhoopMath.median(band), medBand > 1e-12 else { return nil }
        var peakBin = 10
        for k in 11...32 where avgPsd[k] > avgPsd[peakBin] { peakBin = k }
        // Reject Nyquist alternation (peakBin >= 31 or psd[32] > 0.2 * psd[peak])
        guard peakBin < 31, avgPsd[32] <= 0.2 * avgPsd[peakBin], avgPsd[peakBin] >= 4.5 * medBand else {
            return nil
        }
        let noiseFloor = medBand
        let totalBand = band.reduce(0, +)
        let noiseTotal = Double(band.count) * noiseFloor
        return min(1.0, max(0.0, noiseTotal / max(1e-12, totalBand)))
    }

    // MARK: - Respiration Rate (`rsaRespRate`, Lomb–Scargle 0.15–0.45 Hz) & Stress Score

    public static func rsaRespRate(nnMs: [Double], nnTsMs: [Int64]) -> Double? {
        let n = min(nnMs.count, nnTsMs.count)
        guard n >= 60 else { return nil }
        guard let medBeatMs = WhoopMath.median(nnMs), (0.5 / (medBeatMs / 1000.0)) >= 0.40 else { return nil }

        let startMs = nnTsMs[0]
        let endMs = nnTsMs[n - 1]
        var winPeaksBrpm: [Double] = []
        var wStart = startMs
        while wStart + 300_000 <= endMs {
            let wEnd = wStart + 300_000
            var tSec: [Double] = []
            var vals: [Double] = []
            for i in 0..<n where nnTsMs[i] >= wStart && nnTsMs[i] < wEnd {
                tSec.append(Double(nnTsMs[i] - wStart) / 1000.0)
                vals.append(nnMs[i])
            }
            let coveredSec = vals.reduce(0, +) / 1000.0
            if coveredSec >= 240.0, let m = WhoopMath.mean(vals) {
                let centered = vals.map { $0 - m }
                var bestFreq = 0.25
                var bestPower = -1.0
                var f = 0.15
                while f <= 0.45 {
                    let p = WhoopMath.lombScarglePower(timesSec: tSec, centeredValues: centered, freqHz: f)
                    if p > bestPower { bestPower = p; bestFreq = f }
                    f += 0.005
                }
                winPeaksBrpm.append(bestFreq * 60.0)
            }
            wStart += 150_000
        }
        guard !winPeaksBrpm.isEmpty, let medBrpm = WhoopMath.median(winPeaksBrpm) else { return nil }
        let consensus = winPeaksBrpm.filter { abs($0 - medBrpm) <= 2.0 }.count
        guard Double(consensus) / Double(winPeaksBrpm.count) >= 0.50 else { return nil }
        return medBrpm
    }

    public static func stressScoreFromSi(_ si: Double) -> Double {
        let clamped = min(600.0, max(5.0, si))
        return 100.0 * log(clamped / 5.0) / log(600.0 / 5.0)
    }

    // MARK: - §3.2.4 Nocturnal Resting Heart Rate (`nocturnalRhr`)

    public static func nocturnalRhr(sleepTsSec: [Int64], sleepHr: [Int], tstSec: Int) -> WhoopNocturnalRhrResult? {
        guard tstSec >= WhoopCoreConstants.rhrMinSleepSec else { return nil }
        let n = min(sleepTsSec.count, sleepHr.count)
        guard n >= 1620 else { return nil } // need at least 90% of 1800s

        // Estimate cadence (1.0s on WHOOP)
        var diffs: [Double] = []
        for i in 1..<min(n, 500) {
            let d = sleepTsSec[i] - sleepTsSec[i - 1]
            if d > 0 && d <= 10 { diffs.append(Double(d)) }
        }
        let cadence = max(1.0, WhoopMath.median(diffs) ?? 1.0)
        let perWindow = 1800.0 / cadence
        let minValid = Int(ceil(0.90 * perWindow))

        var lo = 0
        var validCount = 0
        var sumValid = 0.0
        var bestMean: Double?
        var allValidHrs: [Double] = []

        for hi in 0..<n {
            let h = WhoopSubstrateGates.plausibleHrOrZero(sleepHr[hi])
            if h > 0 {
                validCount += 1
                sumValid += Double(h)
                allValidHrs.append(Double(h))
            }
            while lo < hi && Double(sleepTsSec[hi] - sleepTsSec[lo]) >= 1800.0 {
                let lh = WhoopSubstrateGates.plausibleHrOrZero(sleepHr[lo])
                if lh > 0 {
                    validCount -= 1
                    sumValid -= Double(lh)
                }
                lo += 1
            }
            if Double(sleepTsSec[hi] - sleepTsSec[0]) >= (1800.0 - cadence) && validCount >= minValid {
                let m = sumValid / Double(validCount)
                if bestMean == nil || m < bestMean! { bestMean = m }
            }
        }

        guard let low30 = bestMean, let p1 = WhoopMath.percentile(allValidHrs, p: 1.0) else { return nil }
        return WhoopNocturnalRhrResult(low30Mean: low30, nadirP1: p1)
    }
}
