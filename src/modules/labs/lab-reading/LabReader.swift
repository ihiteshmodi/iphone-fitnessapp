import Foundation

public enum LabStatus: Equatable {
    case optimal
    /// Inside some of the vault's optimal bands but not all: the vault disagrees with itself here, so no flag (D1).
    case disputed
    case low
    case high
    /// The marker has no optimal band for this person.
    case noOptimalBand
    /// The typed unit has no factor to the bands' unit.
    case notComparable
}

public enum LabSeverityTier: String, Codable, Equatable {
    case criticalLow
    case suboptimalLow
    case watchLow
    case optimal
    case watchHigh
    case suboptimalHigh
    case high
    case criticalHigh
    case disputed
    case unknown
}

public struct LabReading: Equatable {
    public let value: Double?
    public let unit: String?
    public let status: LabStatus
    public let tier: LabSeverityTier
    public let tierLabel: String?
    public let activeStratum: LabStratum?
    /// Every band (except conditional ones) this value falls in, in catalogue order.
    public let bands: [LabBand]
    public let optimalBands: [LabBand]
    public let disputes: [String]
    /// Both names when the value sits exactly on a boundary two bands share (D3).
    public let edgeLabels: [String]
    /// Every unconditional doctor line crossed, most urgent first (D2).
    public let doctorLines: [LabDoctorLine]
    /// Doctor lines whose numeric threshold was crossed and that require checking paired symptoms.
    public let conditionalDoctorLines: [LabDoctorLine]
    /// Active genotype-driven interpretation notes or target shifts on this marker.
    public let geneticNotes: [String]

    public init(value: Double?, unit: String?, status: LabStatus, tier: LabSeverityTier = .unknown, tierLabel: String? = nil,
                activeStratum: LabStratum? = nil, bands: [LabBand], optimalBands: [LabBand], disputes: [String],
                edgeLabels: [String], doctorLines: [LabDoctorLine], conditionalDoctorLines: [LabDoctorLine] = [],
                geneticNotes: [String] = []) {
        self.value = value
        self.unit = unit
        self.status = status
        self.tier = tier
        self.tierLabel = tierLabel
        self.activeStratum = activeStratum
        self.bands = bands
        self.optimalBands = optimalBands
        self.disputes = disputes
        self.edgeLabels = edgeLabels
        self.doctorLines = doctorLines
        self.conditionalDoctorLines = conditionalDoctorLines
        self.geneticNotes = geneticNotes
    }
}

public struct LabMarkerOverride: Codable, Equatable, Sendable {
    public var markerID: String
    public var optimalLow: Double?
    public var optimalHigh: Double?
    public var unit: String
    public var note: String?

    public init(markerID: String, optimalLow: Double?, optimalHigh: Double?, unit: String, note: String? = nil) {
        self.markerID = markerID
        self.optimalLow = optimalLow
        self.optimalHigh = optimalHigh
        self.unit = unit
        self.note = note
    }
}

public final class LabMarkerOverrideService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func overrides() throws -> [LabMarkerOverride] {
        try db.query("SELECT marker_id, optimal_low, optimal_high, unit, note FROM lab_marker_overrides ORDER BY marker_id").map { row in
            LabMarkerOverride(markerID: row.text("marker_id"), optimalLow: row.optionalDouble("optimal_low"),
                              optimalHigh: row.optionalDouble("optimal_high"), unit: row.text("unit"), note: row.optionalText("note"))
        }
    }

    public func override(for markerID: String) throws -> LabMarkerOverride? {
        try db.query("SELECT marker_id, optimal_low, optimal_high, unit, note FROM lab_marker_overrides WHERE marker_id = ?", [.text(markerID)]).first.map { row in
            LabMarkerOverride(markerID: row.text("marker_id"), optimalLow: row.optionalDouble("optimal_low"),
                              optimalHigh: row.optionalDouble("optimal_high"), unit: row.text("unit"), note: row.optionalText("note"))
        }
    }

    public func setOverride(_ override: LabMarkerOverride) throws {
        guard override.optimalLow != nil || override.optimalHigh != nil else {
            throw ValidationError("Specify at least one optimal bound")
        }
        if let lo = override.optimalLow, let hi = override.optimalHigh, lo > hi {
            throw ValidationError("Optimal low cannot exceed optimal high")
        }
        try db.execute("""
            INSERT INTO lab_marker_overrides (marker_id, optimal_low, optimal_high, unit, note)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(marker_id) DO UPDATE SET
                optimal_low = excluded.optimal_low,
                optimal_high = excluded.optimal_high,
                unit = excluded.unit,
                note = excluded.note
            """, [.text(override.markerID), .optional(override.optimalLow), .optional(override.optimalHigh),
                  .text(override.unit), .optional(override.note)])
    }

    public func deleteOverride(for markerID: String) throws {
        try db.execute("DELETE FROM lab_marker_overrides WHERE marker_id = ?", [.text(markerID)])
    }
}

