import Foundation

// MARK: - Recovery 31-Day Rated Bars, Strain Intraday & Zones, OpenStrap-Style Sleep Hypnogram / Ranges / Overnight Signals, and Hourly Steps

public struct WhoopRecoveryDayBar: Identifiable, Equatable, Sendable {
    public var id: String { date }
    public let date: String
    public let shortLabel: String
    public let score: Int
    public let rating: String   // "Good to go" | "Steady" | "Take it easy"
    public let tone: WhoopHoopTone
}

public struct WhoopRecoveryDetailModel: Equatable, Sendable {
    public let bars31d: [WhoopRecoveryDayBar]
    public let usualLow: Int
    public let usualHigh: Int
}

public struct WhoopIntradayPoint: Identifiable, Equatable, Sendable {
    public let id: Int
    public let label: String
    public let value: Double
    public let detail: String
}

public struct WhoopZoneDurationRow: Identifiable, Equatable, Sendable {
    public let id: Int          // 0..5
    public let title: String
    public let bpmRangeText: String
    public let minutes: Int
    public let pctOfTracked: Int
}

public struct WhoopStrainDetailModel: Equatable, Sendable {
    public let date: ISODate
    public let finalStrain: Double
    public let cumulativeCurve: [WhoopIntradayPoint]
    public let zoneRows: [WhoopZoneDurationRow]
    public let totalTrackedWakeMinutes: Int
}

public struct WhoopHypnogramBlock: Identifiable, Equatable, Sendable {
    public let id: Int
    public let startSec: Int64
    public let endSec: Int64
    public let stage: WhoopSleepStage4
    public let timeLabel: String
}

public struct WhoopStageConfidenceRange: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let pointMinutes: Int
    public let lowMinutes: Int
    public let highMinutes: Int
    public let pctText: String
}

public struct WhoopUsualComparisonRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let tonightText: String
    public let usualRangeText: String
    public let deltaBadge: String
    public let pinPosition: Double      // 0..1 across full bar
    public let usualStartFrac: Double   // 0..1
    public let usualEndFrac: Double     // 0..1
    public let inUsualBand: Bool
}

public struct WhoopSleepDetailModel: Equatable, Sendable {
    public let dayId: String
    public let onsetSec: Int64?
    public let offsetSec: Int64?
    public let inBedMinutes: Int
    public let asleepMinutes: Int
    public let efficiencyPct: Int
    public let hypnogramBlocks: [WhoopHypnogramBlock]
    public let stageRanges: [WhoopStageConfidenceRange]
    public let usualComparisons: [WhoopUsualComparisonRow]
    public let hrSignal: [WhoopIntradayPoint]
    public let hrSummary: String
    public let hrvSignal: [WhoopIntradayPoint]
    public let hrvSummary: String
    public let respSignal: [WhoopIntradayPoint]
    public let respSummary: String
    public let tempSignal: [WhoopIntradayPoint]
    public let tempSummary: String
}

public struct WhoopHourlyStepsSlot: Identifiable, Equatable, Sendable {
    public var id: Int { hour }
    public let hour: Int
    public let label: String
    public let zoneSteps: [Int] // [z0, z1, z2, z3, z4, z5]
    public let walkSteps: Int
    public let runSteps: Int
    public let rejectedClass0Ticks: Int

    public func steps(selectedZones: Set<Int>) -> Int {
        selectedZones.reduce(0) { acc, z in
            guard z >= 0 && z < zoneSteps.count else { return acc }
            return acc + zoneSteps[z]
        }
    }
}

public struct WhoopStepsDetailModel: Equatable, Sendable {
    public let date: ISODate
    public let hourlySlots: [WhoopHourlyStepsSlot]
    public let zoneTotals: [Int] // [z0..z5]
    public let walkSteps: Int
    public let runSteps: Int
    public let rejectedNonGaitTicks: Int
    public let divisorUsed: Double
}

public enum WhoopDetailPresenters {
    // MARK: - True Weekly Heart-Rate Zone Minutes (`decoded_onehz` + non-overlapping `workout_sessions`)

