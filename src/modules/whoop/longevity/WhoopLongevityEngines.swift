import Foundation

public enum WhoopVo2MaxEstimator: String, Codable, Equatable, Sendable {
    case nes = "nes"
    case uth = "uth"
}

public enum WhoopLongevityReadiness: String, Codable, Equatable, Sendable {
    case estimate = "estimate"
    case ready = "ready"
}

public struct WhoopLongevityDayInput: Equatable, Sendable {
    public let date: String
    public let restingHr: Double?
    /// Canonical `0–21` Strain (automatically normalized to `0–100` Effort via `(strain / 21.0) * 100.0`).
    public let strain0To21: Double?
    public let sleepMinutes: Double?
    public let rmssdMs: Double?
    public let steps: Double?

    public init(date: String, restingHr: Double?, strain0To21: Double?, sleepMinutes: Double?, rmssdMs: Double?, steps: Double?) {
        self.date = date
        self.restingHr = restingHr
        self.strain0To21 = strain0To21
        self.sleepMinutes = sleepMinutes
        self.rmssdMs = rmssdMs
        self.steps = steps
    }

    public var normalizedEffort0To100: Double? {
        guard let s = strain0To21, s.isFinite else { return nil }
        return min(100.0, max(0.0, (s / 21.0) * 100.0))
    }
}

public struct WhoopFitnessAgeResult: Equatable, Sendable {
    public let vo2MaxMlKgMin: Double
    public let estimator: WhoopVo2MaxEstimator
    public let see: Double
    public let pai: Double
    public let activeDays: Int
    public let medianRhr: Double
    public let fitnessAge: Double
    public let deltaYearsYounger: Double
    public let readiness: WhoopLongevityReadiness
}

public struct WhoopVitalityResult: Equatable, Sendable {
    public let bodyAge: Double
    public let deltaYearsYounger: Double
    public let vitalityScore: Double
    public let netLogHazard: Double
    public let factorHazards: [String: Double]
    public let factorsUsed: Int
}

public enum WhoopLongevityEngines {
    // MARK: - §4.1 `VO2 Max` (`vo2max_est`) & `Fitness Age` (`fitness_age`)

    public static func physicalActivityIndexFromEffort(activeDaysPerWeek: Int, meanActiveEffort0To100: Double) -> Double {
        let f: Double
        switch activeDaysPerWeek {
        case ..<1: f = 0.0
        case 1: f = 0.5
        case 2: f = 1.0
        case 3, 4: f = 2.5
        default: f = 5.0
        }
        guard f > 0 else { return 0.0 }
        return f * min(3.0, max(0.0, meanActiveEffort0To100 / 30.0))
    }

    public static func computeFitnessAge(
        days7: [WhoopLongevityDayInput],
        chronoAge: Double,
        sex: String,
        waistCm: Double?
    ) -> WhoopFitnessAgeResult? {
        let trimmedSex = sex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard chronoAge > 0, !trimmedSex.isEmpty else { return nil }

        let window = Array(days7.suffix(7))
        let rhrs = window.compactMap { d -> Double? in
            guard let r = d.restingHr, r > 0 else { return nil }
            return r
        }
        guard rhrs.count >= 4, let medRhr = WhoopMath.median(rhrs), medRhr > 0 else { return nil }
        let readiness: WhoopLongevityReadiness = rhrs.count >= 6 ? .ready : .estimate

        let activeEfforts = window.compactMap(\.normalizedEffort0To100).filter { $0 >= 30.0 }
        let meanActive = WhoopMath.mean(activeEfforts) ?? 0.0
        let pai = physicalActivityIndexFromEffort(activeDaysPerWeek: activeEfforts.count, meanActiveEffort0To100: meanActive)

        let isFemale = (trimmedSex.lowercased() == "female")
        // Nes et al. 2011 HUNT3 coefficients
        let intercept = isFemale ? 74.74 : 100.27
        let cAge = isFemale ? 0.247 : 0.296
        let cWc = isFemale ? 0.259 : 0.369
        let cRhr = isFemale ? 0.114 : 0.155
        let cPai = isFemale ? 0.198 : 0.226
        let see = isFemale ? 5.14 : 5.70

        let vo2Max: Double
        let estimator: WhoopVo2MaxEstimator
        if let wc = waistCm, wc > 0 {
            vo2Max = intercept - cAge * chronoAge + cPai * pai - cWc * wc - cRhr * medRhr
            estimator = .nes
        } else {
            vo2Max = 15.3 * ((208.0 - 0.7 * chronoAge) / medRhr)
            estimator = .uth
        }

        let rawFitnessAge = chronoAge + (cRhr * (medRhr - 65.0) - cPai * (pai - 5.0)) / cAge
        let fitnessAge = min(80.0, max(20.0, rawFitnessAge))
        return WhoopFitnessAgeResult(
            vo2MaxMlKgMin: vo2Max,
            estimator: estimator,
            see: see,
            pai: pai,
            activeDays: activeEfforts.count,
            medianRhr: medRhr,
            fitnessAge: fitnessAge,
            deltaYearsYounger: chronoAge - fitnessAge,
            readiness: readiness
        )
    }

