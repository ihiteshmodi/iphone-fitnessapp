import Foundation

public struct WhoopSavedWorkoutSpan: Equatable, Sendable {
    public let startSec: Int64
    public let endSec: Int64

    public init(startSec: Int64, endSec: Int64) {
        self.startSec = startSec
        self.endSec = endSec
    }

    public func overlaps(start: Int64, end: Int64) -> Bool {
        startSec <= end && start <= endSec
    }
}

public struct WhoopDetectedWorkout: Identifiable, Equatable, Sendable {
    public var id: String { "\(dayId):\(startSec)" }
    public let dayId: String
    public let startSec: Int64
    public let endSec: Int64
    public let avgBpm: Int
    public let peakBpm: Int
    public let durationMin: Int
    public let meanMotionG: Double?
    public let rescuedByCardiacOnset: Bool
}

/// Exact §3.6.2 Auto-Workout Suggestion Detector (`autoDetectWorkouts`).
/// Surfaces unlogged elevated HR bouts into `activity_suggestions` / `workout_suggestions` — never auto-inserts sessions.
public enum WhoopAutoWorkoutDetector {
    public static let hrrFloorFraction: Double = 0.45
    public static let elevatedMarginBpm: Int = 40
    public static let minSustainedSec: Int64 = 720      // 12 min
    public static let maxWorkoutSec: Int64 = 7200       // 120 min
    public static let maxDipSec: Int64 = 90
    public static let maxGapSec: Int64 = 90
    public static let mergeGapSec: Int64 = 300          // 5 min
    public static let restBridgeMaxSec: Int64 = 900     // 15 min
    public static let restBridgeHrrFraction: Double = 0.15
    public static let motionConfirmMeanG: Double = 0.15
    public static let onsetWindowSec: Int64 = 180
    public static let onsetRiseBpm: Double = 25.0