public enum LabReader {
    public static func read(result: LabResult, marker: LabMarker, preferences: LabPreferences,
                            draw: LabDrawDraft? = nil, genotypes: [GenotypeEntry] = [],
                            personalOverride: LabMarkerOverride? = nil) -> LabReading {
        if marker.id == "blood-pressure", let diastolic = result.secondaryValue {
            return readBloodPressure(systolic: result.value, diastolic: diastolic, marker: marker, sex: preferences.sex)
        }
        if let text = result.textValue, result.defaultValue == nil, marker.units.isEmpty || !marker.bands.filter({ $0.values != nil }).isEmpty {
            return readQualitative(text: text, marker: marker, sex: preferences.sex)
        }
        let ageYears: Int? = preferences.birthDate.map { Int(Double(result.date.days(since: $0)) / 365.25) }
        let base = readInternal(typed: result.value, unit: result.unit, customDefault: result.defaultValue,
                                textValue: result.textValue, labLow: result.labLow, labHigh: result.labHigh,
                                specimen: result.specimen, assay: result.assay, marker: marker,
                                preferences: preferences, ageYears: ageYears, draw: draw)
        let withGenetics = GeneticsModifierEvaluator.applyReadingModifiers(base: base, marker: marker, preferences: preferences, genotypes: genotypes)
        guard let personalOverride else { return withGenetics }
        return applyPersonalOverride(withGenetics, result: result, marker: marker, override: personalOverride)
    }

    private static func applyPersonalOverride(_ base: LabReading, result: LabResult, marker: LabMarker, override: LabMarkerOverride) -> LabReading {
        let valInOverrideUnit: Double?
        if result.unit.caseInsensitiveCompare(override.unit) == .orderedSame {
            valInOverrideUnit = result.value
        } else if let defVal = base.value, let overrideLoInDef = override.optimalLow.flatMap({ marker.toDefault($0, unit: override.unit) }),
                  override.optimalHigh == nil {
            let status: LabStatus = defVal < overrideLoInDef ? .low : .optimal
            return LabReading(value: base.value, unit: base.unit, status: status,
                              tier: status == .low ? .suboptimalLow : .optimal, tierLabel: override.note ?? "Personal target",
                              activeStratum: base.activeStratum, bands: base.bands, optimalBands: base.optimalBands,
                              disputes: base.disputes, edgeLabels: base.edgeLabels, doctorLines: base.doctorLines,
                              conditionalDoctorLines: base.conditionalDoctorLines, geneticNotes: base.geneticNotes)
        } else if let defVal = base.value {
            let loDef = override.optimalLow.flatMap { marker.toDefault($0, unit: override.unit) }
            let hiDef = override.optimalHigh.flatMap { marker.toDefault($0, unit: override.unit) }
            if loDef != nil || hiDef != nil {
                let st: LabStatus
                if let loDef, defVal < loDef { st = .low }
                else if let hiDef, defVal > hiDef { st = .high }
                else { st = .optimal }
                let tier: LabSeverityTier = st == .low ? .suboptimalLow : (st == .high ? .suboptimalHigh : .optimal)
                return LabReading(value: base.value, unit: base.unit, status: st, tier: tier,
                                  tierLabel: override.note ?? "Personal target", activeStratum: base.activeStratum,
                                  bands: base.bands, optimalBands: base.optimalBands, disputes: base.disputes,
                                  edgeLabels: base.edgeLabels, doctorLines: base.doctorLines,
                                  conditionalDoctorLines: base.conditionalDoctorLines, geneticNotes: base.geneticNotes)
            }
            valInOverrideUnit = nil
        } else {
            valInOverrideUnit = nil
        }
        guard let v = valInOverrideUnit else { return base }
        let st: LabStatus
        if let lo = override.optimalLow, v < lo { st = .low }
        else if let hi = override.optimalHigh, v > hi { st = .high }
        else { st = .optimal }
        let tier: LabSeverityTier = st == .low ? .suboptimalLow : (st == .high ? .suboptimalHigh : .optimal)
        return LabReading(value: base.value ?? v, unit: base.unit ?? override.unit, status: st, tier: tier,
                          tierLabel: override.note ?? "Personal target", activeStratum: base.activeStratum,
                          bands: base.bands, optimalBands: base.optimalBands, disputes: base.disputes,
                          edgeLabels: base.edgeLabels, doctorLines: base.doctorLines,
                          conditionalDoctorLines: base.conditionalDoctorLines, geneticNotes: base.geneticNotes)
    }

