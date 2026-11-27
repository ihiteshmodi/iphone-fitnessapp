import Foundation

// MARK: - Part 5.1 & 5.2: Guided Breathing, Biofeedback, Spectral Coherence, Stress Curve & Alertness Forecast

public enum WhoopBreathPhaseKind: String, Codable, Equatable, Sendable {
    case inhale = "inhale"
    case holdIn = "hold_in"
    case exhale = "exhale"
    case holdOut = "hold_out"
    case guided = "guided"

    public var displayTitle: String {
        switch self {
        case .inhale: return "Inhale"
        case .holdIn: return "Hold"
        case .exhale: return "Exhale"
        case .holdOut: return "Hold"
        case .guided: return "Breathe"
        }
    }

    public var hapticLoops: UInt8 {
        switch self {
        case .inhale: return 1
        case .exhale: return 2
        case .holdIn, .holdOut, .guided: return 0
        }
    }

    public var toneFrequencyHz: Double? {
        switch self {
        case .inhale: return 440.0
        case .exhale: return 330.0
        case .holdIn, .holdOut, .guided: return nil
        }
    }
}

public struct WhoopBreathStage: Equatable, Sendable {
    public let kind: WhoopBreathPhaseKind
    public let durationMs: Int
    public let label: String?

    public init(_ kind: WhoopBreathPhaseKind, _ durationMs: Int, label: String? = nil) {
        self.kind = kind
        self.durationMs = max(0, durationMs)
        self.label = label
    }
}

public enum WhoopBreathCategory: String, CaseIterable, Equatable, Sendable {
    case ans = "ANS & Calm"
    case presence = "Presence"
    case biofeedback = "Biofeedback"
    case guided = "Guided"
}

public struct WhoopBreathPhaseSnapshot: Equatable, Sendable {
    public let kind: WhoopBreathPhaseKind
    public let label: String
    public let stageIndex: Int
    public let stageProgress: Double
    public let cycleNumber: Int
    public let hapticLoops: UInt8
}

public struct WhoopBreathProtocol: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let category: WhoopBreathCategory
    public let stages: [WhoopBreathStage]
    public let defaultDurationSec: Int
    public let coherenceRated: Bool

    public var cycleDurationMs: Int {
        stages.reduce(0) { $0 + $1.durationMs }
    }

    public var breathsPerMinute: Double? {
        let ms = cycleDurationMs
        guard ms > 0 else { return nil }
        return 60_000.0 / Double(ms)
    }

    public var pacedHz: Double? {
        let ms = cycleDurationMs
        guard ms > 0 else { return nil }
        return 1_000.0 / Double(ms)
    }

    public func phaseAt(elapsedMs: Int) -> WhoopBreathPhaseSnapshot {
        let total = cycleDurationMs
        guard total > 0, !stages.isEmpty else {
            return WhoopBreathPhaseSnapshot(
                kind: .guided, label: title, stageIndex: 0, stageProgress: 0.5, cycleNumber: 1, hapticLoops: 0
            )
        }
        let clamped = max(0, elapsedMs)
        let cycleNum = (clamped / total) + 1
        let inCycle = clamped % total
        var acc = 0
        for (idx, st) in stages.enumerated() {
            let nextAcc = acc + st.durationMs
            if inCycle < nextAcc || idx == stages.count - 1 {
                let frac = st.durationMs > 0 ? Double(inCycle - acc) / Double(st.durationMs) : 1.0
                return WhoopBreathPhaseSnapshot(
                    kind: st.kind,
                    label: st.label ?? st.kind.displayTitle,
                    stageIndex: idx,
                    stageProgress: min(1.0, max(0.0, frac)),
                    cycleNumber: cycleNum,
                    hapticLoops: st.kind.hapticLoops
                )
            }
            acc = nextAcc
        }
        return WhoopBreathPhaseSnapshot(kind: .inhale, label: "Inhale", stageIndex: 0, stageProgress: 0, cycleNumber: 1, hapticLoops: 1)
    }
}

public enum WhoopBreathProtocolCatalog {
    public static func dynamicResonance(breathsPerMin: Double) -> WhoopBreathProtocol {
        let clamped = min(12.0, max(3.0, breathsPerMin))
        let cycleMs = Int((60_000.0 / clamped).rounded())
        let inhaleMs = Int((0.40 * Double(cycleMs)).rounded())
        let exhaleMs = max(500, cycleMs - inhaleMs)
        return WhoopBreathProtocol(
            id: "locked_resonance",
            title: String(format: "Locked Resonance (%.1f)", clamped),
            subtitle: "40:60 RSA baroreflex entrainment",
            category: .biofeedback,
            stages: [.init(.inhale, inhaleMs), .init(.exhale, exhaleMs)],
            defaultDurationSec: 600,
            coherenceRated: true
        )
    }