    public static func trueWeeklyZoneMinutes(
        whoopDb: Database?,
        fitnessDb: Database?,
        endingOn day: ISODate,
        zones: WhoopTrainingZones,
        calendar: Calendar = .current
    ) throws -> (zone2Minutes: Int, zone4And5Minutes: Int, windowLabel: String) {
        let startDay = day.adding(days: -6)
        let windowLabel = "\(startDay.string.suffix(5)) → \(day.string.suffix(5))"

        var z2MinutesSet: Set<Int64> = []
        var z45MinutesSet: Set<Int64> = []

        if let whoopDb,
           let startBounds = WhoopSubstrateGates.calendarDayBounds(for: startDay, calendar: calendar),
           let endBounds = WhoopSubstrateGates.calendarDayBounds(for: day, calendar: calendar) {
            // Exclude sleep spans so dream REM spikes never count as Zone 2 cardio
            let winRows = try whoopDb.query(
                "SELECT window_json FROM day_result WHERE day_id BETWEEN ? AND ?",
                [.text(startDay.string), .text(day.string)]
            )
            var sleepSpans: [(Int64, Int64)] = []
            for r in winRows {
                if let wj = r.optionalText("window_json"),
                   let obj = (try? JSONSerialization.jsonObject(with: Data(wj.utf8))) as? [String: Any],
                   let onMs = obj["onset_ms"] as? Double,
                   let offMs = obj["offset_ms"] as? Double {
                    sleepSpans.append((Int64(onMs / 1000.0), Int64(offMs / 1000.0)))
                }
            }

            let hrRows = try whoopDb.query("""
                SELECT (rec_ts / 60) AS min_key, AVG(hr) AS avg_hr, COUNT(*) AS n
                FROM decoded_onehz
                WHERE rec_ts >= ? AND rec_ts < ? AND hr >= 25 AND hr <= 230
                GROUP BY (rec_ts / 60)
                """, [.int(startBounds.dayStartSec), .int(endBounds.dayEndSec)])

            for r in hrRows {
                guard r.int("n") >= 15, let avgHr = r.optionalDouble("avg_hr") else { continue }
                let minKey = Int64(r.int("min_key"))
                let secMid = minKey * 60 + 30
                let isAsleep = sleepSpans.contains { secMid >= $0.0 && secMid < $0.1 }
                guard !isAsleep else { continue }

                let bpm = Int(avgHr.rounded())
                let z = WorkoutSessionService.zoneIndex(forBpm: bpm, zones: zones)
                if z == 2 { z2MinutesSet.insert(minKey) }
                else if z >= 4 { z45MinutesSet.insert(minKey) }
            }
        }

        var extraSessionZ2 = 0
        var extraSessionZ45 = 0
        if let fitnessDb {
            let sessions = try WorkoutSessionService(fitnessDb: fitnessDb).sessions().filter {
                $0.performedOn >= startDay && $0.performedOn <= day && $0.endTs != nil && $0.kind != .lifting
            }
            for s in sessions {
                let sMinStart = s.startTs / 60
                let sMinEnd = (s.endTs ?? s.startTs) / 60
                let alreadyCovered = (sMinStart...max(sMinStart, sMinEnd)).contains {
                    z2MinutesSet.contains($0) || z45MinutesSet.contains($0)
                }
                if !alreadyCovered {
                    extraSessionZ2 += s.zoneSeconds[2] / 60
                    extraSessionZ45 += (s.zoneSeconds[4] + s.zoneSeconds[5]) / 60
                }
            }
        }

        return (z2MinutesSet.count + extraSessionZ2, z45MinutesSet.count + extraSessionZ45, windowLabel)
    }

    // MARK: - 1. Recovery 31-Day Rated Bars

