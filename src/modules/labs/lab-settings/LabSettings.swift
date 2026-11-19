import Foundation

public struct LabPreferences: Equatable {
    /// Picks the sex-specific bands.
    public var sex: LabSex
    /// For calendar age in PhenoAge.
    public var birthDate: ISODate?
    /// Drug, TRT and prescription notes are hidden unless switched on (D5).
    public var showDrugNotes: Bool
}

public final class LabSettings {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func load() throws -> LabPreferences {
        var values: [String: String] = [:]
        for row in try db.query("SELECT key, value FROM settings WHERE key IN ('labs_sex', 'labs_birth_date', 'labs_show_drug_notes')") {
            values[row.text("key")] = row.text("value")
        }
        return LabPreferences(sex: values["labs_sex"].flatMap(LabSex.init(rawValue:)) ?? .male,
                              birthDate: values["labs_birth_date"].flatMap(ISODate.init),
                              showDrugNotes: values["labs_show_drug_notes"] == "1")
    }

    public func setSex(_ sex: LabSex) throws { try save("labs_sex", sex.rawValue) }
    public func setBirthDate(_ day: ISODate?) throws {
        guard let day else { return try db.execute("DELETE FROM settings WHERE key = 'labs_birth_date'") }
        try save("labs_birth_date", day.string)
    }
    public func setShowDrugNotes(_ on: Bool) throws { try save("labs_show_drug_notes", on ? "1" : "0") }

    private func save(_ key: String, _ value: String) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key), .text(value)])
    }
}