    public static let all: [WhoopBreathProtocol] = [
        WhoopBreathProtocol(
            id: "physiological_sigh",
            title: "Physiological Sigh",
            subtitle: "Huberman double-inhale + long exhale rapid CO2 offload",
            category: .ans,
            stages: [
                .init(.inhale, 2500, label: "Inhale (nose)"),
                .init(.inhale, 1000, label: "Top-up sip"),
                .init(.exhale, 6500, label: "Long mouth exhale"),
            ],
            defaultDurationSec: 180,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "coherence_5_5",
            title: "Resonance 5.5",
            subtitle: "5.5s inhale / 5.5s exhale · Peak HRV & baroreflex gain",
            category: .biofeedback,
            stages: [.init(.inhale, 5500), .init(.exhale, 5500)],
            defaultDurationSec: 600,
            coherenceRated: true
        ),
        WhoopBreathProtocol(
            id: "four_seven_eight",
            title: "4-7-8 Downshift",
            subtitle: "4s inhale · 7s hold · 8s exhale pre-sleep vagal brake",
            category: .ans,
            stages: [.init(.inhale, 4000), .init(.holdIn, 7000), .init(.exhale, 8000)],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "box_4_4_4_4",
            title: "Box 4-4-4-4",
            subtitle: "Equal 4s inhale · hold · exhale · hold autonomic steadying",
            category: .ans,
            stages: [.init(.inhale, 4000), .init(.holdIn, 4000), .init(.exhale, 4000), .init(.holdOut, 4000)],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "relax_4_6",
            title: "Relax 4-6",
            subtitle: "4s inhale · 6s exhale (6.0 br/min)",
            category: .ans,
            stages: [.init(.inhale, 4000), .init(.exhale, 6000)],
            defaultDurationSec: 300,
            coherenceRated: true
        ),
        WhoopBreathProtocol(
            id: "extended_exhale",
            title: "Long Exhale 4-8",
            subtitle: "1:2 inhale-to-exhale ratio (5.0 br/min)",
            category: .ans,
            stages: [.init(.inhale, 4000), .init(.exhale, 8000)],
            defaultDurationSec: 300,
            coherenceRated: true
        ),
        WhoopBreathProtocol(
            id: "deep_4_2_6",
            title: "Deep 4-2-6",
            subtitle: "4s inhale · 2s hold · 6s exhale",
            category: .ans,
            stages: [.init(.inhale, 4000), .init(.holdIn, 2000), .init(.exhale, 6000)],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "diaphragmatic_4_2_6",
            title: "Diaphragmatic",
            subtitle: "Belly-led 4-2-6 slow nasal breathing",
            category: .ans,
            stages: [.init(.inhale, 4000, label: "Belly out"), .init(.holdIn, 2000), .init(.exhale, 6000, label: "Belly in")],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "coherent_6_6",
            title: "Coherent 6-6",
            subtitle: "6s inhale · 6s exhale (5.0 br/min)",
            category: .biofeedback,
            stages: [.init(.inhale, 6000), .init(.exhale, 6000)],
            defaultDurationSec: 600,
            coherenceRated: true
        ),
        WhoopBreathProtocol(
            id: "nadi_shodhana",
            title: "Alternate Nostril",
            subtitle: "24s dual-nostril cycle",
            category: .ans,
            stages: [
                .init(.inhale, 4000, label: "Inhale left"), .init(.holdIn, 4000), .init(.exhale, 4000, label: "Exhale right"),
                .init(.inhale, 4000, label: "Inhale right"), .init(.holdIn, 4000), .init(.exhale, 4000, label: "Exhale left"),
            ],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "buteyko",
            title: "Buteyko",
            subtitle: "2.5s inhale · 3.5s exhale · 3.5s pause",
            category: .ans,
            stages: [.init(.inhale, 2500), .init(.exhale, 3500), .init(.holdOut, 3500)],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "buteyko_reduced",
            title: "Buteyko Reduced",
            subtitle: "2s inhale · 3s exhale · 4s pause",
            category: .ans,
            stages: [.init(.inhale, 2000), .init(.exhale, 3000), .init(.holdOut, 4000)],
            defaultDurationSec: 900,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "ujjayi",
            title: "Ujjayi",
            subtitle: "4.5s ocean-throat inhale & exhale",
            category: .ans,
            stages: [.init(.inhale, 4500), .init(.exhale, 4500)],
            defaultDurationSec: 600,
            coherenceRated: true
        ),
        WhoopBreathProtocol(
            id: "qigong",
            title: "Qi Gong Breath",
            subtitle: "4.5s · 1.5s · 4.5s · 1.5s harmonic cycle",
            category: .ans,
            stages: [.init(.inhale, 4500), .init(.holdIn, 1500), .init(.exhale, 4500), .init(.holdOut, 1500)],
            defaultDurationSec: 900,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "tummo",
            title: "Tummo",
            subtitle: "Force out · 10s empty · 7s in · 15s full · 7s out",
            category: .ans,
            stages: [
                .init(.exhale, 1000, label: "Force out"), .init(.holdOut, 10000, label: "Hold empty"),
                .init(.inhale, 7000), .init(.holdIn, 15000, label: "Hold full"), .init(.exhale, 7000),
            ],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "bhastrika",
            title: "Bhastrika",
            subtitle: "1s brisk nasal bellows (30 br/min)",
            category: .ans,
            stages: [.init(.inhale, 1000), .init(.exhale, 1000)],
            defaultDurationSec: 300,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "soma",
            title: "Soma",
            subtitle: "2s rhythmic cadence (15 br/min)",
            category: .ans,
            stages: [.init(.inhale, 2000), .init(.exhale, 2000)],
            defaultDurationSec: 600,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "presence_regular",
            title: "Presence Regular",
            subtitle: "3.8s continuous connected breath (no holds)",
            category: .presence,
            stages: [.init(.inhale, 3800), .init(.exhale, 3800)],
            defaultDurationSec: 900,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "presence_mid",
            title: "Presence Mid",
            subtitle: "2.4s connected breath (12.5 br/min)",
            category: .presence,
            stages: [.init(.inhale, 2400), .init(.exhale, 2400)],
            defaultDurationSec: 900,
            coherenceRated: false
        ),
        WhoopBreathProtocol(
            id: "presence_punching",
            title: "Presence Punching",
            subtitle: "1.9s alertness push-through",
            category: .presence,
            stages: [.init(.inhale, 1900), .init(.exhale, 1900)],
            defaultDurationSec: 900,
            coherenceRated: false
        ),
        WhoopBreathProtocol(id: "wim_hof", title: "Wim Hof", subtitle: "Guided cyclic hyperventilation + retention timer", category: .guided, stages: [], defaultDurationSec: 900, coherenceRated: false),
        WhoopBreathProtocol(id: "kapalabhati", title: "Kapalabhati", subtitle: "Guided skull-shining passive inhale timer", category: .guided, stages: [], defaultDurationSec: 300, coherenceRated: false),
        WhoopBreathProtocol(id: "holotropic", title: "Holotropic", subtitle: "Guided open awareness timer", category: .guided, stages: [], defaultDurationSec: 900, coherenceRated: false),
    ]
}

