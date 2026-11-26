import Foundation

/// One blood draw and the state it was taken in, as the vault's draw protocol asks. nil = not answered.
public struct LabDrawDraft: Equatable {
    public var date: ISODate
    public var time: String?
    public var lab: String?
    public var fastedHours: Double?
    public var trainedHard72h: Bool?
    public var alcohol5d: Bool?
    public var biotinStopped: Bool?
    public var ironStopped: Bool?
    public var illRecently: Bool?
    public var cycleDay: Int?
    public var cyclePhase: String?
    public var poorSleep: Bool?
    public var acuteStress: Bool?
    public var recentVaccineOrSurgery: Bool?
    public var medsNoted: String?
    public var note: String?

    public init(date: ISODate, time: String? = nil, lab: String? = nil, fastedHours: Double? = nil, trainedHard72h: Bool? = nil,
                alcohol5d: Bool? = nil, biotinStopped: Bool? = nil, ironStopped: Bool? = nil, illRecently: Bool? = nil,
                cycleDay: Int? = nil, cyclePhase: String? = nil, poorSleep: Bool? = nil, acuteStress: Bool? = nil,
                recentVaccineOrSurgery: Bool? = nil, medsNoted: String? = nil, note: String? = nil) {
        self.date = date
        self.time = time
        self.lab = lab
        self.fastedHours = fastedHours
        self.trainedHard72h = trainedHard72h
        self.alcohol5d = alcohol5d
        self.biotinStopped = biotinStopped
        self.ironStopped = ironStopped
        self.illRecently = illRecently
        self.cycleDay = cycleDay
        self.cyclePhase = cyclePhase
        self.poorSleep = poorSleep
        self.acuteStress = acuteStress
        self.recentVaccineOrSurgery = recentVaccineOrSurgery
        self.medsNoted = medsNoted
        self.note = note
    }
}

public enum LabValueOperator: String, Codable, Equatable {
    case equal = "="
    case belowLimit = "<"
    case aboveLimit = ">"
}

public struct LabDraw: Equatable, Identifiable {
    public let id: Int
    public let draft: LabDrawDraft
}

public struct LabResult: Equatable, Identifiable {
    public let id: Int
    public let drawID: Int
    public let date: ISODate
    public let markerID: String
    public let value: Double
    public let textValue: String?
    public let valueOperator: LabValueOperator?
    public let secondaryValue: Double?
    public let customToDefault: Double?
    public let specimen: String?
    public let assay: String?
    public let unit: String
    public let labLow: Double?
    public let labHigh: Double?
    /// The value in the marker's default unit; nil when the vault gives no factor for the typed unit.
    public let defaultValue: Double?
    public let defaultUnit: String?
    /// Worked out from the draw's other results by a vault formula, not typed or printed by the lab; it cannot be deleted.
    public var isCalculated = false

    public init(id: Int, drawID: Int, date: ISODate, markerID: String, value: Double, textValue: String? = nil,
                valueOperator: LabValueOperator? = nil, secondaryValue: Double? = nil, customToDefault: Double? = nil,
                specimen: String? = nil, assay: String? = nil, unit: String, labLow: Double? = nil, labHigh: Double? = nil,
                defaultValue: Double? = nil, defaultUnit: String? = nil, isCalculated: Bool = false) {
        self.id = id
        self.drawID = drawID
        self.date = date
        self.markerID = markerID
        self.value = value
        self.textValue = textValue
        self.valueOperator = valueOperator
        self.secondaryValue = secondaryValue
        self.customToDefault = customToDefault
        self.specimen = specimen
        self.assay = assay
        self.unit = unit
        self.labLow = labLow
        self.labHigh = labHigh
        self.defaultValue = defaultValue
        self.defaultUnit = defaultUnit
        self.isCalculated = isCalculated
    }
}

public final class LabDrawService {
    private let db: Database
    private let catalogue: LabCatalogue

    public init(_ db: Database, catalogue: LabCatalogue) {
        self.db = db
        self.catalogue = catalogue
    }