    public static func detect(
        dayId: String,
        tsSec: [Int64],
        hr: [Int],
        motionIntensityG: [Double?],
        rhr: Int?,
        maxHr: Int?,
        savedSpans: [WhoopSavedWorkoutSpan] = []
    ) -> [WhoopDetectedWorkout] {
        let n = min(tsSec.count, hr.count)
        guard n >= 60, let rhr, let maxHr, maxHr > rhr else { return [] }

        var validPts: [(ts: Int64, bpm: Int, idx: Int)] = []
        for i in 0..<n {
            let b = WhoopSubstrateGates.plausibleHrOrZero(hr[i])
            if b > 0 { validPts.append((tsSec[i], b, i)) }
        }
        guard validPts.count >= 60 else { return [] }
        validPts.sort { $0.ts < $1.ts }

        let floorBpm = max(rhr + elevatedMarginBpm, Int((Double(rhr) + hrrFloorFraction * Double(maxHr - rhr)).rounded()))

        // 1. Span growth with dip & hole guards
        var rawSpans: [(start: Int64, end: Int64)] = []
        var spanStart: Int64?
        var spanEnd: Int64 = 0
        var dipStart: Int64?

        for k in 0..<validPts.count {
            let cur = validPts[k]
            if let s = spanStart, k > 0 && (cur.ts - validPts[k - 1].ts) > maxGapSec {
                if (spanEnd - s) >= minSustainedSec { rawSpans.append((s, spanEnd)) }
                spanStart = nil
                dipStart = nil
            }
            if cur.bpm >= floorBpm {
                if spanStart == nil { spanStart = cur.ts }
                spanEnd = cur.ts
                dipStart = nil
            } else if let s = spanStart {
                if dipStart == nil { dipStart = cur.ts }
                if (cur.ts - dipStart!) > maxDipSec {
                    if (spanEnd - s) >= minSustainedSec { rawSpans.append((s, spanEnd)) }
                    spanStart = nil
                    dipStart = nil
                }
            }
        }
        if let s = spanStart, (spanEnd - s) >= minSustainedSec {
            rawSpans.append((s, spanEnd))
        }
        guard !rawSpans.isEmpty else { return [] }

        // 2. Pass 1 Merge: unconditional short gap < 300s
        var pass1: [(start: Int64, end: Int64)] = [rawSpans[0]]
        for sp in rawSpans.dropFirst() {
            let prev = pass1[pass1.count - 1]
            if (sp.start - prev.end) < mergeGapSec && (sp.end - prev.start) <= maxWorkoutSec {
                pass1[pass1.count - 1] = (prev.start, sp.end)
            } else {
                pass1.append(sp)
            }
        }

        // 3. Pass 2 Merge: observed unrecovered rest bridge (<= 900s)
        struct CandidateWin {
            var start: Int64
            var end: Int64
            var rests: [(Int64, Int64)]
            func inRest(_ t: Int64) -> Bool { rests.contains { t > $0.0 && t < $0.1 } }
        }

        let restFloorBpm = min(floorBpm, Int((Double(rhr) + restBridgeHrrFraction * Double(maxHr - rhr)).rounded()))
        var windows: [CandidateWin] = [CandidateWin(start: pass1[0].start, end: pass1[0].end, rests: [])]
        for sp in pass1.dropFirst() {
            let prev = windows[windows.count - 1]
            let gap = sp.start - prev.end
            if gap <= restBridgeMaxSec && (sp.end - prev.start) <= maxWorkoutSec
                && !savedSpans.contains(where: { $0.overlaps(start: prev.start, end: sp.end) }) {
                let pausePts = validPts.filter { $0.ts >= prev.end && $0.ts <= sp.start }
                let strictlyInside = validPts.filter { $0.ts > prev.end && $0.ts < sp.start }
                var noHole = true
                for j in 1..<pausePts.count where (pausePts[j].ts - pausePts[j - 1].ts) > maxGapSec {
                    noHole = false
                    break
                }
                if noHole, !strictlyInside.isEmpty {
                    let meanPause = Double(strictlyInside.map(\.bpm).reduce(0, +)) / Double(strictlyInside.count)
                    if meanPause >= Double(restFloorBpm) {
                        var merged = prev
                        merged.end = sp.end
                        merged.rests.append((prev.end, sp.start))
                        windows[windows.count - 1] = merged
                        continue
                    }
                }
            }
            windows.append(CandidateWin(start: sp.start, end: sp.end, rests: []))
        }

        // 4. Candidate validation & low-wrist-motion Phase-II cardiac onset bypass
        var detected: [WhoopDetectedWorkout] = []
        for win in windows {
            guard (win.end - win.start) <= maxWorkoutSec else { continue }
            guard !savedSpans.contains(where: { $0.overlaps(start: win.start, end: win.end) }) else { continue }

            let effortPts = validPts.filter { $0.ts >= win.start && $0.ts <= win.end && !win.inRest($0.ts) }
            guard !effortPts.isEmpty else { continue }
            let effortMean = Double(effortPts.map(\.bpm).reduce(0, +)) / Double(effortPts.count)
            guard effortMean >= Double(floorBpm) else { continue }

            var motionVals: [Double] = []
            for p in effortPts where p.idx < motionIntensityG.count {
                if let m = motionIntensityG[p.idx], m.isFinite { motionVals.append(m) }
            }
            let meanMotion = WhoopMath.mean(motionVals)
            var rescued = false
            if let mm = meanMotion, mm < motionConfirmMeanG {
                let onsetEnd = min(win.end + 1, win.start + onsetWindowSec)
                let postPts = validPts.filter { $0.ts >= win.start && $0.ts < onsetEnd }
                let prePts = validPts.filter { $0.ts >= (win.start - onsetWindowSec) && $0.ts < win.start }
                guard !postPts.isEmpty && !prePts.isEmpty else { continue }
                let postMean = Double(postPts.map(\.bpm).reduce(0, +)) / Double(postPts.count)
                let preMean = Double(prePts.map(\.bpm).reduce(0, +)) / Double(prePts.count)
                guard (postMean - preMean) >= onsetRiseBpm else { continue }
                rescued = true
            }

            let allBoutPts = validPts.filter { $0.ts >= win.start && $0.ts <= win.end }
            let avgBpm = Int((Double(allBoutPts.map(\.bpm).reduce(0, +)) / Double(allBoutPts.count)).rounded())
            let peakBpm = allBoutPts.map(\.bpm).max() ?? avgBpm
            detected.append(WhoopDetectedWorkout(
                dayId: dayId,
                startSec: win.start,
                endSec: win.end,
                avgBpm: avgBpm,
                peakBpm: peakBpm,
                durationMin: Int((win.end - win.start) / 60),
                meanMotionG: meanMotion,
                rescuedByCardiacOnset: rescued
            ))
        }
        return detected
    }

    public static func queueProposals(_ workouts: [WhoopDetectedWorkout], into store: WhoopAnalyticsStore, nowSec: Int64) throws {
        let existing = Set(try store.activityProposals().map(\.id))
        for w in workouts where !existing.contains(w.id) {
            let json = """
            {"avg_bpm":\(w.avgBpm),"peak_bpm":\(w.peakBpm),"duration_min":\(w.durationMin),"sport":"detected","rescued_by_onset":\(w.rescuedByCardiacOnset)}
            """
            try store.upsertProposal(WhoopActivityProposal(
                id: w.id,
                kind: "workout",
                dayId: w.dayId,
                startTs: w.startSec,
                endTs: w.endSec,
                detectionStart: w.startSec,
                detectionEnd: w.endSec,
                detailsJson: json,
                status: "pending",
                revision: 0
            ), nowSec: nowSec)
        }
    }
}