// MARK: - McCraty Spectral Cardiac Coherence (`cardiacCoherence`) & Live RMSSD Proxy

public struct WhoopCardiacCoherenceResult: Equatable, Sendable {
    public let score: Double          // 0..100
    public let peakHz: Double
    public let ratio: Double
    public let confidence: Double
    public let onPace: Bool
}

public enum WhoopCardiacCoherenceEngine {
    public static func liveRmssdProxy(rrMs: [Int]) -> (rmssd: Double, fraction: Double, label: String)? {
        let tail = Array(rrMs.suffix(30)).filter { $0 >= 250 && $0 <= 2400 }
        guard tail.count >= 4 else { return nil }
        var sumSq = 0.0
        for i in 1..<tail.count {
            let d = Double(tail[i] - tail[i - 1])
            sumSq += d * d
        }
        let rmssd = sqrt(sumSq / Double(tail.count - 1))
        let frac = min(1.0, max(0.0, rmssd / 120.0))
        let label: String
        if rmssd < 20 { label = "Building" }
        else if rmssd < 45 { label = "Settling" }
        else if rmssd < 80 { label = "Coherent" }
        else { label = "Deep calm" }
        return (rmssd, frac, label)
    }

    /// McCraty & Zayas (2014) Lomb–Scargle PSD coherence on 400-point grid (`0.04..0.26 Hz` peak window `±0.015 Hz`).
    public static func compute(rrMs: [Double], rrTsMs: [Int64], pacedHz: Double? = nil) -> WhoopCardiacCoherenceResult? {
        let n = min(rrMs.count, rrTsMs.count)
        guard n >= 20 else { return nil }

        var cleanT: [Double] = []
        var cleanY: [Double] = []
        let t0 = Double(rrTsMs[0]) / 1000.0
        for i in 0..<n where rrMs[i] >= 250.0 && rrMs[i] <= 2400.0 {
            cleanT.append(Double(rrTsMs[i]) / 1000.0 - t0)
            cleanY.append(rrMs[i])
        }
        guard cleanY.count >= 20, let spanSec = cleanT.last, spanSec >= 30.0 else { return nil }

        let meanY = cleanY.reduce(0, +) / Double(cleanY.count)
        let centered = cleanY.map { $0 - meanY }
        let variance = centered.reduce(0.0) { $0 + $1 * $1 } / Double(centered.count)
        guard variance > 1e-6 else { return nil }

        let gridCount = 400
        let fLo = min(0.04, max(0.0033, 1.0 / spanSec))
        let fHi = 0.40
        let df = (fHi - fLo) / Double(gridCount - 1)

        var freqs = [Double](repeating: 0, count: gridCount)
        var psd = [Double](repeating: 0, count: gridCount)

        for g in 0..<gridCount {
            let f = fLo + Double(g) * df
            freqs[g] = f
            let w = 2.0 * Double.pi * f
            var sin2wt = 0.0
            var cos2wt = 0.0
            for t in cleanT {
                sin2wt += sin(2.0 * w * t)
                cos2wt += cos(2.0 * w * t)
            }
            let tau = atan2(sin2wt, cos2wt) / (2.0 * w)
            var yc = 0.0, ys = 0.0, cc = 0.0, ss = 0.0
            for i in 0..<cleanT.count {
                let arg = w * (cleanT[i] - tau)
                let c = cos(arg)
                let s = sin(arg)
                yc += centered[i] * c
                ys += centered[i] * s
                cc += c * c
                ss += s * s
            }
            let p = 0.5 * ((cc > 1e-9 ? (yc * yc / cc) : 0) + (ss > 1e-9 ? (ys * ys / ss) : 0)) / variance
            psd[g] = max(0.0, p)
        }

        // Dominant peak inside [0.04, 0.26] Hz
        var bestIdx = -1
        var bestVal = -1.0
        for g in 0..<gridCount where freqs[g] >= 0.04 && freqs[g] <= 0.26 {
            if psd[g] > bestVal {
                bestVal = psd[g]
                bestIdx = g
            }
        }
        guard bestIdx >= 0 else { return nil }
        let peakHz = freqs[bestIdx]

        // Trapezoidal integration for peak window (±0.015 Hz) and total [fLo..0.40]
        var pPeak = 0.0
        var pTot = 0.0
        for g in 1..<gridCount {
            let fMid = 0.5 * (freqs[g - 1] + freqs[g])
            let area = 0.5 * (psd[g - 1] + psd[g]) * df
            pTot += area
            if fMid >= max(fLo, peakHz - 0.015) && fMid <= min(fHi, peakHz + 0.015) {
                pPeak += area
            }
        }
        let denom = pTot - pPeak
        guard denom > 1e-9 else { return nil }
        let ratio = pPeak / denom
        let score = (100.0 * ratio) / (ratio + 1.0)
        let onPace = pacedHz.map { abs(peakHz - $0) < 0.02 } ?? true
        let spanFactor = min(1.0, max(0.3, spanSec / 180.0))
        let conf = min(0.9, max(0.2, spanFactor * (onPace ? 1.0 : 0.85)))

        return WhoopCardiacCoherenceResult(score: score, peakHz: peakHz, ratio: ratio, confidence: conf, onPace: onPace)
    }
}