    @discardableResult
    public func addDraw(_ draft: LabDrawDraft) throws -> Int {
        try db.execute("""
            INSERT INTO lab_draws (
                draw_date, draw_time, lab, fasted_hours, trained_72h, alcohol_5d, biotin_stopped, iron_stopped, ill_recently,
                cycle_day, cycle_phase, poor_sleep, acute_stress, recent_vaccine_or_surgery, meds_noted, note
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(draft.date.string), .optional(draft.time), .optional(draft.lab), .optional(draft.fastedHours),
                  Self.flag(draft.trainedHard72h), Self.flag(draft.alcohol5d), Self.flag(draft.biotinStopped),
                  Self.flag(draft.ironStopped), Self.flag(draft.illRecently), .optional(draft.cycleDay),
                  .optional(draft.cyclePhase), Self.flag(draft.poorSleep), Self.flag(draft.acuteStress),
                  Self.flag(draft.recentVaccineOrSurgery), .optional(draft.medsNoted), .optional(draft.note)])
        return try db.query("SELECT last_insert_rowid() AS id")[0].int("id")
    }

    public func draws() throws -> [LabDraw] {
        try db.query("SELECT * FROM lab_draws ORDER BY draw_date DESC, id DESC").map { row in
            LabDraw(id: row.int("id"), draft: LabDrawDraft(
                date: ISODate(row.text("draw_date"))!, time: row.optionalText("draw_time"), lab: row.optionalText("lab"),
                fastedHours: row.optionalDouble("fasted_hours"), trainedHard72h: Self.bool(row, "trained_72h"),
                alcohol5d: Self.bool(row, "alcohol_5d"), biotinStopped: Self.bool(row, "biotin_stopped"),
                ironStopped: Self.bool(row, "iron_stopped"), illRecently: Self.bool(row, "ill_recently"),
                cycleDay: row.optionalInt("cycle_day"), cyclePhase: row.optionalText("cycle_phase"),
                poorSleep: Self.bool(row, "poor_sleep"), acuteStress: Self.bool(row, "acute_stress"),
                recentVaccineOrSurgery: Self.bool(row, "recent_vaccine_or_surgery"),
                medsNoted: row.optionalText("meds_noted"), note: row.optionalText("note")))
        }
    }

    public func deleteDraw(_ id: Int) throws {
        try db.execute("DELETE FROM lab_draws WHERE id = ?", [.int(Int64(id))])
    }

    public func updateDraw(_ id: Int, _ draft: LabDrawDraft) throws {
        guard !(try db.query("SELECT 1 FROM lab_draws WHERE id = ?", [.int(Int64(id))])).isEmpty else {
            throw ValidationError("Draw not found")
        }
        try db.execute("""
            UPDATE lab_draws SET
                draw_date = ?, draw_time = ?, lab = ?, fasted_hours = ?, trained_72h = ?, alcohol_5d = ?,
                biotin_stopped = ?, iron_stopped = ?, ill_recently = ?, cycle_day = ?, cycle_phase = ?,
                poor_sleep = ?, acute_stress = ?, recent_vaccine_or_surgery = ?, meds_noted = ?, note = ?
            WHERE id = ?
            """, [.text(draft.date.string), .optional(draft.time), .optional(draft.lab), .optional(draft.fastedHours),
                  Self.flag(draft.trainedHard72h), Self.flag(draft.alcohol5d), Self.flag(draft.biotinStopped),
                  Self.flag(draft.ironStopped), Self.flag(draft.illRecently), .optional(draft.cycleDay),
                  .optional(draft.cyclePhase), Self.flag(draft.poorSleep), Self.flag(draft.acuteStress),
                  Self.flag(draft.recentVaccineOrSurgery), .optional(draft.medsNoted), .optional(draft.note),
                  .int(Int64(id))])
    }

    /// Unique trimmed lab names ordered by most recent draw, deduplicated case-insensitively while keeping newest casing.
    public func savedLabNames() throws -> [String] {
        let rows = try db.query("SELECT lab FROM lab_draws WHERE lab IS NOT NULL ORDER BY draw_date DESC, id DESC")
        var seen: Set<String> = []
        var names: [String] = []
        for row in rows {
            guard let raw = row.optionalText("lab") else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            names.append(trimmed)
        }
        return names
    }

    @discardableResult
    public func addResult(drawID: Int, markerID: String, value: Double, unit: String, labLow: Double? = nil, labHigh: Double? = nil,
                          valueOperator: LabValueOperator? = nil, secondaryValue: Double? = nil, customToDefault: Double? = nil,
                          specimen: String? = nil, assay: String? = nil) throws -> Int {
        try validateNumericResult(markerID: markerID, value: value, unit: unit, customToDefault: customToDefault)
        try db.execute("""
            INSERT INTO lab_results (
                draw_id, marker_id, value, value_operator, secondary_value, custom_to_default, specimen, assay, unit, lab_low, lab_high
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.int(Int64(drawID)), .text(markerID), .double(value), .optional(valueOperator?.rawValue),
                  .optional(secondaryValue), .optional(customToDefault), .optional(specimen), .optional(assay),
                  .text(unit), .optional(labLow), .optional(labHigh)])
        return try db.query("SELECT last_insert_rowid() AS id")[0].int("id")
    }