    public static func read(value typed: Double, unit: String, marker: LabMarker, sex: LabSex) -> LabReading {
        readInternal(typed: typed, unit: unit, customDefault: nil, textValue: nil, labLow: nil, labHigh: nil,
                     specimen: nil, assay: nil, marker: marker, preferences: LabPreferences(sex: sex), ageYears: nil, draw: nil)
    }

    private static func readInternal(typed: Double, unit: String, customDefault: Double?, textValue: String?,
                                     labLow: Double?, labHigh: Double?, specimen: String?, assay: String?,
                                     marker: LabMarker, preferences: LabPreferences, ageYears: Int?, draw: LabDrawDraft?) -> LabReading {
        let sex = preferences.sex
        guard let value = customDefault ?? marker.toDefault(typed, unit: unit) else {
            if let textValue { return readQualitative(text: textValue, marker: marker, sex: sex) }
            if let sameUnitReading = readSameUnitBands(typed: typed, unit: unit, marker: marker, sex: sex, showDrugNotes: preferences.showDrugNotes) {
                return sameUnitReading
            }
            return LabReading(value: nil, unit: nil, status: .notComparable, bands: [], optimalBands: [], disputes: [], edgeLabels: [], doctorLines: [])
        }
        let stratum = selectStratum(marker: marker, preferences: preferences, ageYears: ageYears, specimen: specimen, assay: assay, draw: draw)
        let applicable = marker.bands.filter { applies($0.sex, to: sex) && $0.condition == nil }
        let containing = applicable.filter { band in bounds(of: band, in: marker).map { contains($0, value, band) } ?? false }
        let optimal = applicable.filter { $0.kind == "optimal" && bounds(of: $0, in: marker) != nil }

        let allDoctorMatches = marker.doctor
            .filter { applies($0.sex, to: sex) && sex.allows(sex: $0.sex, tag: $0.tag, showDrugNotes: preferences.showDrugNotes) }
            .filter { line in
                guard let op = line.op, let limit = line.value else { return false }
                return converted(limit, line.unit, marker).map { crosses(value, op, $0) } ?? false
            }
            .sorted { $0.urgency < $1.urgency }
        let unconditionalDoctor = allDoctorMatches.filter { $0.requires == nil }
        let conditionalDoctor = allDoctorMatches.filter { $0.requires != nil }

        let resolved: (status: LabStatus, tier: LabSeverityTier, label: String?)
        if let stratum {
            resolved = evaluateAgainstStratum(value: value, stratum: stratum, optimalBands: optimal, marker: marker)
        } else {
            let baseStatus = status(value, optimal, marker)
            if baseStatus == .noOptimalBand, marker.needsLabRange || labLow != nil || labHigh != nil,
               let fallback = evaluateAgainstLabRange(typed: typed, labLow: labLow, labHigh: labHigh, markerID: marker.id) {
                resolved = fallback
            } else {
                resolved = (baseStatus, defaultTier(for: baseStatus), nil)
            }
        }

        return LabReading(value: value, unit: marker.defaultUnit, status: resolved.status, tier: resolved.tier,
                          tierLabel: resolved.label, activeStratum: stratum, bands: containing, optimalBands: optimal,
                          disputes: Array(Set(optimal.compactMap(\.dispute))).sorted(),
                          edgeLabels: edgeLabels(value, containing.filter { $0.kind != "lab" && $0.dispute == nil }, marker),
                          doctorLines: unconditionalDoctor, conditionalDoctorLines: conditionalDoctor)
    }