// MARK: - L1 Resonance Sweep & L2 `HRDownPacer` (`Calm Me`)

public enum WhoopHrDownPacer {
    public static let calmTargetBpm: Double = 60.0
    public static let hrFloorBpm: Double = 50.0
    public static let maxDurationSec: Int = 180

    public static func rampedDelta(elapsedSec: Double) -> Double {
        3.0 + 5.0 * min(1.0, max(0.0, elapsedSec / 120.0))
    }

    public static func targetBpm(currentHr: Double, elapsedSec: Double) -> Double {
        let delta = rampedDelta(elapsedSec: elapsedSec)
        return min(max(hrFloorBpm, currentHr - delta), max(hrFloorBpm, currentHr - 1.0))
    }

    public static func intervalMs(currentHr: Double, elapsedSec: Double) -> Int {
        let t = targetBpm(currentHr: currentHr, elapsedSec: elapsedSec)
        return Int((60_000.0 / max(40.0, t)).rounded())
    }
}

public enum WhoopResonanceSweepEngine {
    public static let quickRatesBpm: [Double] = [6.5, 5.5, 4.5]
    public static let fullRatesBpm: [Double] = [4.5, 5.0, 5.5, 6.0, 6.5, 7.0]

    public static func scorePace(bpm: Double, rrMs: [Double], beatTsSec: [Double]) -> Double? {
        let n = min(rrMs.count, beatTsSec.count)
        guard n >= 12, let t0 = beatTsSec.first else { return nil }
        let cycleSec = 60.0 / bpm
        var byCycle: [Int: [Double]] = [:]
        for i in 0..<n {
            let rel = beatTsSec[i] - t0
            guard rel >= 30.0, rrMs[i] > 300.0 && rrMs[i] < 2000.0 else { continue }
            let idx = Int((rel - 30.0) / cycleSec)
            byCycle[idx, default: []].append(60_000.0 / rrMs[i])
        }
        let swings = byCycle.values.compactMap { ihrs -> Double? in
            guard ihrs.count >= 2, let hi = ihrs.max(), let lo = ihrs.min() else { return nil }
            return hi - lo
        }
        guard swings.count >= 3 else { return nil }
        return swings.reduce(0, +) / Double(swings.count)
    }
}