    @discardableResult
    public func addQualitativeResult(drawID: Int, markerID: String, textValue: String, unit: String = "", specimen: String? = nil) throws -> Int {
        let (cleaned, parsedNumeric, resolvedUnit) = try validateQualitativeResult(markerID: markerID, textValue: textValue, unit: unit)
        try db.execute("""
            INSERT INTO lab_results (draw_id, marker_id, value, text_value, specimen, unit)
            VALUES (?, ?, ?, ?, ?, ?)
            """, [.int(Int64(drawID)), .text(markerID), .optional(parsedNumeric), .text(cleaned),
                  .optional(specimen), .text(resolvedUnit)])
        return try db.query("SELECT last_insert_rowid() AS id")[0].int("id")
    }

    public func deleteResult(_ id: Int) throws {
        try db.execute("DELETE FROM lab_results WHERE id = ?", [.int(Int64(id))])
    }

    public func updateResult(_ id: Int, value: Double, unit: String, labLow: Double? = nil, labHigh: Double? = nil,
                             valueOperator: LabValueOperator? = nil, secondaryValue: Double? = nil, customToDefault: Double? = nil,
                             specimen: String? = nil, assay: String? = nil) throws {
        guard let markerID = try db.query("SELECT marker_id FROM lab_results WHERE id = ?", [.int(Int64(id))]).first?.text("marker_id") else {
            throw ValidationError("Result not found")
        }
        try validateNumericResult(markerID: markerID, value: value, unit: unit, customToDefault: customToDefault)
        try db.execute("""
            UPDATE lab_results SET
                value = ?, text_value = NULL, value_operator = ?, secondary_value = ?, custom_to_default = ?,
                specimen = ?, assay = ?, unit = ?, lab_low = ?, lab_high = ?
            WHERE id = ?
            """, [.double(value), .optional(valueOperator?.rawValue), .optional(secondaryValue), .optional(customToDefault),
                  .optional(specimen), .optional(assay), .text(unit), .optional(labLow), .optional(labHigh), .int(Int64(id))])
    }

    public func updateQualitativeResult(_ id: Int, textValue: String, unit: String = "", specimen: String? = nil) throws {
        guard let markerID = try db.query("SELECT marker_id FROM lab_results WHERE id = ?", [.int(Int64(id))]).first?.text("marker_id") else {
            throw ValidationError("Result not found")
        }
        let (cleaned, parsedNumeric, resolvedUnit) = try validateQualitativeResult(markerID: markerID, textValue: textValue, unit: unit)
        try db.execute("""
            UPDATE lab_results SET value = ?, text_value = ?, value_operator = NULL, secondary_value = NULL,
                custom_to_default = NULL, specimen = ?, assay = NULL, unit = ?, lab_low = NULL, lab_high = NULL
            WHERE id = ?
            """, [.optional(parsedNumeric), .text(cleaned), .optional(specimen), .text(resolvedUnit), .int(Int64(id))])
    }

