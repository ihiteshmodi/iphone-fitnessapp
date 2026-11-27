import Foundation

public enum WhoopStepSleepContext: Int, Equatable, Sendable {
    case awake = 0
    case wakeInSleepSession = 1
    case asleepStage = 2
}

public struct WhoopStepSample: Equatable, Sendable {
    public let tsSec: Int64
    public let counter: Int
    public let activityClass: Int?
    public let sleepContext: WhoopStepSleepContext

    public init(tsSec: Int64, counter: Int, activityClass: Int?, sleepContext: WhoopStepSleepContext = .awake) {
        self.tsSec = tsSec
        self.counter = counter
        self.activityClass = activityClass
        self.sleepContext = sleepContext
    }
}

public struct WhoopStepCountResult: Equatable, Sendable {
    public let totalTicks: Int
    public let steps: Int
    public let divisorUsed: Double
}

/// Gen5 `step_count` + `activity_class` (`1 = walk`, `2 = run`) + sleep-stage bout coherence step counter.
/// Strictly zero HealthKit / zero phone calibration.
public enum WhoopStepsEngine {
    public static let maxStepDelta: Int = 512
    public static let maxTicksPerSecond: Int = 4
    public static let maxSecondsBetweenGaitDeltas: Int64 = 3

    @inline(__always)
    public static func u16WrapDelta(prev: Int, cur: Int) -> Int {
        (cur - prev) & 0xFFFF
    }

    @inline(__always)
    public static func isPlausibleDelta(_ delta: Int, elapsedSec: Int64) -> Bool {
        guard delta >= 1 && delta < maxStepDelta && elapsedSec > 0 else { return false }
        let cap = elapsedSec >= 128 ? 511 : Int(elapsedSec) * maxTicksPerSecond
        return delta <= cap
    }

    public static func countSteps(samples: [WhoopStepSample], stepTicksPerStep: Double = 1.0) -> WhoopStepCountResult {
        let divisor = min(30.0, max(0.5, stepTicksPerStep))
        guard samples.count >= 2 else {
            return WhoopStepCountResult(totalTicks: 0, steps: 0, divisorUsed: divisor)
        }
        let sorted = samples.sorted { $0.tsSec < $1.tsSec }
        let hasActivityClass = sorted.contains { $0.activityClass != nil }

        var totalTicks = 0
        // Sleep-stage bout coherence buffer (`context == .asleepStage`)
        var boutSamples = 0
        var boutFirstTs: Int64?
        var boutLastTs: Int64?
        var boutTicks = 0

        func flushSleepBout() {
            if let f = boutFirstTs, let l = boutLastTs,
               boutSamples >= 5 && (l - f) >= 4 && boutTicks >= 6 {
                totalTicks += boutTicks
            }
            boutSamples = 0
            boutFirstTs = nil
            boutLastTs = nil
            boutTicks = 0
        }

        // Seed asleep bout anchor if first sample is already in an asleep gait state
        if sorted[0].sleepContext == .asleepStage {
            let classOk = !hasActivityClass || sorted[0].activityClass == 1 || sorted[0].activityClass == 2
            if classOk {
                boutSamples = 1
                boutFirstTs = sorted[0].tsSec
                boutLastTs = sorted[0].tsSec
            }
        }

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let cur = sorted[i]
            guard cur.tsSec > prev.tsSec else { continue }
            let elapsed = cur.tsSec - prev.tsSec
            let delta = u16WrapDelta(prev: prev.counter, cur: cur.counter)

            let classOk: Bool
            if hasActivityClass {
                classOk = (cur.activityClass == 1 || cur.activityClass == 2)
            } else {
                classOk = true
            }

            guard classOk && isPlausibleDelta(delta, elapsedSec: elapsed) else {
                if cur.sleepContext != .asleepStage || (boutLastTs != nil && (cur.tsSec - boutLastTs!) > maxSecondsBetweenGaitDeltas) {
                    flushSleepBout()
                }
                continue
            }

            switch cur.sleepContext {
            case .awake, .wakeInSleepSession:
                flushSleepBout()
                totalTicks += delta
            case .asleepStage:
                if let last = boutLastTs, (cur.tsSec - last) > maxSecondsBetweenGaitDeltas {
                    flushSleepBout()
                }
                if boutFirstTs == nil {
                    // If previous sample was within 3s and asleep, anchor from prev so sample count includes bout start
                    if prev.sleepContext == .asleepStage && elapsed <= maxSecondsBetweenGaitDeltas {
                        boutFirstTs = prev.tsSec
                        boutSamples = 2
                    } else {
                        boutFirstTs = cur.tsSec
                        boutSamples = 1
                    }
                } else {
                    boutSamples += 1
                }
                boutLastTs = cur.tsSec
                boutTicks += delta
            }
        }
        flushSleepBout()