// MARK: - 24-Hour Baevsky Stress Index Curve

public struct WhoopHourlyStressPoint: Identifiable, Equatable, Sendable {
    public var id: Int { hour }
    public let hour: Int
    public let label: String
    public let score: Double
    public let isAsleep: Bool
}

public enum WhoopStressCurveEngine {
    /// Baevsky Stress Index mapped onto `0..100`: `100 * ln(clamp(SI, 5, 600) / 5) / ln(600 / 5)`.
    public static func baevskyStressScore(rrMs: [Double]) -> Double? {
        let clean = rrMs.filter { $0 >= 300.0 && $0 <= 2200.0 }
        guard clean.count >= 15 else { return nil }
        let sorted = clean.sorted()
        let p5 = sorted[max(0, Int(Double(sorted.count - 1) * 0.05))]
        let p95 = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
        let mxdmnSec = max(0.020, (p95 - p5) / 1000.0)

        // 50 ms histogram bins for Mode (Mo) and Mode Amplitude (AMo %)
        var bins: [Int: Int] = [:]
        for v in clean {
            let b = Int((v / 50.0).rounded())
            bins[b, default: 0] += 1
        }
        guard let bestBin = bins.max(by: { $0.value < $1.value }) else { return nil }
        let moSec = max(0.30, (Double(bestBin.key) * 50.0) / 1000.0)
        let amoPct = (Double(bestBin.value) / Double(clean.count)) * 100.0

        let si = amoPct / (2.0 * moSec * mxdmnSec)
        let clampedSi = min(600.0, max(5.0, si))
        return 100.0 * log(clampedSi / 5.0) / log(600.0 / 5.0)
    }

    public static func build24HourCurve(
        whoopDb: Database,
        day: ISODate,
        rhr: Double,
        maxHr: Double,
        sleepSpan: (onsetSec: Int64, offsetSec: Int64)?,
        calendar: Calendar = .current
    ) throws -> [WhoopHourlyStressPoint] {
        guard let bounds = WhoopSubstrateGates.calendarDayBounds(for: day, calendar: calendar) else { return [] }
        let rrRows = try whoopDb.query(
            "SELECT rec_ts, rr_ms FROM decoded_rr WHERE rec_ts >= ? AND rec_ts < ?",
            [.int(bounds.dayStartSec), .int(bounds.dayEndSec)]
        )
        var rrByHour: [Int: [Double]] = [:]
        for r in rrRows {
            let ts = r.int("rec_ts")
            let dt = Date(timeIntervalSince1970: TimeInterval(ts))
            let hrOfDay = calendar.component(.hour, from: dt)
            if let v = r.optionalInt("rr_ms") {
                rrByHour[hrOfDay, default: []].append(Double(v))
            }
        }

        let hrRows = try whoopDb.query(
            "SELECT rec_ts, hr FROM decoded_onehz WHERE rec_ts >= ? AND rec_ts < ? AND hr IS NOT NULL",
            [.int(bounds.dayStartSec), .int(bounds.dayEndSec)]
        )
        var bpmByHour: [Int: [Int]] = [:]
        for r in hrRows {
            let b = WhoopSubstrateGates.plausibleHrOrZero(r.optionalInt("hr"))
            guard b > 0 else { continue }
            let hrOfDay = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(r.int("rec_ts"))))
            bpmByHour[hrOfDay, default: []].append(b)
        }

        var points: [WhoopHourlyStressPoint] = []
        for h in 0..<24 {
            let midSec = bounds.dayStartSec + Int64(h * 3600 + 1800)
            let asleep = sleepSpan.map { midSec >= $0.onsetSec && midSec <= $0.offsetSec } ?? (h < 7)
            if let beats = rrByHour[h], let siScore = baevskyStressScore(rrMs: beats) {
                points.append(WhoopHourlyStressPoint(hour: h, label: String(format: "%02d", h), score: siScore, isAsleep: asleep))
            } else if let bpms = bpmByHour[h], !bpms.isEmpty {
                let meanBpm = Double(bpms.reduce(0, +)) / Double(bpms.count)
                let hrr = min(1.0, max(0.0, (meanBpm - rhr) / max(20.0, maxHr - rhr)))
                points.append(WhoopHourlyStressPoint(hour: h, label: String(format: "%02d", h), score: min(100.0, max(5.0, hrr * 95.0 + 8.0)), isAsleep: asleep))
            }
        }
        return points
    }
}