    /// Reads the latest Waist circumference from `body_measurements` in `fitness.sqlite` and converts to centimeters.
    public static func latestWaistCm(from fitnessDb: Database) throws -> Double? {
        guard let row = try fitnessDb.query("""
            SELECT inches FROM body_measurements
            WHERE site = 'Waist' COLLATE NOCASE
            ORDER BY measured_on DESC, id DESC LIMIT 1
            """).first else {
            return nil
        }
        let unit = try fitnessDb.query("SELECT unit FROM measurement_targets WHERE site = 'Waist' COLLATE NOCASE")
            .first?.optionalText("unit") ?? "in"
        let raw = row.double("inches")
        guard raw > 0 else { return nil }
        return unit == "cm" ? raw : (raw * 2.54)
    }

    // MARK: - §4.2 `Vitality` (`0–100`) & `Body Age` (`body_age`)

    public static func rmssdNorm(forAge age: Double) -> Double {
        let anchors: [(Double, Double)] = [
            (20, 47.0), (30, 40.0), (40, 33.0), (50, 29.0), (60, 25.0), (70, 22.0), (80, 20.0),
        ]
        if age <= anchors.first!.0 { return anchors.first!.1 }
        if age >= anchors.last!.0 { return anchors.last!.1 }
        for i in 1..<anchors.count {
            let (a0, v0) = anchors[i - 1]
            let (a1, v1) = anchors[i]
            if age <= a1 {
                let t = (age - a0) / (a1 - a0)
                return v0 + t * (v1 - v0)
            }
        }
        return 20.0
    }

    public static func sleepConsistency(sleepHours: [Double]) -> Double? {
        let valid = sleepHours.filter { $0 > 0 }
        guard valid.count >= 3 else { return nil }
        let mu = valid.reduce(0, +) / Double(valid.count)
        guard mu > 1e-9 else { return nil }
        let popVar = valid.reduce(0.0) { $0 + ($1 - mu) * ($1 - mu) } / Double(valid.count)
        let sigmaPop = sqrt(popVar)
        return min(1.0, max(0.0, 1.0 - sigmaPop / mu))
    }