    public static func buildRecoveryDetail(whoopDb: Database?, upTo day: ISODate) throws -> WhoopRecoveryDetailModel {
        guard let whoopDb else {
            return WhoopRecoveryDetailModel(bars31d: [], usualLow: 40, usualHigh: 70)
        }
        let rows = try whoopDb.query("""
            SELECT date, value FROM metric_series
            WHERE key = 'readiness' AND date <= ? AND value IS NOT NULL
            ORDER BY date ASC
            """, [.text(day.string)])
        let tail = Array(rows.suffix(31))
        let scores = tail.compactMap { $0.optionalDouble("value") }.map { min(100, max(1, Int($0.rounded()))) }
        let sorted = scores.sorted()
        let lo = sorted.isEmpty ? 40 : sorted[max(0, Int(Double(sorted.count - 1) * 0.20))]
        let hi = sorted.isEmpty ? 72 : sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.80))]

        let bars: [WhoopRecoveryDayBar] = tail.compactMap { r in
            guard let v = r.optionalDouble("value") else { return nil }
            let sc = min(100, max(1, Int(v.rounded())))
            let d = r.text("date")
            let rating: String
            let tone: WhoopHoopTone
            if sc >= 67 {
                rating = "Good to go"
                tone = .green
            } else if sc >= 34 {
                rating = "Steady"
                tone = .amber
            } else {
                rating = "Take it easy"
                tone = .red
            }
            return WhoopRecoveryDayBar(date: d, shortLabel: String(d.suffix(5)), score: sc, rating: rating, tone: tone)
        }
        return WhoopRecoveryDetailModel(bars31d: bars, usualLow: lo, usualHigh: hi)
    }

    // MARK: - 2. Strain Intraday Curve & Cardio Zone Time Breakdown

    public static func buildStrainDetail(
        whoopDb: Database?,
        on day: ISODate,
        zones: WhoopTrainingZones,
        rhr: Double = 53.0,
        isFemale: Bool = false,
        calendar: Calendar = .current
    ) throws -> WhoopStrainDetailModel {
        guard let whoopDb, let bounds = WhoopSubstrateGates.calendarDayBounds(for: day, calendar: calendar) else {
            return WhoopStrainDetailModel(date: day, finalStrain: 0, cumulativeCurve: [], zoneRows: [], totalTrackedWakeMinutes: 0)
        }

        // Exclude sleep window
        var sleepOn: Int64?
        var sleepOff: Int64?
        if let wj = try whoopDb.query("SELECT window_json FROM day_result WHERE day_id = ? ORDER BY algo_version DESC LIMIT 1", [.text(day.string)]).first?.optionalText("window_json"),
           let obj = (try? JSONSerialization.jsonObject(with: Data(wj.utf8))) as? [String: Any] {
            if let onMs = obj["onset_ms"] as? Double { sleepOn = Int64(onMs / 1000.0) }
            if let offMs = obj["offset_ms"] as? Double { sleepOff = Int64(offMs / 1000.0) }
        }

        let rows = try whoopDb.query("""
            SELECT (rec_ts / 60) AS min_key, AVG(hr) AS avg_hr
            FROM decoded_onehz
            WHERE rec_ts >= ? AND rec_ts < ? AND hr >= 25 AND hr <= 230
            GROUP BY (rec_ts / 60)
            ORDER BY min_key ASC
            """, [.int(bounds.dayStartSec), .int(bounds.dayEndSec)])

        var zMinutes = [0, 0, 0, 0, 0, 0]
        var exerciseTrimp = 0.0
        var livingTrimp = 0.0
        let maxHr = Double(max(150, zones.maxHrBpm))
        let q = 0.12
        let rQ = q * WhoopReadinessAndStrainEngine.banisterY(q, isFemale: isFemale)

        var bucketStrainByQuarterHour: [Int: Double] = [:]

        for r in rows {
            let minKey = Int64(r.int("min_key"))
            let sec = minKey * 60
            if let on = sleepOn, let off = sleepOff, sec >= on && sec < off { continue }
            guard let avgHr = r.optionalDouble("avg_hr") else { continue }
            let bpm = Int(avgHr.rounded())
            let z = WorkoutSessionService.zoneIndex(forBpm: bpm, zones: zones)
            zMinutes[z] += 1

            let x = min(1.0, max(0.0, (avgHr - rhr) / max(20.0, maxHr - rhr)))
            let e = x * WhoopReadinessAndStrainEngine.banisterY(x, isFemale: isFemale) - rQ
            if x >= 0.40 { exerciseTrimp += max(0.0, e) } else { livingTrimp += e }

            let net = exerciseTrimp + max(0.0, livingTrimp)
            let curStrain = WhoopReadinessAndStrainEngine.strainFromNetTrimp(net)
            let qIdx = Int(max(0, min(95, (sec - bounds.dayStartSec) / 900)))
            bucketStrainByQuarterHour[qIdx] = curStrain
        }

        let storedStrain = try whoopDb.query("SELECT value FROM metric_series WHERE date = ? AND key = 'strain'", [.text(day.string)])
            .first?.optionalDouble("value")
        let computedEnd = bucketStrainByQuarterHour.values.max() ?? 0.0
        let finalStrain = max(computedEnd, storedStrain ?? 0.0)

        var curve: [WhoopIntradayPoint] = []
        var running = 0.0
        let scale = (computedEnd > 0.1 && finalStrain > computedEnd) ? (finalStrain / computedEnd) : 1.0
        for qIdx in 0..<96 {
            if let v = bucketStrainByQuarterHour[qIdx] {
                running = max(running, v * scale)
            }
            if running > 0 || !curve.isEmpty {
                let totalMin = qIdx * 15
                let lbl = String(format: "%02d:%02d", totalMin / 60, totalMin % 60)
                curve.append(WhoopIntradayPoint(
                    id: qIdx,
                    label: lbl,
                    value: min(21.0, running),
                    detail: String(format: "%@ · Strain %.1f", lbl, min(21.0, running))
                ))
            }
        }

        let trackedTotal = max(1, zMinutes.reduce(0, +))
        let b = zones.boundsBpm
        let labels: [(Int, String, String)] = [
            (5, "Zone 5 · VO2 Peak", "≥\(b[4]) bpm"),
            (4, "Zone 4 · Threshold", "\(b[3])–\(b[4] - 1) bpm"),
            (3, "Zone 3 · Tempo", "\(b[2])–\(b[3] - 1) bpm"),
            (2, "Zone 2 · Aerobic Base", "\(b[1])–\(b[2] - 1) bpm"),
            (1, "Zone 1 · Light", "\(b[0])–\(b[1] - 1) bpm"),
            (0, "Rest / Below Z1", "<\(b[0]) bpm"),
        ]
        let zRows = labels.map { idx, title, rangeText in
            WhoopZoneDurationRow(
                id: idx,
                title: title,
                bpmRangeText: rangeText,
                minutes: zMinutes[idx],
                pctOfTracked: Int((Double(zMinutes[idx]) / Double(trackedTotal) * 100.0).rounded())
            )
        }

        return WhoopStrainDetailModel(
            date: day,
            finalStrain: finalStrain,
            cumulativeCurve: curve,
            zoneRows: zRows,
            totalTrackedWakeMinutes: zMinutes.reduce(0, +)
        )
    }

    // MARK: - 3. OpenStrap-Style Sleep Detail (Hypnogram + Confidence Ranges + Against Your Usual + 4 Overnight Signals)

    public static func buildSleepDetail(
        whoopDb: Database?,
        dayId: String,
        tempUnit: TemperatureUnitPreference,
        calendar: Calendar = .current
    ) throws -> WhoopSleepDetailModel {
        guard let whoopDb else {
            return WhoopSleepDetailModel(
                dayId: dayId, onsetSec: nil, offsetSec: nil, inBedMinutes: 0, asleepMinutes: 0, efficiencyPct: 0,
                hypnogramBlocks: [], stageRanges: [], usualComparisons: [],
                hrSignal: [], hrSummary: "—", hrvSignal: [], hrvSummary: "—",
                respSignal: [], respSummary: "—", tempSignal: [], tempSummary: "—"
            )
        }

        let analyticsStore = WhoopAnalyticsStore(whoopDb)
        let manualOv = try analyticsStore.sleepOverride(for: dayId)

        var onsetSec: Int64? = manualOv?.startTs
        var offsetSec: Int64? = manualOv?.endTs
        if onsetSec == nil || offsetSec == nil {
            if let wj = try whoopDb.query("SELECT window_json FROM day_result WHERE day_id = ? ORDER BY algo_version DESC LIMIT 1", [.text(dayId)]).first?.optionalText("window_json"),
               let obj = (try? JSONSerialization.jsonObject(with: Data(wj.utf8))) as? [String: Any] {
                if onsetSec == nil, let onMs = obj["onset_ms"] as? Double { onsetSec = Int64(onMs / 1000.0) }
                if offsetSec == nil, let offMs = obj["offset_ms"] as? Double { offsetSec = Int64(offMs / 1000.0) }
            }
        }

        // Load day metrics + 28d history for "Against your usual"
        let histRows = try whoopDb.query("""
            SELECT date, key, value FROM metric_series
            WHERE date <= ? AND key IN ('tst_min', 'deep_min', 'rem_min', 'light_min', 'efficiency', 'sleep_onset_sec', 'midsleep_sec', 'resp_rate', 'skin_temp_adc')
            ORDER BY date ASC
            """, [.text(dayId)])
        var byDate: [String: [String: Double]] = [:]
        for r in histRows {
            if let v = r.optionalDouble("value"), v.isFinite {
                byDate[r.text("date"), default: [:]][r.text("key")] = v
            }
        }
        let cur = byDate[dayId] ?? [:]

        let recalc = manualOv?.recalculatedStages
        let tstMin = recalc?.tstMin ?? Int((cur["tst_min"] ?? Double(max(0, ((offsetSec ?? 0) - (onsetSec ?? 0)) / 60))).rounded())
        let deepMin = recalc?.deepMin ?? Int((cur["deep_min"] ?? 0).rounded())
        let remMin = recalc?.remMin ?? Int((cur["rem_min"] ?? 0).rounded())
        let lightMin = recalc?.lightMin ?? max(0, Int((cur["light_min"] ?? Double(max(0, tstMin - deepMin - remMin))).rounded()))
        let effRaw = cur["efficiency"] ?? 0
        let effPct = recalc?.efficiencyPct ?? Int((effRaw <= 1.05 && effRaw > 0 ? effRaw * 100.0 : effRaw).rounded())
        let inBedMin: Int = {
            if let on = onsetSec, let off = offsetSec, off > on { return Int((off - on) / 60) }
            return effPct > 0 ? Int((Double(tstMin) * 100.0 / Double(effPct)).rounded()) : tstMin
        }()
        let awakeMin = max(0, inBedMin - tstMin)

        // Stage hypnogram blocks & overnight signals over [onsetSec, offsetSec]
        var hypnogram: [WhoopHypnogramBlock] = []
        var hrPts: [WhoopIntradayPoint] = []
        var hrvPts: [WhoopIntradayPoint] = []
        var respPts: [WhoopIntradayPoint] = []
        var tempPts: [WhoopIntradayPoint] = []
        var hrSummary = "—"
        var hrvSummary = "—"
        var respSummary = "—"
        var tempSummary = "—"

        if let on = onsetSec, let off = offsetSec, off > on {
            let store = try WhoopStore(whoopDb)
            if let seg = try? store.stageSleepFromSubstrate(onsetSec: on, offsetSec: off, sleepSource: manualOv != nil ? "override" : "auto"),
               !seg.stages4.isEmpty {
                // Coarsen per-second stages4 into 5-minute (300s) blocks for crisp hypnogram rendering
                let blockSec = 300
                let count = max(1, seg.stages4.count / blockSec)
                for b in 0..<count {
                    let s0 = b * blockSec
                    let s1 = min(seg.stages4.count, s0 + blockSec)
                    let slice = seg.stages4[s0..<s1]
                    var tally: [WhoopSleepStage4: Int] = [:]
                    for st in slice where st != .unobserved { tally[st, default: 0] += 1 }
                    let dom = tally.max(by: { $0.value < $1.value })?.key ?? .light
                    let bStart = on + Int64(s0)
                    let bEnd = on + Int64(s1)
                    hypnogram.append(WhoopHypnogramBlock(
                        id: b, startSec: bStart, endSec: bEnd, stage: dom,
                        timeLabel: hm(bStart, calendar: calendar)
                    ))
                }
            }

            // 10-minute (600s) buckets for Overnight Signals (HR, HRV rMSSD, Breathing, Skin Temp)
            let oneHzRows = try whoopDb.query("""
                SELECT (rec_ts / 600) AS b_key, AVG(hr) AS m_hr, MIN(hr) AS min_hr, AVG(skin_temp_c) AS m_tc, AVG(skin_temp_raw) AS m_traw
                FROM decoded_onehz
                WHERE rec_ts >= ? AND rec_ts < ?
                GROUP BY (rec_ts / 600)
                ORDER BY b_key ASC
                """, [.int(on), .int(off)])

            var allSleepHrs: [Double] = []
            var minSleepHr = 999
            var allTempsConv: [Double] = []

            for (idx, r) in oneHzRows.enumerated() {
                let bSec = Int64(r.int("b_key")) * 600
                let lbl = hm(bSec, calendar: calendar)
                if let mHr = r.optionalDouble("m_hr"), mHr >= 25 && mHr <= 220 {
                    allSleepHrs.append(mHr)
                    if let mn = r.optionalInt("min_hr"), mn >= 25 && mn < minSleepHr { minSleepHr = mn }
                    hrPts.append(WhoopIntradayPoint(id: idx, label: lbl, value: mHr, detail: "\(lbl) · \(Int(mHr.rounded())) bpm"))
                }
                let tcOpt: Double? = {
                    if let tc = r.optionalDouble("m_tc"), tc >= 25 && tc <= 42.5 { return tc }
                    if let raw = r.optionalDouble("m_traw"), raw > 1000 && raw < 4500 { return raw / 100.0 }
                    return nil
                }()
                if let tc = tcOpt {
                    let conv = tempUnit.convert(celsius: tc)
                    allTempsConv.append(conv)
                    tempPts.append(WhoopIntradayPoint(id: idx, label: lbl, value: conv, detail: String(format: "%@ · %.1f %@", lbl, conv, tempUnit.label)))
                }
            }
            if !allSleepHrs.isEmpty {
                let avgBpm = Int((allSleepHrs.reduce(0, +) / Double(allSleepHrs.count)).rounded())
                hrSummary = minSleepHr < 250 ? "min \(minSleepHr) · avg \(avgBpm) bpm" : "avg \(avgBpm) bpm"
            }
            if !allTempsConv.isEmpty {
                let avgT = allTempsConv.reduce(0, +) / Double(allTempsConv.count)
                tempSummary = String(format: "avg %.1f %@", avgT, tempUnit.label)
            }

            // RR -> 10-min HRV rMSSD & RSA breathing proxy
            let rrRows = try whoopDb.query("""
                SELECT (rec_ts / 600) AS b_key, rr_ms
                FROM decoded_rr
                WHERE rec_ts >= ? AND rec_ts < ?
                ORDER BY rec_ts ASC, beat_index ASC
                """, [.int(on), .int(off)])
            var rrByBucket: [Int64: [Double]] = [:]
            for r in rrRows {
                if let v = r.optionalInt("rr_ms"), v >= 300 && v <= 2200 {
                    rrByBucket[Int64(r.int("b_key")), default: []].append(Double(v))
                }
            }
            let sortedBuckets = rrByBucket.keys.sorted()
            var hrvVals: [Double] = []
            var respVals: [Double] = []
            let baseResp = cur["resp_rate"] ?? 14.8

            for (idx, bKey) in sortedBuckets.enumerated() {
                guard let beats = rrByBucket[bKey] else { continue }
                let lbl = hm(bKey * 600, calendar: calendar)
                if beats.count >= 6 {
                    var sq = 0.0
                    var cnt = 0
                    var zeroCross = 0
                    var prevDiff: Double?
                    for i in 1..<beats.count {
                        let d = beats[i] - beats[i - 1]
                        if abs(d) <= 220 {
                            sq += d * d
                            cnt += 1
                            if let pd = prevDiff, (pd > 0 && d <= 0) || (pd < 0 && d >= 0) {
                                zeroCross += 1
                            }
                            prevDiff = d
                        }
                    }
                    if cnt >= 4 {
                        let rmssd = sqrt(sq / Double(cnt))
                        hrvVals.append(rmssd)
                        hrvPts.append(WhoopIntradayPoint(id: idx, label: lbl, value: rmssd, detail: "\(lbl) · \(Int(rmssd.rounded())) ms"))

                        let totalSec = beats.reduce(0, +) / 1000.0
                        let estBrpm = totalSec > 20 ? min(22.0, max(9.5, (Double(zeroCross) / 2.0) / (totalSec / 60.0))) : baseResp
                        let blendedResp = 0.65 * baseResp + 0.35 * estBrpm
                        respVals.append(blendedResp)
                        respPts.append(WhoopIntradayPoint(id: idx, label: lbl, value: blendedResp, detail: String(format: "%@ · %.1f br/min", lbl, blendedResp)))
                    }
                } else if let single = beats.first {
                    // Sparse test or gap bucket
                    let estRmssd = max(20.0, (single - 700.0) * 0.18)
                    hrvVals.append(estRmssd)
                    hrvPts.append(WhoopIntradayPoint(id: idx, label: lbl, value: estRmssd, detail: "\(lbl) · \(Int(estRmssd.rounded())) ms"))
                    respPts.append(WhoopIntradayPoint(id: idx, label: lbl, value: baseResp, detail: String(format: "%@ · %.1f br/min", lbl, baseResp)))
                }
            }
            if !hrvVals.isEmpty {
                let avgHrv = Int((hrvVals.reduce(0, +) / Double(hrvVals.count)).rounded())
                let maxHrv = Int((hrvVals.max() ?? 0).rounded())
                hrvSummary = "avg \(avgHrv) · peak \(maxHrv) ms"
            }
            if !respVals.isEmpty {
                let medResp = WhoopMath.median(respVals) ?? baseResp
                respSummary = String(format: "%.1f br/min", medResp)
            } else if let r = cur["resp_rate"] {
                respSummary = String(format: "%.1f br/min", r)
            }

            // Synthesize proportional hypnogram from scored stage totals if raw accel was sparse
            if hypnogram.isEmpty && inBedMin >= 30 {
                let totalBlocks = max(6, min(96, inBedMin / 5))
                let blockDurSec = max(60, Int64((off - on) / Int64(totalBlocks)))
                for b in 0..<totalBlocks {
                    let cyclePos = Double(b % 18) / 18.0
                    let st: WhoopSleepStage4
                    if b == 0 || (awakeMin > 15 && b == totalBlocks / 2) {
                        st = .wake
                    } else if cyclePos < 0.28 && b < (totalBlocks * 2 / 3) && deepMin > 0 {
                        st = .deep
                    } else if cyclePos > 0.72 && remMin > 0 {
                        st = .rem
                    } else {
                        st = .light
                    }
                    let bs = on + Int64(b) * blockDurSec
                    hypnogram.append(WhoopHypnogramBlock(id: b, startSec: bs, endSec: bs + blockDurSec, stage: st, timeLabel: hm(bs, calendar: calendar)))
                }
            }
        }

        // Confidence ranges: optical cardio-staging carries ~±30% 1-sigma uncertainty around point stage counts (DREAMT validation)
        func makeRange(id: String, title: String, mins: Int, spreadFrac: Double) -> WhoopStageConfidenceRange {
            let delta = max(6, Int((Double(mins) * spreadFrac).rounded()))
            let lo = max(0, mins - delta)
            let hi = min(max(inBedMin, mins + delta), mins + delta)
            let pct = inBedMin > 0 ? Int((Double(mins) / Double(inBedMin) * 100.0).rounded()) : 0
            return WhoopStageConfidenceRange(id: id, title: title, pointMinutes: mins, lowMinutes: lo, highMinutes: max(lo + 5, hi), pctText: "\(pct)%")
        }
        let stageRanges: [WhoopStageConfidenceRange] = [
            makeRange(id: "deep", title: "Deep", mins: deepMin, spreadFrac: 0.35),
            makeRange(id: "rem", title: "REM", mins: remMin, spreadFrac: 0.30),
            makeRange(id: "light", title: "Light", mins: lightMin, spreadFrac: 0.20),
            makeRange(id: "awake", title: "Awake", mins: awakeMin, spreadFrac: 0.25),
        ]

        // Concrete "Against Your Usual" (28 prior days p20..p80 range bars)
        let priorDates = byDate.keys.filter { $0 < dayId }.sorted().suffix(28)
        let priorTst = priorDates.compactMap { byDate[$0]?["tst_min"] }.filter { $0 > 60 }
        let priorEff = priorDates.compactMap { d -> Double? in
            guard let e = byDate[d]?["efficiency"], e > 0 else { return nil }
            return e <= 1.05 ? e * 100.0 : e
        }
        let priorRestorative = priorDates.compactMap { d -> Double? in
            guard let dp = byDate[d]?["deep_min"], let rm = byDate[d]?["rem_min"] else { return nil }
            return dp + rm
        }

        var usualRows: [WhoopUsualComparisonRow] = []
        if priorTst.count >= 3 {
            usualRows.append(buildUsualRow(
                id: "duration", title: "Sleep Duration", value: Double(tstMin), history: priorTst,
                formatter: { WhoopDashboardPresenter.formatHoursMinutes(Int($0.rounded())) },
                deltaFormatter: { diff in
                    let m = Int(diff.rounded())
                    return m >= 0 ? "+\(m)m vs med" : "\(m)m vs med"
                }
            ))
        }
        if priorEff.count >= 3 {
            usualRows.append(buildUsualRow(
                id: "efficiency", title: "Efficiency", value: Double(effPct), history: priorEff,
                formatter: { "\(Int($0.rounded()))%" },
                deltaFormatter: { diff in String(format: "%+.0f%% vs med", diff) }
            ))
        }
        if priorRestorative.count >= 3 {
            usualRows.append(buildUsualRow(
                id: "restorative", title: "Deep + REM", value: Double(deepMin + remMin), history: priorRestorative,
                formatter: { WhoopDashboardPresenter.formatHoursMinutes(Int($0.rounded())) },
                deltaFormatter: { diff in
                    let m = Int(diff.rounded())
                    return m >= 0 ? "+\(m)m vs med" : "\(m)m vs med"
                }
            ))
        }

        return WhoopSleepDetailModel(
            dayId: dayId,
            onsetSec: onsetSec,
            offsetSec: offsetSec,
            inBedMinutes: inBedMin,
            asleepMinutes: tstMin,
            efficiencyPct: effPct,
            hypnogramBlocks: hypnogram,
            stageRanges: stageRanges,
            usualComparisons: usualRows,
            hrSignal: hrPts,
            hrSummary: hrSummary,
            hrvSignal: hrvPts,
            hrvSummary: hrvSummary,
            respSignal: respPts,
            respSummary: respSummary,
            tempSignal: tempPts,
            tempSummary: tempSummary
        )
    }

    // MARK: - 4. Hourly Steps & Zone 0..5 Checkmark Calculator

    public static func buildStepsDetail(
        whoopDb: Database?,
        on day: ISODate,
        zones: WhoopTrainingZones,
        stepTicksPerStep: Double = 1.0,
        filterGaitOnly: Bool = true,
        calendar: Calendar = .current
    ) throws -> WhoopStepsDetailModel {
        let divisor = min(30.0, max(0.5, stepTicksPerStep))
        guard let whoopDb, let bounds = WhoopSubstrateGates.calendarDayBounds(for: day, calendar: calendar) else {
            return WhoopStepsDetailModel(
                date: day, hourlySlots: [], zoneTotals: [0, 0, 0, 0, 0, 0],
                walkSteps: 0, runSteps: 0, rejectedNonGaitTicks: 0, divisorUsed: divisor
            )
        }

        let rows = try whoopDb.query("""
            SELECT rec_ts, hr, step_count, activity_class
            FROM decoded_onehz
            WHERE rec_ts >= ? AND rec_ts < ? AND step_count IS NOT NULL
            ORDER BY rec_ts ASC, counter ASC
            """, [.int(bounds.dayStartSec), .int(bounds.dayEndSec)])

        var zTicksByHour = Array(repeating: [0, 0, 0, 0, 0, 0], count: 24)
        var walkTicksByHour = [Int](repeating: 0, count: 24)
        var runTicksByHour = [Int](repeating: 0, count: 24)
        var rejTicksByHour = [Int](repeating: 0, count: 24)

        if rows.count >= 2 {
            let hasClass = rows.contains { $0.optionalInt("activity_class") != nil }
            for i in 1..<rows.count {
                let prev = rows[i - 1]
                let cur = rows[i]
                let pTs = Int64(prev.int("rec_ts"))
                let cTs = Int64(cur.int("rec_ts"))
                guard cTs > pTs,
                      let pCnt = prev.optionalInt("step_count"),
                      let cCnt = cur.optionalInt("step_count") else { continue }
                let delta = WhoopStepsEngine.u16WrapDelta(prev: pCnt, cur: cCnt)
                guard WhoopStepsEngine.isPlausibleDelta(delta, elapsedSec: cTs - pTs) else { continue }

                let h = max(0, min(23, calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(cTs)))))
                let cls = cur.optionalInt("activity_class")
                if filterGaitOnly && hasClass && cls == 0 {
                    rejTicksByHour[h] += delta
                    continue
                }
                if cls == 2 { runTicksByHour[h] += delta } else { walkTicksByHour[h] += delta }

                let bpm = WhoopSubstrateGates.plausibleHrOrZero(cur.optionalInt("hr"))
                let z = bpm > 0 ? WorkoutSessionService.zoneIndex(forBpm: bpm, zones: zones) : 0
                zTicksByHour[h][z] += delta
            }
        }

        func scale(_ ticks: Int) -> Int { Int((Double(ticks) / divisor).rounded()) }

        var slots: [WhoopHourlyStepsSlot] = []
        var zTotals = [0, 0, 0, 0, 0, 0]
        var totalWalk = 0
        var totalRun = 0
        var totalRej = 0

        for h in 0..<24 {
            let zScaled = zTicksByHour[h].map(scale)
            let wS = scale(walkTicksByHour[h])
            let rS = scale(runTicksByHour[h])
            for z in 0..<6 { zTotals[z] += zScaled[z] }
            totalWalk += wS
            totalRun += rS
            totalRej += rejTicksByHour[h]
            slots.append(WhoopHourlyStepsSlot(
                hour: h,
                label: String(format: "%02d:00", h),
                zoneSteps: zScaled,
                walkSteps: wS,
                runSteps: rS,
                rejectedClass0Ticks: rejTicksByHour[h]
            ))
        }

        return WhoopStepsDetailModel(
            date: day,
            hourlySlots: slots,
            zoneTotals: zTotals,
            walkSteps: totalWalk,
            runSteps: totalRun,
            rejectedNonGaitTicks: totalRej,
            divisorUsed: divisor
        )
    }

    // MARK: - Helpers

    private static func buildUsualRow(
        id: String,
        title: String,
        value: Double,
        history: [Double],
        formatter: (Double) -> String,
        deltaFormatter: (Double) -> String
    ) -> WhoopUsualComparisonRow {
        let sorted = history.sorted()
        let p20 = sorted[max(0, Int(Double(sorted.count - 1) * 0.20))]
        let p80 = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.80))]
        let med = WhoopMath.median(sorted) ?? value
        let spanMin = min(sorted.first ?? value, value) - max(1.0, (p80 - p20) * 0.35)
        let spanMax = max(sorted.last ?? value, value) + max(1.0, (p80 - p20) * 0.35)
        let denom = max(1e-6, spanMax - spanMin)

        let pin = min(0.98, max(0.02, (value - spanMin) / denom))
        let u0 = min(0.95, max(0.05, (p20 - spanMin) / denom))
        let u1 = min(0.96, max(u0 + 0.08, (p80 - spanMin) / denom))
        let inBand = (value >= p20 - 1e-6 && value <= p80 + 1e-6)

        return WhoopUsualComparisonRow(
            id: id,
            title: title,
            tonightText: formatter(value),
            usualRangeText: "\(formatter(p20)) – \(formatter(p80))",
            deltaBadge: inBand ? "Typical" : deltaFormatter(value - med),
            pinPosition: pin,
            usualStartFrac: u0,
            usualEndFrac: u1,
            inUsualBand: inBand
        )
    }

    private static func hm(_ epochSec: Int64, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "HH:mm"
        return f.string(from: Date(timeIntervalSince1970: TimeInterval(epochSec)))
    }
}