// MARK: - Three-Process Alertness Forecast (`alertnessForecast`, Spec §5.2.3)

public struct WhoopAlertnessPoint: Identifiable, Equatable, Sendable {
    public var id: Int { stepIndex }
    public let stepIndex: Int
    public let clockLabel: String
    public let value: Double // Strictly unitless [0, 1]
}

public struct WhoopAlertnessForecast: Equatable, Sendable {
    public let points: [WhoopAlertnessPoint]
    public let troughLabel: String
    public let confidence: Double
}

public enum WhoopAlertnessForecastEngine {
    public static func compute(
        wakeLocalHour: Double?,
        sleepDurationHours: Double?,
        napsLocalHours: [(startHour: Double, endHour: Double)] = [],
        circadianAcrophaseHours: Double = 16.8
    ) -> WhoopAlertnessForecast? {
        guard let wakeH = wakeLocalHour, let sleepDur = sleepDurationHours, sleepDur > 0 else { return nil }
        let sUpper = 14.3
        let sLower = 2.4
        let tauW = 1.0 / 0.0353
        let tauS = 1.0 / 0.3813
        let cAmp = 2.5
        let wInertia = 5.72
        let tauInertia = 0.67
        let dt = 0.25

        let horizonHours = max(3.0, min(18.0, 24.0 - sleepDur))
        let steps = Int((horizonHours / dt).rounded())
        guard steps >= 12 else { return nil }

        var s = sUpper - (sUpper - sLower) * exp(-sleepDur / tauS)
        var rawA: [Double] = []
        var clockHours: [Double] = []

        for i in 0...steps {
            let elapsed = Double(i) * dt
            let clock = (wakeH + elapsed).truncatingRemainder(dividingBy: 24.0)
            if i > 0 {
                let inNap = napsLocalHours.contains { clock >= $0.startHour && clock < $0.endHour }
                if inNap {
                    s = sUpper - (sUpper - s) * exp(-dt / tauS)
                } else {
                    s = sLower + (s - sLower) * exp(-dt / tauW)
                }
            }
            let c = cAmp * cos(2.0 * Double.pi * (clock - circadianAcrophaseHours) / 24.0)
            let u = -0.5 - 0.5 * cos(2.0 * Double.pi * (clock - (circadianAcrophaseHours - 3.0)) / 12.0)
            let w = wInertia * exp(-elapsed / tauInertia)
            rawA.append(s + c + u - w)
            clockHours.append(clock < 0 ? clock + 24.0 : clock)
        }

        guard let minA = rawA.min(), let maxA = rawA.max(), (maxA - minA) > 1e-9 else { return nil }
        let norm = rawA.map { ($0 - minA) / (maxA - minA) }

        // Lowest 2.0h (8-step) window after first 1.0h (step >= 4)
        var bestStart = 4
        var bestSum = Double.greatestFiniteMagnitude
        if norm.count >= 13 {
            for start in 4...(norm.count - 8) {
                let sum = norm[start..<(start + 8)].reduce(0, +)
                if sum < bestSum {
                    bestSum = sum
                    bestStart = start
                }
            }
        }
        let tStart = clockHours[min(bestStart, clockHours.count - 1)]
        let tEnd = (tStart + 2.0).truncatingRemainder(dividingBy: 24.0)
        let troughText = "\(formatHour(tStart)) – \(formatHour(tEnd))"

        let pts = norm.enumerated().map { idx, val in
            WhoopAlertnessPoint(stepIndex: idx, clockLabel: formatHour(clockHours[idx]), value: val)
        }
        return WhoopAlertnessForecast(points: pts, troughLabel: troughText, confidence: 0.35)
    }

    private static func formatHour(_ h: Double) -> String {
        let totalMin = Int((h * 60.0).rounded()) % 1440
        return String(format: "%02d:%02d", totalMin / 60, totalMin % 60)
    }
}

// MARK: - 7-Day Wake Consistency & Nap Compliance Evaluator