        let steps = Int((Double(totalTicks) / divisor).rounded())
        return WhoopStepCountResult(totalTicks: totalTicks, steps: steps, divisorUsed: divisor)
    }

    /// Reads Gen5 `decoded_onehz` rows for `[startSec, endSec)` directly from `whoop.sqlite` and computes filtered steps.
    public static func countStepsFromDatabase(
        whoopDb: Database,
        startSec: Int64,
        endSec: Int64,
        asleepRanges: [(Int64, Int64)] = [],
        stepTicksPerStep: Double = 1.0
    ) throws -> WhoopStepCountResult {
        let rows = try whoopDb.query("""
            SELECT rec_ts, step_count, activity_class
            FROM decoded_onehz
            WHERE rec_ts >= ? AND rec_ts < ? AND step_count IS NOT NULL
            ORDER BY rec_ts ASC, counter ASC
            """, [.int(startSec), .int(endSec)])

        let samples: [WhoopStepSample] = rows.compactMap { row in
            guard let ts = row.optionalInt64("rec_ts"),
                  let cnt = row.optionalInt("step_count") else { return nil }
            let isAsleep = asleepRanges.contains { ts >= $0.0 && ts < $0.1 }
            return WhoopStepSample(
                tsSec: ts,
                counter: cnt,
                activityClass: row.optionalInt("activity_class"),
                sleepContext: isAsleep ? .asleepStage : .awake
            )
        }
        return countSteps(samples: samples, stepTicksPerStep: stepTicksPerStep)
    }

    public struct StepBreakdown: Equatable, Sendable {
        public let walkSteps: Int
        public let runSteps: Int
        public let unclassedSteps: Int
        public let rejectedNonGaitTicks: Int
        public let zoneSteps: [Int] // [zone0, zone1, zone2, zone3, zone4, zone5]
        public let totalSteps: Int
        public let divisorUsed: Double
    }

    /// Computes a full daily breakdown of Gen5 steps across firmware `activity_class` (`0 = rejected non-gait`, `1 = walk`, `2 = run`)
    /// and Heart Rate Zones `0..5`.
    public static func stepBreakdownFromDatabase(
        whoopDb: Database,
        startSec: Int64,
        endSec: Int64,
        zones: WhoopTrainingZones,
        stepTicksPerStep: Double = 1.0,
        filterGaitOnly: Bool = true
    ) throws -> StepBreakdown {
        let divisor = min(30.0, max(0.5, stepTicksPerStep))
        let rows = try whoopDb.query("""
            SELECT rec_ts, hr, step_count, activity_class
            FROM decoded_onehz
            WHERE rec_ts >= ? AND rec_ts < ? AND step_count IS NOT NULL
            ORDER BY rec_ts ASC, counter ASC
            """, [.int(startSec), .int(endSec)])
        guard rows.count >= 2 else {
            return StepBreakdown(walkSteps: 0, runSteps: 0, unclassedSteps: 0, rejectedNonGaitTicks: 0,
                                 zoneSteps: [0, 0, 0, 0, 0, 0], totalSteps: 0, divisorUsed: divisor)
        }

        let hasActivityClass = rows.contains { $0.optionalInt("activity_class") != nil }
        var walkTicks = 0
        var runTicks = 0
        var unclassedTicks = 0
        var rejectedTicks = 0
        var zTicks = [0, 0, 0, 0, 0, 0]

        for i in 1..<rows.count {
            let prev = rows[i - 1]
            let cur = rows[i]
            let prevTs = Int64(prev.int("rec_ts"))
            let curTs = Int64(cur.int("rec_ts"))
            guard curTs > prevTs,
                  let pCnt = prev.optionalInt("step_count"),
                  let cCnt = cur.optionalInt("step_count") else { continue }
            let delta = u16WrapDelta(prev: pCnt, cur: cCnt)
            guard isPlausibleDelta(delta, elapsedSec: curTs - prevTs) else { continue }

            let cls = cur.optionalInt("activity_class")
            if filterGaitOnly && hasActivityClass && cls == 0 {
                rejectedTicks += delta
                continue
            }

            switch cls {
            case 1: walkTicks += delta
            case 2: runTicks += delta
            default: unclassedTicks += delta
            }

            let bpm = WhoopSubstrateGates.plausibleHrOrZero(cur.optionalInt("hr"))
            let zIdx = bpm > 0 ? WorkoutSessionService.zoneIndex(forBpm: bpm, zones: zones) : 0
            zTicks[zIdx] += delta
        }

        func scale(_ ticks: Int) -> Int { Int((Double(ticks) / divisor).rounded()) }
        let walkS = scale(walkTicks)
        let runS = scale(runTicks)
        let uncS = scale(unclassedTicks)
        return StepBreakdown(
            walkSteps: walkS,
            runSteps: runS,
            unclassedSteps: uncS,
            rejectedNonGaitTicks: rejectedTicks,
            zoneSteps: zTicks.map(scale),
            totalSteps: walkS + runS + uncS,
            divisorUsed: divisor
        )
    }
}