    public static func computeVitality(
        days7: [WhoopLongevityDayInput],
        chronoAge: Double,
        vo2MaxPair: (actual: Double, expected: Double)? = nil
    ) -> WhoopVitalityResult? {
        guard chronoAge > 0 else { return nil }
        let window = Array(days7.suffix(7))
        var hazards: [String: Double] = [:]

        let rhrs = window.compactMap { ($0.restingHr ?? 0) > 0 ? $0.restingHr : nil }
        if let medRhr = WhoopMath.median(rhrs) {
            hazards["rhr"] = ((medRhr - 65.0) / 10.0) * 0.100
        }

        if let pair = vo2MaxPair {
            let clamped = min(4.0, max(-4.0, (pair.expected - pair.actual) / 3.5))
            hazards["vo2max"] = clamped * 0.130
        }

        let sleepHours = window.compactMap { d -> Double? in
            guard let m = d.sleepMinutes, m > 0 else { return nil }
            return m / 60.0
        }
        if let meanSleep = WhoopMath.mean(sleepHours) {
            let dev = min(3.0, max(0.0, max(0.0, abs(meanSleep - 7.5) - 0.5)))
            hazards["sleep"] = dev * 0.110
        }
        if let cons = sleepConsistency(sleepHours: sleepHours) {
            hazards["consistency"] = (0.75 - cons) * 0.450
        }

        let hrvVals = window.compactMap { ($0.rmssdMs ?? 0) > 0 ? $0.rmssdMs : nil }
        if let medRmssd = WhoopMath.median(hrvVals) {
            let norm = rmssdNorm(forAge: chronoAge)
            let clamped = min(1.0, max(-1.0, (norm - medRmssd) / norm))
            hazards["hrv"] = clamped * 0.160
        }

        let stepVals = window.compactMap { ($0.steps ?? -1) >= 0 ? $0.steps : nil }
        if let meanSteps = WhoopMath.mean(stepVals) {
            let cappedSteps = min(11_000.0, max(0.0, meanSteps))
            let clamped = min(4.0, max(-4.0, (7000.0 - cappedSteps) / 1000.0))
            hazards["steps"] = clamped * 0.064
        }

        guard hazards.count >= 3 else { return nil }

        let overlapShrink = 0.75
        let lnHazardPerYear = log(2.0) / 8.0
        let netLnH = overlapShrink * hazards.values.reduce(0, +)
        let deltaAge = netLnH / lnHazardPerYear
        let bodyAge = min(90.0, max(20.0, chronoAge + deltaAge))
        let deltaYounger = chronoAge - bodyAge
        let vitality = min(100.0, max(0.0, 50.0 + 2.5 * deltaYounger))

        return WhoopVitalityResult(
            bodyAge: bodyAge,
            deltaYearsYounger: deltaYounger,
            vitalityScore: vitality,
            netLogHazard: netLnH,
            factorHazards: hazards,
            factorsUsed: hazards.count
        )
    }
}

// MARK: - ACSM Treadmill VO2 Max Calculator & Editable Store

public struct TreadmillVo2Draft: Equatable, Sendable {
    public var loggedOn: ISODate
    public var speedKmh: Double
    public var gradePct: Double
    public var durationMin: Double
    public var steadyHr: Int?
    public var restingHr: Int?
    public var maxHr: Int?
    public var notes: String?

    public init(loggedOn: ISODate, speedKmh: Double, gradePct: Double, durationMin: Double,
                steadyHr: Int? = nil, restingHr: Int? = nil, maxHr: Int? = nil, notes: String? = nil) {
        self.loggedOn = loggedOn
        self.speedKmh = speedKmh
        self.gradePct = gradePct
        self.durationMin = durationMin
        self.steadyHr = steadyHr
        self.restingHr = restingHr
        self.maxHr = maxHr
        self.notes = notes
    }
}

public struct TreadmillVo2Log: Identifiable, Equatable, Sendable {
    public let id: Int
    public let loggedOn: ISODate
    public let speedKmh: Double
    public let gradePct: Double
    public let durationMin: Double
    public let steadyHr: Int?
    public let restingHr: Int?
    public let maxHr: Int?
    public let vo2MlKgMin: Double
    public let estimatedVo2Max: Double
    public let notes: String?
}

public final class AcsmTreadmillVo2Service {
    private let db: Database

    public init(_ db: Database) {
        self.db = db
    }

    /// ACSM running metabolic equation:
    /// `VO2 = 0.2 * speed_m_min + 0.9 * speed_m_min * grade + 3.5`
    /// When submaximal (`steadyHr < maxHr` with known `restingHr`), scales via `%HRR`:
    /// `VO2_max = (VO2 - 3.5) / %HRR + 3.5`.
    public static func calculate(
        speedKmh: Double,
        gradePct: Double,
        steadyHr: Int? = nil,
        restingHr: Int? = nil,
        maxHr: Int? = nil
    ) -> (vo2MlKgMin: Double, estimatedVo2Max: Double) {
        let speedMPerMin = (speedKmh * 1000.0) / 60.0
        let grade = max(0.0, gradePct) / 100.0
        let vo2 = 0.2 * speedMPerMin + 0.9 * speedMPerMin * grade + 3.5
        if let shr = steadyHr, let rhr = restingHr, let mhr = maxHr, mhr > rhr, shr > rhr && shr < mhr {
            let hrrFrac = min(1.0, max(0.30, Double(shr - rhr) / Double(mhr - rhr)))
            let estMax = (vo2 - 3.5) / hrrFrac + 3.5
            return (vo2, estMax)
        }
        return (vo2, vo2)
    }