    private static func selectStratum(marker: LabMarker, preferences: LabPreferences, ageYears: Int?,
                                      specimen: String?, assay: String?, draw: LabDrawDraft?) -> LabStratum? {
        let sex = preferences.sex
        let candidates = marker.strata.filter { stratum in
            guard sex.allows(sex: stratum.sex) else { return false }
            if sex != .female, stratum.cyclePhase != nil || stratum.pregnancy != nil || stratum.requiresHRT != nil { return false }
            if let minAge = stratum.ageMin, let ageYears, ageYears < minAge { return false }
            if let maxAge = stratum.ageMax, let ageYears, ageYears > maxAge { return false }
            if (stratum.ageMin != nil || stratum.ageMax != nil) && ageYears == nil { return false }
            if let reqHRT = stratum.requiresHRT {
                let userOnHRT = preferences.reproductiveStatus == .postmenopausalHRT
                if reqHRT != userOnHRT { return false }
            }
            if let preg = stratum.pregnancy {
                guard let status = preferences.reproductiveStatus else { return false }
                let matchesPreg = (preg == status.rawValue)
                    || (preg == "pregnant" && status.rawValue.hasPrefix("trimester_"))
                    || (preg == "trimester_2_3" && (status == .pregnantTrimester2 || status == .pregnantTrimester3))
                if !matchesPreg { return false }
            }
            if let mod = stratum.modifier {
                let ok = (mod == "endurance_athlete" && preferences.isEnduranceAthlete)
                    || (mod == "smoker" && preferences.isSmoker)
                    || (mod == "african_ancestry" && preferences.africanAncestry)
                if !ok { return false }
            }
            return true
        }
        guard !candidates.isEmpty else { return nil }
        let desiredPhase = effectiveCyclePhase(preferences: preferences, draw: draw)
        let assayLow = assay?.lowercased()
        let specLow = specimen?.lowercased()

        return candidates.max { a, b in
            specificityScore(a, sex: sex, ageYears: ageYears, phase: desiredPhase, assay: assayLow, specimen: specLow)
                < specificityScore(b, sex: sex, ageYears: ageYears, phase: desiredPhase, assay: assayLow, specimen: specLow)
        }
    }

    private static func specificityScore(_ s: LabStratum, sex: LabSex, ageYears: Int?, phase: String?, assay: String?, specimen: String?) -> Int {
        var score = 0
        if s.sex == sex && sex != .any { score += 4 }
        if s.ageMin != nil || s.ageMax != nil, ageYears != nil { score += 8 }
        if s.pregnancy != nil { score += 12 }
        if let cp = s.cyclePhase {
            if cp == phase { score += 10 } else if phase != nil { score -= 5 }
        }
        if s.modifier != nil { score += 6 }
        if let sa = s.assay {
            if assay?.contains(sa) == true { score += 10 } else if assay != nil { score -= 4 }
        }
        if let spec = specimen, s.population.lowercased().contains(spec) { score += 6 }
        return score
    }

    private static func effectiveCyclePhase(preferences: LabPreferences, draw: LabDrawDraft?) -> String? {
        guard preferences.sex == .female else { return nil }
        if let explicit = draw?.cyclePhase, !explicit.isEmpty { return explicit }
        if let day = draw?.cycleDay {
            switch day {
            case 1...5: return "early_follicular"
            case 6...10: return "mid_follicular"
            case 11...14: return "ovulation"
            default: return "luteal"
            }
        }
        switch preferences.reproductiveStatus {
        case .postmenopausal, .postmenopausalHRT: return "postmenopausal"
        case .premenopausal: return "premenopausal"
        default: return nil
        }
    }