public struct WhoopWakeConsistencyReport: Equatable, Sendable {
    public let wakeStdDevMinutes: Int
    public let withinThirtyMinTarget: Bool
    public let weekendDriftMinutes: Int
    public let weekendJetLagFlagged: Bool
    public let summaryText: String
}

public struct WhoopNapComplianceReport: Equatable, Sendable {
    public let compliant: Bool
    public let badgeText: String
    public let guidanceText: String
}

public enum WhoopWakeAndNapComplianceEngine {
    public static func evaluateWakeConsistency(_ wakes: [(isWeekend: Bool, wakeMinuteOfDay: Int)]) -> WhoopWakeConsistencyReport {
        guard wakes.count >= 2 else {
            return WhoopWakeConsistencyReport(
                wakeStdDevMinutes: 0, withinThirtyMinTarget: true, weekendDriftMinutes: 0,
                weekendJetLagFlagged: false, summaryText: "Collecting 7-day wake timestamps (target ≤30m variance)."
            )
        }
        let mins = wakes.map { Double($0.wakeMinuteOfDay) }
        let sd = Int((WhoopMath.sampleStdDev(mins) ?? 0).rounded())
        let weekdayWakes = wakes.filter { !$0.isWeekend }.map { Double($0.wakeMinuteOfDay) }
        let weekendWakes = wakes.filter { $0.isWeekend }.map { Double($0.wakeMinuteOfDay) }
        let drift: Int
        if let wdMean = WhoopMath.mean(weekdayWakes), let weMean = WhoopMath.mean(weekendWakes) {
            drift = Int(abs(weMean - wdMean).rounded())
        } else {
            drift = 0
        }
        let jetLag = drift >= 120
        let within30 = sd <= 30 && !jetLag
        let text: String
        if jetLag {
            text = "Social Jet Lag: weekend wake shifted by \(drift)m (≥2h) — anchor wake within ±30m."
        } else if within30 {
            text = "7d wake variance ±\(sd)m (within ≤30m circadian anchor ✓)."
        } else {
            text = "7d wake variance ±\(sd)m — tighten daily wake toward ±30m."
        }
        return WhoopWakeConsistencyReport(
            wakeStdDevMinutes: sd,
            withinThirtyMinTarget: within30,
            weekendDriftMinutes: drift,
            weekendJetLagFlagged: jetLag,
            summaryText: text
        )
    }

    public static func evaluateNap(durationMin: Int, startMinuteOfDay: Int, sleepDeprived: Bool) -> WhoopNapComplianceReport {
        if !sleepDeprived {
            if durationMin <= 22 && startMinuteOfDay < 14 * 60 {
                return WhoopNapComplianceReport(
                    compliant: true,
                    badgeText: "Power nap ✓",
                    guidanceText: "<20m before 14:00 clears adenosine without sleep inertia."
                )
            }
            return WhoopNapComplianceReport(
                compliant: false,
                badgeText: startMinuteOfDay >= 14 * 60 ? "After 14:00" : ">20m standard",
                guidanceText: "On well-slept days keep naps <20m before 14:00 so tonight's sleep pressure stays intact."
            )
        } else {
            let validDur = durationMin <= 35 || (durationMin >= 80 && durationMin <= 100)
            if validDur && startMinuteOfDay < 13 * 60 {
                return WhoopNapComplianceReport(
                    compliant: true,
                    badgeText: "Recovery nap ✓",
                    guidanceText: "Sleep-deprived \(durationMin)m recovery nap before 13:00 credits tonight's sleep need."
                )
            }
            return WhoopNapComplianceReport(
                compliant: false,
                badgeText: startMinuteOfDay >= 13 * 60 ? "Past 13:00" : "Mid-SWS risk",
                guidanceText: "When sleep-deprived, take a 30m or 90m full-cycle nap before 13:00 to avoid slow-wave inertia."
            )
        }
    }
}

// MARK: - 20+ Physiological Variables Trend Explorer Service

public struct WhoopMetricDefinition: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let unit: String
    public let category: String
}

public struct WhoopMetricTrendPoint: Identifiable, Equatable, Sendable {
    public var id: String { date }
    public let date: String
    public let value: Double
}

public struct WhoopMetricTrendBundle: Equatable, Sendable {
    public let definition: WhoopMetricDefinition
    public let points: [WhoopMetricTrendPoint]
    public let median28d: Double?
    public let bandLow: Double?
    public let bandHigh: Double?
}

