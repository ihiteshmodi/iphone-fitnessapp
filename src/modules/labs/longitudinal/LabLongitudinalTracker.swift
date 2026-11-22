import Foundation

public enum LabDriftKind: String, Equatable {
    case psaVelocityHigh
    case egfrRapidDecline
    case globulinRising
    case cortisolDHEARising
    case sustainedElevation
    case labBaselineReset
}

public struct LabDriftFlag: Equatable {
    public let kind: LabDriftKind
    public let message: String
}

public struct LabLongitudinalSummary: Equatable {
    public let latestValue: Double?
    public let unit: String?
    public let previousValue: Double?
    public let baselineValue: Double?
    public let deltaFromPrevious: Double?
    public let percentFromPrevious: Double?
    public let deltaFromBaseline: Double?
    public let percentFromBaseline: Double?
    public let annualizedVelocity: Double?
    public let switchedLab: Bool
    public let activeLab: String?
    public let driftFlags: [LabDriftFlag]
}

public enum LabLongitudinalTracker {
    public static func summarize(marker: LabMarker, history: [LabResult], drawsByID: [Int: LabDrawDraft] = [:]) -> LabLongitudinalSummary? {
        let comparable = history.compactMap { res -> (result: LabResult, val: Double)? in
            guard let v = res.defaultValue ?? (marker.isUnitlessRatio || marker.defaultUnit == nil ? res.value : nil),
                  res.textValue == nil || res.defaultValue != nil else { return nil }
            return (res, v)
        }
        guard let latest = comparable.first else { return nil }

        let latestLab = normalizedLab(drawsByID[latest.result.drawID]?.lab)
        var sameLabSegment: [(result: LabResult, val: Double)] = [latest]
        var switchedLab = false

        for item in comparable.dropFirst() {
            let itemLab = normalizedLab(drawsByID[item.result.drawID]?.lab)
            if let latestLab, let itemLab, latestLab.caseInsensitiveCompare(itemLab) != .orderedSame {
                switchedLab = true
                break
            }
            sameLabSegment.append(item)
        }

        let previous = sameLabSegment.count >= 2 ? sameLabSegment[1] : nil
        let baseline = sameLabSegment.count >= 2 ? sameLabSegment.last : nil

        let deltaPrev = previous.map { latest.val - $0.val }
        let pctPrev = previous.flatMap { $0.val != 0 ? ((latest.val - $0.val) / abs($0.val)) * 100.0 : nil }
        let deltaBase = baseline.map { latest.val - $0.val }
        let pctBase = baseline.flatMap { $0.val != 0 ? ((latest.val - $0.val) / abs($0.val)) * 100.0 : nil }

        let velocity: Double? = previous.flatMap { prev in
            let days = Double(latest.result.date.days(since: prev.result.date))
            guard days >= 30 else { return nil }
            return (latest.val - prev.val) / (days / 365.25)
        }

        var flags: [LabDriftFlag] = []
        if switchedLab {
            flags.append(LabDriftFlag(kind: .labBaselineReset,
                                      message: "New baseline started for \(latestLab ?? "current lab") — cross-lab shifts are not compared directly."))
        }
        if marker.id == "psa", let vel = velocity, vel >= 0.35 {
            flags.append(LabDriftFlag(kind: .psaVelocityHigh,
                                      message: "PSA velocity \(LabInsightsRule.number(vel)) ng/mL/yr meets or exceeds 0.35 ng/mL/yr — review trajectory."))
        }
        if marker.id == "egfr", let vel = velocity, vel <= -5.0 {
            flags.append(LabDriftFlag(kind: .egfrRapidDecline,
                                      message: "Rapid eGFR decline (\(LabInsightsRule.number(vel)) mL/min/1.73m²/yr) — warrants prompt kidney review."))
        }
        if marker.id == "globulin", let db = deltaBase, db >= 0.4, latest.val > 3.2 {
            flags.append(LabDriftFlag(kind: .globulinRising,
                                      message: "Globulin has risen +\(LabInsightsRule.number(db)) g/dL from baseline."))
        }
        if marker.id == "cortisol-dhea-ratio", let pb = pctBase, pb >= 25.0 {
            flags.append(LabDriftFlag(kind: .cortisolDHEARising,
                                      message: "Cortisol:DHEA-S ratio is up +\(LabInsightsRule.number(pb))% vs your personal baseline (rising stress-to-recovery strain)."))
        }
        if marker.id == "hs-crp", let prev = previous {
            let days = latest.result.date.days(since: prev.result.date)
            let illLatest = drawsByID[latest.result.drawID]?.illRecently == true
            let illPrev = drawsByID[prev.result.drawID]?.illRecently == true
            if days >= 14, !illLatest, !illPrev, latest.val >= 1.0, prev.val >= 1.0 {
                flags.append(LabDriftFlag(kind: .sustainedElevation,
                                          message: "hs-CRP ≥ 1.0 mg/L sustained across two consecutive unconfounded draws."))
            }
        }

        return LabLongitudinalSummary(
            latestValue: latest.val,
            unit: marker.defaultUnit,
            previousValue: previous?.val,
            baselineValue: baseline?.val,
            deltaFromPrevious: deltaPrev,
            percentFromPrevious: pctPrev,
            deltaFromBaseline: deltaBase,
            percentFromBaseline: pctBase,
            annualizedVelocity: velocity,
            switchedLab: switchedLab,
            activeLab: latestLab,
            driftFlags: flags)
    }

    private static func normalizedLab(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