    @discardableResult
    public func addLog(_ draft: TreadmillVo2Draft) throws -> Int {
        try validate(draft)
        let calc = Self.calculate(speedKmh: draft.speedKmh, gradePct: draft.gradePct,
                                  steadyHr: draft.steadyHr, restingHr: draft.restingHr, maxHr: draft.maxHr)
        try db.execute("""
            INSERT INTO treadmill_vo2_logs (
                logged_on, speed_kmh, grade_pct, duration_min, steady_hr, resting_hr, max_hr,
                vo2_ml_kg_min, estimated_vo2max, notes
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(draft.loggedOn.string), .double(draft.speedKmh), .double(draft.gradePct),
                .double(draft.durationMin), .optional(draft.steadyHr), .optional(draft.restingHr),
                .optional(draft.maxHr), .double(calc.vo2MlKgMin), .double(calc.estimatedVo2Max),
                .optional(Self.clean(draft.notes)),
            ])
        return db.lastInsertRowID
    }

    public func updateLog(id: Int, _ draft: TreadmillVo2Draft) throws {
        try validate(draft)
        guard !(try db.query("SELECT 1 FROM treadmill_vo2_logs WHERE id = ?", [.int(Int64(id))])).isEmpty else {
            throw ValidationError("Treadmill log not found")
        }
        let calc = Self.calculate(speedKmh: draft.speedKmh, gradePct: draft.gradePct,
                                  steadyHr: draft.steadyHr, restingHr: draft.restingHr, maxHr: draft.maxHr)
        try db.execute("""
            UPDATE treadmill_vo2_logs SET
                logged_on = ?, speed_kmh = ?, grade_pct = ?, duration_min = ?, steady_hr = ?,
                resting_hr = ?, max_hr = ?, vo2_ml_kg_min = ?, estimated_vo2max = ?, notes = ?
            WHERE id = ?
            """, [
                .text(draft.loggedOn.string), .double(draft.speedKmh), .double(draft.gradePct),
                .double(draft.durationMin), .optional(draft.steadyHr), .optional(draft.restingHr),
                .optional(draft.maxHr), .double(calc.vo2MlKgMin), .double(calc.estimatedVo2Max),
                .optional(Self.clean(draft.notes)), .int(Int64(id)),
            ])
    }

    public func deleteLog(id: Int) throws {
        try db.execute("DELETE FROM treadmill_vo2_logs WHERE id = ?", [.int(Int64(id))])
    }

    public func logs() throws -> [TreadmillVo2Log] {
        try db.query("SELECT * FROM treadmill_vo2_logs ORDER BY logged_on DESC, id DESC").compactMap { row in
            guard let day = ISODate(row.text("logged_on")) else { return nil }
            return TreadmillVo2Log(
                id: row.int("id"),
                loggedOn: day,
                speedKmh: row.double("speed_kmh"),
                gradePct: row.double("grade_pct"),
                durationMin: row.double("duration_min"),
                steadyHr: row.optionalInt("steady_hr"),
                restingHr: row.optionalInt("resting_hr"),
                maxHr: row.optionalInt("max_hr"),
                vo2MlKgMin: row.double("vo2_ml_kg_min"),
                estimatedVo2Max: row.double("estimated_vo2max"),
                notes: row.optionalText("notes")
            )
        }
    }

    private func validate(_ draft: TreadmillVo2Draft) throws {
        guard draft.speedKmh.isFinite && draft.speedKmh > 0 else { throw ValidationError("Speed must be > 0 km/h") }
        guard draft.gradePct.isFinite && draft.gradePct >= 0 else { throw ValidationError("Grade cannot be negative") }
        guard draft.durationMin.isFinite && draft.durationMin > 0 else { throw ValidationError("Duration must be > 0 min") }
    }

    private static func clean(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