public enum WhoopMetricsExplorerService {
    /// Complete 22-variable physiological catalogue (`>= 20` variables required by checklist).
    public static let catalogue: [WhoopMetricDefinition] = [
        .init(id: "rmssd", title: "HRV (rMSSD)", unit: "ms", category: "Autonomic"),
        .init(id: "hrv_cv", title: "HRV Stability (CV)", unit: "%", category: "Autonomic"),
        .init(id: "sdnn", title: "Whole-Sleep SDNN", unit: "ms", category: "Autonomic"),
        .init(id: "lf_hf", title: "LF / HF Autonomic Ratio", unit: "ratio", category: "Autonomic"),
        .init(id: "rhr", title: "Nocturnal RHR", unit: "bpm", category: "Autonomic"),
        .init(id: "dip_pct", title: "Overnight HR Dip", unit: "%", category: "Autonomic"),
        .init(id: "hrr_bpm", title: "Heart Rate Recovery (HRR)", unit: "bpm", category: "Cardio"),
        .init(id: "hrr_tau_s", title: "HRR Decay Tau", unit: "s", category: "Cardio"),
        .init(id: "tst_min", title: "Total Sleep Duration", unit: "min", category: "Sleep"),
        .init(id: "deep_min", title: "Deep Sleep (SWS)", unit: "min", category: "Sleep"),
        .init(id: "rem_min", title: "REM Sleep", unit: "min", category: "Sleep"),
        .init(id: "light_min", title: "Light Sleep", unit: "min", category: "Sleep"),
        .init(id: "efficiency", title: "Sleep Efficiency", unit: "%", category: "Sleep"),
        .init(id: "awakenings", title: "Sustained Awakenings", unit: "count", category: "Sleep"),
        .init(id: "resp_rate", title: "RSA Respiratory Rate", unit: "br/min", category: "Respiratory"),
        .init(id: "brv_cv", title: "Breathing Variability (CV)", unit: "%", category: "Respiratory"),
        .init(id: "steps", title: "Filtered Daily Steps", unit: "steps", category: "Activity"),
        .init(id: "active_min", title: "Movement / Active Minutes", unit: "min", category: "Activity"),
        .init(id: "calories", title: "Active Energy", unit: "kcal", category: "Energy"),
        .init(id: "calories_total", title: "Total Daily Energy", unit: "kcal", category: "Energy"),
        .init(id: "strain", title: "Daily Strain (0–21)", unit: "score", category: "Load"),
        .init(id: "skin_temp_adc", title: "Nightly Skin Temperature", unit: "°C / °F", category: "Wellness"),
        .init(id: "stress", title: "Nocturnal Stress Index", unit: "0–100", category: "Wellness"),
        .init(id: "worn_min", title: "Daily Wear Time", unit: "min", category: "Hardware"),
    ]

    public static func loadTrend(
        whoopDb: Database,
        metricId: String,
        startDate: ISODate,
        endDate: ISODate,
        tempUnit: TemperatureUnitPreference = .celsius
    ) throws -> WhoopMetricTrendBundle {
        let def = catalogue.first { $0.id == metricId } ?? .init(id: metricId, title: metricId, unit: "", category: "Other")
        let allRows = try whoopDb.query(
            "SELECT date, value FROM metric_series WHERE key = ? AND value IS NOT NULL ORDER BY date ASC",
            [.text(metricId)]
        )

        func normalize(_ raw: Double) -> Double {
            if metricId == "efficiency" && raw <= 1.05 && raw > 0 { return raw * 100.0 }
            if metricId == "skin_temp_adc" {
                let c = raw > 100.0 ? (raw / 100.0) : raw
                return tempUnit.convert(celsius: c)
            }
            return raw
        }

        let allPts: [WhoopMetricTrendPoint] = allRows.compactMap { r in
            guard let v = r.optionalDouble("value"), v.isFinite else { return nil }
            return WhoopMetricTrendPoint(date: r.text("date"), value: normalize(v))
        }

        let windowPts = allPts.filter { $0.date >= startDate.string && $0.date <= endDate.string }
        let baselineVals = Array(allPts.filter { $0.date <= endDate.string }.suffix(28).map(\.value))
        let med = WhoopMath.median(baselineVals)
        let madScaled: Double? = {
            guard let m = med, baselineVals.count >= 4 else { return nil }
            let devs = baselineVals.map { abs($0 - m) }
            guard let mad = WhoopMath.median(devs) else { return nil }
            return max(0.01, 1.4826 * mad)
        }()

        return WhoopMetricTrendBundle(
            definition: def,
            points: windowPts,
            median28d: med,
            bandLow: (med != nil && madScaled != nil) ? (med! - madScaled!) : nil,
            bandHigh: (med != nil && madScaled != nil) ? (med! + madScaled!) : nil
        )
    }
}
