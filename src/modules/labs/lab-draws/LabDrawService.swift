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
    public var note: String?

    public init(date: ISODate, time: String? = nil, lab: String? = nil, fastedHours: Double? = nil, trainedHard72h: Bool? = nil,
                alcohol5d: Bool? = nil, biotinStopped: Bool? = nil, ironStopped: Bool? = nil, illRecently: Bool? = nil, note: String? = nil) {
        self.date = date
        self.time = time
        self.lab = lab
        self.fastedHours = fastedHours
        self.trainedHard72h = trainedHard72h
        self.alcohol5d = alcohol5d
        self.biotinStopped = biotinStopped
        self.ironStopped = ironStopped
        self.illRecently = illRecently
        self.note = note
    }
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
    public let unit: String
    public let labLow: Double?
    public let labHigh: Double?
    /// The value in the marker's default unit; nil when the vault gives no factor for the typed unit.
    public let defaultValue: Double?
    public let defaultUnit: String?
    /// Worked out from the draw's other results by a vault formula, not typed or printed by the lab; it cannot be deleted.
    public var isCalculated = false
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
            INSERT INTO lab_draws (draw_date, draw_time, lab, fasted_hours, trained_72h, alcohol_5d, biotin_stopped, iron_stopped, ill_recently, note)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [.text(draft.date.string), .optional(draft.time), .optional(draft.lab), .optional(draft.fastedHours),
                  Self.flag(draft.trainedHard72h), Self.flag(draft.alcohol5d), Self.flag(draft.biotinStopped),
                  Self.flag(draft.ironStopped), Self.flag(draft.illRecently), .optional(draft.note)])
        return try db.query("SELECT last_insert_rowid() AS id")[0].int("id")
    }

    public func draws() throws -> [LabDraw] {
        try db.query("SELECT * FROM lab_draws ORDER BY draw_date DESC, id DESC").map { row in
            LabDraw(id: row.int("id"), draft: LabDrawDraft(
                date: ISODate(row.text("draw_date"))!, time: row.optionalText("draw_time"), lab: row.optionalText("lab"),
                fastedHours: row.optionalDouble("fasted_hours"), trainedHard72h: Self.bool(row, "trained_72h"),
                alcohol5d: Self.bool(row, "alcohol_5d"), biotinStopped: Self.bool(row, "biotin_stopped"),
                ironStopped: Self.bool(row, "iron_stopped"), illRecently: Self.bool(row, "ill_recently"), note: row.optionalText("note")))
        }
    }

    public func deleteDraw(_ id: Int) throws {
        try db.execute("DELETE FROM lab_draws WHERE id = ?", [.int(Int64(id))])
    }

    @discardableResult
    public func addResult(drawID: Int, markerID: String, value: Double, unit: String, labLow: Double? = nil, labHigh: Double? = nil) throws -> Int {
        guard let marker = catalogue.marker(markerID) else { throw ValidationError("\(markerID) is not in the labs catalogue") }
        guard marker.units.isEmpty || marker.units.contains(where: { $0.unit == unit }) else {
            throw ValidationError("\(unit) is not a unit the catalogue gives for \(marker.name)")
        }
        guard value.isFinite else { throw ValidationError("The value must be a number") }
        try db.execute("INSERT INTO lab_results (draw_id, marker_id, value, unit, lab_low, lab_high) VALUES (?, ?, ?, ?, ?, ?)",
                       [.int(Int64(drawID)), .text(markerID), .double(value), .text(unit), .optional(labLow), .optional(labHigh)])
        return try db.query("SELECT last_insert_rowid() AS id")[0].int("id")
    }

    public func deleteResult(_ id: Int) throws {
        try db.execute("DELETE FROM lab_results WHERE id = ?", [.int(Int64(id))])
    }

    /// Newest first. A calculated marker is worked out on every draw that has its inputs.
    public func history(of markerID: String) throws -> [LabResult] {
        guard catalogue.marker(markerID)?.formula != nil else { return try results(where: "r.marker_id = ?", [.text(markerID)]) }
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
            let markerID = row.text("marker_id"), value = row.double("value"), unit = row.text("unit")
            let marker = catalogue.marker(markerID)
            return LabResult(id: row.int("id"), drawID: row.int("draw_id"), date: ISODate(row.text("draw_date"))!, markerID: markerID,
                             value: value, unit: unit, labLow: row.optionalDouble("lab_low"), labHigh: row.optionalDouble("lab_high"),
                             defaultValue: marker?.toDefault(value, unit: unit), defaultUnit: marker?.defaultUnit)
        }
    }

    private static func flag(_ value: Bool?) -> SQLValue { value.map { .int($0 ? 1 : 0) } ?? .null }
    private static func bool(_ row: Row, _ name: String) -> Bool? { row.optionalInt(name).map { $0 == 1 } }
}