    private func validateNumericResult(markerID: String, value: Double, unit: String, customToDefault: Double?) throws {
        guard let marker = catalogue.marker(markerID) else { throw ValidationError("\(markerID) is not in the labs catalogue") }
        let isKnownUnit = marker.units.isEmpty || marker.units.contains(where: { $0.unit == unit })
        if let customToDefault, (!customToDefault.isFinite || customToDefault <= 0) {
            throw ValidationError("Custom conversion multiplier must be a positive number")
        }
        guard isKnownUnit || customToDefault != nil else {
            throw ValidationError("\(unit) is not a unit the catalogue gives for \(marker.name)")
        }
        guard value.isFinite else { throw ValidationError("The value must be a number") }
    }

    private func validateQualitativeResult(markerID: String, textValue: String, unit: String) throws -> (String, Double?, String) {
        guard let marker = catalogue.marker(markerID) else { throw ValidationError("\(markerID) is not in the labs catalogue") }
        let cleaned = textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ValidationError("Enter a result for \(marker.name)") }
        let parsedNumeric = Self.parseTiterNumber(cleaned)
        let resolvedUnit = unit.isEmpty ? (marker.defaultUnit ?? "") : unit
        return (cleaned, parsedNumeric, resolvedUnit)
    }

    /// Newest first. A calculated marker is worked out on every draw that has its inputs.
    public func history(of markerID: String) throws -> [LabResult] {
        let marker = catalogue.marker(markerID)
        guard marker?.formula != nil || marker?.computed == true else { return try results(where: "r.marker_id = ?", [.text(markerID)]) }
        return try draws().flatMap { try results(inDraw: $0.id).filter { $0.markerID == markerID } }
    }

    /// What the lab reported, plus every vault formula the draw has the inputs for.
    public func results(inDraw drawID: Int) throws -> [LabResult] {
        let stored = try results(where: "r.draw_id = ?", [.int(Int64(drawID))])
        return stored + LabCalculator(catalogue: catalogue).calculate(from: stored)
    }

    private func results(where clause: String, _ params: [SQLValue]) throws -> [LabResult] {
        try db.query("""
            SELECT r.*, d.draw_date FROM lab_results r JOIN lab_draws d ON d.id = r.draw_id
            WHERE \(clause) ORDER BY d.draw_date DESC, r.id DESC
            """, params).map { row in
            let markerID = row.text("marker_id"), unit = row.text("unit")
            let numeric = row.optionalDouble("value")
            let value = numeric ?? 0
            let customFactor = row.optionalDouble("custom_to_default")
            let marker = catalogue.marker(markerID)
            let inDefault: Double? = numeric.flatMap { raw in
                if let customFactor { return raw * customFactor }
                return marker?.toDefault(raw, unit: unit)
            }
            return LabResult(id: row.int("id"), drawID: row.int("draw_id"), date: ISODate(row.text("draw_date"))!, markerID: markerID,
                             value: value, textValue: row.optionalText("text_value"),
                             valueOperator: row.optionalText("value_operator").flatMap(LabValueOperator.init(rawValue:)),
                             secondaryValue: row.optionalDouble("secondary_value"), customToDefault: customFactor,
                             specimen: row.optionalText("specimen"), assay: row.optionalText("assay"),
                             unit: unit, labLow: row.optionalDouble("lab_low"), labHigh: row.optionalDouble("lab_high"),
                             defaultValue: inDefault, defaultUnit: marker?.defaultUnit)
        }
    }

    private static func parseTiterNumber(_ text: String) -> Double? {
        let lower = text.lowercased().trimmingCharacters(in: .whitespaces)
        if let colon = lower.firstIndex(of: ":"), lower[..<colon].trimmingCharacters(in: .whitespaces) == "1" {
            let rhs = lower[lower.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: " +"))
            return Double(rhs)
        }
        return nil
    }

    private static func flag(_ value: Bool?) -> SQLValue { value.map { .int($0 ? 1 : 0) } ?? .null }
    private static func bool(_ row: Row, _ name: String) -> Bool? { row.optionalInt(name).map { $0 == 1 } }
}