    private static func evaluateAgainstStratum(value: Double, stratum: LabStratum, optimalBands: [LabBand],
                                               marker: LabMarker) -> (LabStatus, LabSeverityTier, String?) {
        let matchedBand = stratum.bands.first { b in
            let above = b.min.map { value >= $0 } ?? true
            let below = b.max.map { value <= $0 } ?? true
            return above && below && !(b.min != nil && value == b.min && stratum.bands.contains { $0.max == value && $0.tier == "optimal" })
        }
        let mappedTier = matchedBand.map { mapTierName($0.tier) }

        if let optLow = stratum.optimalLow, value < optLow {
            return (.low, mappedTier ?? (stratum.standardLow.map { value < $0 ? .suboptimalLow : .watchLow } ?? .suboptimalLow), matchedBand?.meaning)
        }
        if let optHigh = stratum.optimalHigh, value > optHigh {
            return (.high, mappedTier ?? (stratum.standardHigh.map { value > $0 ? .high : .watchHigh } ?? .watchHigh), matchedBand?.meaning)
        }
        if stratum.optimalLow != nil || stratum.optimalHigh != nil {
            return (.optimal, .optimal, matchedBand?.meaning ?? stratum.sweetSpot)
        }
        if let tier = mappedTier {
            switch tier {
            case .optimal: return (.optimal, .optimal, matchedBand?.meaning)
            case .criticalLow, .suboptimalLow, .watchLow: return (.low, tier, matchedBand?.meaning)
            case .watchHigh, .suboptimalHigh, .high, .criticalHigh: return (.high, tier, matchedBand?.meaning)
            default: break
            }
        }
        if let stdLow = stratum.standardLow, value < stdLow { return (.low, .suboptimalLow, matchedBand?.meaning) }
        if let stdHigh = stratum.standardHigh, value > stdHigh { return (.high, .high, matchedBand?.meaning) }
        let fallback = status(value, optimalBands, marker)
        return (fallback, defaultTier(for: fallback), matchedBand?.meaning)
    }

    private static func evaluateAgainstLabRange(typed: Double, labLow: Double?, labHigh: Double?,
                                                markerID: String) -> (LabStatus, LabSeverityTier, String?)? {
        guard labLow != nil || labHigh != nil else { return nil }
        if let low = labLow, typed < low { return (.low, .suboptimalLow, "Below lab's printed range") }
        if let high = labHigh, high > 0, typed > high {
            if typed > high * 3.0 {
                return (.high, .high, "Above 3× ULN (\(LabInsightsRule.number(high)))")
            }
            return (.high, .watchHigh, "1–3× lab upper limit (\(LabInsightsRule.number(high)))")
        }
        return (.optimal, .optimal, "Within lab's printed range")
    }

    private static func readQualitative(text: String, marker: LabMarker, sex: LabSex) -> LabReading {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = cleaned.lowercased()
        let applicable = marker.bands.filter { applies($0.sex, to: sex) }
        let matched = applicable.filter { band in
            (band.values ?? []).contains { $0.caseInsensitiveCompare(cleaned) == .orderedSame }
        }
        if let first = matched.first {
            let st: LabStatus = first.kind == "optimal" ? .optimal : (first.kind == "low" ? .low : .high)
            return LabReading(value: nil, unit: marker.defaultUnit, status: st, tier: defaultTier(for: st),
                              tierLabel: first.label, bands: matched, optimalBands: applicable.filter { $0.kind == "optimal" },
                              disputes: [], edgeLabels: [], doctorLines: [])
        }
        if ["negative", "none", "none or rare", "rare", "absent", "normal", "not detected"].contains(lower) {
            return LabReading(value: nil, unit: marker.defaultUnit, status: .optimal, tier: .optimal,
                              tierLabel: cleaned, bands: [], optimalBands: [], disputes: [], edgeLabels: [], doctorLines: [])
        }
        if lower.contains("trace") || lower == "few" {
            return LabReading(value: nil, unit: marker.defaultUnit, status: .high, tier: .watchHigh,
                              tierLabel: cleaned, bands: [], optimalBands: [], disputes: [], edgeLabels: [], doctorLines: [])
        }
        return LabReading(value: nil, unit: marker.defaultUnit, status: .high, tier: .high,
                          tierLabel: cleaned, bands: [], optimalBands: [], disputes: [], edgeLabels: [], doctorLines: [])
    }

    private static func readBloodPressure(systolic: Double, diastolic: Double, marker: LabMarker, sex: LabSex) -> LabReading {
        let status: LabStatus
        let tier: LabSeverityTier
        let label: String
        var doctors: [LabDoctorLine] = []
        var condDoctors: [LabDoctorLine] = []

        if systolic >= 180 || diastolic >= 120 {
            status = .high; tier = .criticalHigh; label = "Severe hypertension"
            doctors.append(LabDoctorLine(op: ">=", value: 180, unit: "mmHg", sex: .any, urgency: .fewDays,
                                         text: "Blood pressure ≥ 180/120 without symptoms requires a prompt physician visit.",
                                         source: "global_protocols", requires: nil, tag: nil, origin: .vault))
            condDoctors.append(LabDoctorLine(op: ">=", value: 180, unit: "mmHg", sex: .any, urgency: .goNow,
                                             text: "Severe BP ≥ 180/120 with chest pain, shortness of breath, weakness, vision changes, or severe headache requires emergency transport now.",
                                             source: "global_protocols", requires: "chest pain, shortness of breath, weakness, severe headache, or vision changes", tag: nil, origin: .vault))
        } else if systolic >= 140 || diastolic >= 90 {
            status = .high; tier = .high; label = "Stage 2 hypertension"
        } else if systolic >= 130 || diastolic >= 80 {
            status = .high; tier = .suboptimalHigh; label = "Stage 1 hypertension"
        } else if systolic >= 120 {
            status = .high; tier = .watchHigh; label = "Elevated blood pressure"
        } else {
            status = .optimal; tier = .optimal; label = "Normal blood pressure"
        }
        return LabReading(value: systolic, unit: "mmHg", status: status, tier: tier, tierLabel: label,
                          bands: [], optimalBands: [], disputes: [], edgeLabels: [],
                          doctorLines: doctors, conditionalDoctorLines: condDoctors)
    }

    /// Disputed optimal bands require simultaneous containment (D1); undisputed adjacent optimal sub-bands union cleanly (D8).
    private static func status(_ value: Double, _ optimal: [LabBand], _ marker: LabMarker) -> LabStatus {
        guard !optimal.isEmpty else { return .noOptimalBand }
        let inside = optimal.filter { band in bounds(of: band, in: marker).map { contains($0, value, band) } ?? false }
        let hasDisputes = optimal.contains { $0.dispute != nil }
        if !hasDisputes {
            if !inside.isEmpty { return .optimal }
        } else {
            if inside.count == optimal.count { return .optimal }
            if !inside.isEmpty { return .disputed }
        }
        let lows = optimal.compactMap { bounds(of: $0, in: marker)?.low }
        let highs = optimal.compactMap { bounds(of: $0, in: marker)?.high }
        if let lowest = lows.min(), value < lowest, highs.allSatisfy({ value < $0 }) { return .low }
        if let highest = highs.max(), (value > highest || (value == highest && optimal.allSatisfy { $0.highInclusive == false })) { return .high }
        return hasDisputes ? .disputed : .low
    }

    /// Evaluates known non-convertible secondary units (such as Lp(a) in mg/dL) directly against bands authored in that same unit.
    private static func readSameUnitBands(typed: Double, unit: String, marker: LabMarker, sex: LabSex, showDrugNotes: Bool) -> LabReading? {
        guard !unit.isEmpty, marker.units.contains(where: { $0.unit == unit }) else { return nil }
        let unitBands = marker.bands.filter { $0.unit == unit && applies($0.sex, to: sex) && $0.condition == nil }
        guard !unitBands.isEmpty else { return nil }
        let containing = unitBands.filter { contains(($0.low, $0.high), typed, $0) }
        let optimal = unitBands.filter { $0.kind == "optimal" }
        guard !optimal.isEmpty else { return nil }

        let inside = optimal.filter { contains(($0.low, $0.high), typed, $0) }
        let hasDisputes = optimal.contains { $0.dispute != nil }
        let baseStatus: LabStatus
        if !hasDisputes && !inside.isEmpty {
            baseStatus = .optimal
        } else if hasDisputes && inside.count == optimal.count {
            baseStatus = .optimal
        } else if hasDisputes && !inside.isEmpty {
            baseStatus = .disputed
        } else {
            let lows = optimal.compactMap(\.low)
            let highs = optimal.compactMap(\.high)
            if let lowest = lows.min(), typed < lowest, highs.allSatisfy({ typed < $0 }) {
                baseStatus = .low
            } else if let highest = highs.max(), (typed > highest || (typed == highest && optimal.allSatisfy { $0.highInclusive == false })) {
                baseStatus = .high
            } else {
                baseStatus = hasDisputes ? .disputed : .low
            }
        }

        let doctors = marker.doctor
            .filter { $0.unit == unit && applies($0.sex, to: sex) && sex.allows(sex: $0.sex, tag: $0.tag, showDrugNotes: showDrugNotes) }
            .filter { line in
                guard let op = line.op, let limit = line.value else { return false }
                return crosses(typed, op, limit)
            }
            .sorted { $0.urgency < $1.urgency }
        let tier: LabSeverityTier
        if baseStatus == .high, containing.contains(where: { $0.kind == "watch" }) && !containing.contains(where: { $0.kind == "high" }) {
            tier = .watchHigh
        } else {
            tier = defaultTier(for: baseStatus)
        }
        return LabReading(
            value: typed,
            unit: unit,
            status: baseStatus,
            tier: tier,
            tierLabel: containing.first(where: { $0.kind != "lab" })?.label,
            bands: containing,
            optimalBands: optimal,
            disputes: Array(Set(optimal.compactMap(\.dispute))).sorted(),
            edgeLabels: [],
            doctorLines: doctors.filter { $0.requires == nil },
            conditionalDoctorLines: doctors.filter { $0.requires != nil })
    }

    private static func mapTierName(_ raw: String) -> LabSeverityTier {
        let t = raw.lowercased()
        if t.contains("critical_low") || t.contains("severe_thrombocytopenia") || t.contains("severe_lymphopenia") { return .criticalLow }
        if t.contains("suboptimal_low") || t == "low" || t.contains("openia") { return .suboptimalLow }
        if t.contains("borderline_low") || t == "low_normal" { return .watchLow }
        if t == "optimal" || t == "normal" { return .optimal }
        if t == "near_optimal" || t == "acceptable" || t == "upper_normal" || t == "borderline_high" || t.contains("mild_") { return .watchHigh }
        if t == "suboptimal_high" || t.contains("moderate_") { return .suboptimalHigh }
        if t.contains("critical_high") || t.contains("marked_") { return .criticalHigh }
        if t == "high" || t.contains("philia") || t.contains("cytosis") { return .high }
        return .unknown
    }

    private static func defaultTier(for status: LabStatus) -> LabSeverityTier {
        switch status {
        case .optimal: return .optimal
        case .disputed: return .disputed
        case .low: return .suboptimalLow
        case .high: return .high
        case .noOptimalBand, .notComparable: return .unknown
        }
    }

    private static func edgeLabels(_ value: Double, _ bands: [LabBand], _ marker: LabMarker) -> [String] {
        guard bands.count >= 2, Set(bands.map(\.label)).count >= 2 else { return [] }
        let onEdge = bands.contains { band in
            guard let b = bounds(of: band, in: marker) else { return false }
            return b.low == value || b.high == value
        }
        return onEdge ? bands.map(\.label) : []
    }

    /// Band limits in the marker's default unit; nil when the band has no unit or no stated factor (D4).
    private static func bounds(of band: LabBand, in marker: LabMarker) -> (low: Double?, high: Double?)? {
        guard let unit = band.unit ?? marker.ratioUnit else { return nil }
        let low = band.low.flatMap { marker.toDefault($0, unit: unit) }
        let high = band.high.flatMap { marker.toDefault($0, unit: unit) }
        if (band.low != nil && low == nil) || (band.high != nil && high == nil) { return nil }
        return (low, high)
    }

    private static func converted(_ value: Double, _ unit: String?, _ marker: LabMarker) -> Double? {
        (unit ?? marker.ratioUnit).flatMap { marker.toDefault(value, unit: $0) }
    }

    private static func contains(_ b: (low: Double?, high: Double?), _ value: Double, _ band: LabBand) -> Bool {
        let aboveLow = b.low.map { band.lowInclusive == false ? value > $0 : value >= $0 } ?? true
        let belowHigh = b.high.map { band.highInclusive == false ? value < $0 : value <= $0 } ?? true
        return aboveLow && belowHigh
    }

    private static func crosses(_ value: Double, _ op: String, _ limit: Double) -> Bool {
        switch op {
        case ">": return value > limit
        case ">=": return value >= limit
        case "<": return value < limit
        case "<=": return value <= limit
        default: return false
        }
    }

    private static func applies(_ bandSex: LabSex?, to sex: LabSex) -> Bool {
        bandSex == nil || bandSex == .any || bandSex == sex
    }
}

private extension LabMarker {
    /// The unit a unit-less band or doctor line is read in: only a calculated ratio has one.
    var ratioUnit: String? { isUnitlessRatio ? defaultUnit ?? "" : nil }
}
