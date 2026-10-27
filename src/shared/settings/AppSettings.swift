import Foundation

public enum DayLabelMode: String, Equatable {
    case number
    case weekday
}

public struct DeloadSettings: Equatable {
    public var enabled: Bool
    public var weightMultiplier: Double
    public var repsMultiplier: Double

    public init(enabled: Bool, weightMultiplier: Double, repsMultiplier: Double) {
        self.enabled = enabled
        self.weightMultiplier = weightMultiplier
        self.repsMultiplier = repsMultiplier
    }
}

public struct AppSettings: Equatable {
    /// Sets before this date are ignored by every progress calculation.
    public var historyStartDate: ISODate
    public var dayLabelMode: DayLabelMode
    public var deload: DeloadSettings
    /// When true, sets logged during deload are left out of working weights, trends, last session and volume.
    public var ignoreDeloadSessions: Bool
    public var proteinGramsPerLb: Double
    public var fatPercent: Double
    /// How far a measurement may be from its target (in percent, in the wrong direction) and still count as on track.
    public var measurementTolerancePercent: Double
}

/// Each setting is a separate key so one knob never changes another (deload vs history start).
public final class SettingsRepository {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func load() throws -> AppSettings {
        var values: [String: String] = [:]
        for row in try db.query("SELECT key, value FROM settings") { values[row.text("key")] = row.text("value") }

        return AppSettings(
            historyStartDate: ISODate(values["history_start_date"] ?? "") ?? ISODate("2026-08-31")!,
            dayLabelMode: DayLabelMode(rawValue: values["day_label_mode"] ?? "") ?? .number,
            deload: DeloadSettings(
                enabled: values["deload_enabled"] == "1",
                weightMultiplier: Double(values["deload_weight_multiplier"] ?? "") ?? 1,
                repsMultiplier: Double(values["deload_reps_multiplier"] ?? "") ?? 0.75
            ),
            // Missing key (a database that was never upgraded) behaves like the default: ignore deload.
            ignoreDeloadSessions: values["ignore_deload_sessions"] != "0",
            proteinGramsPerLb: Double(values["protein_g_per_lb"] ?? "") ?? 1.2,
            fatPercent: Double(values["fat_percent_of_calories"] ?? "") ?? 25,
            measurementTolerancePercent: Double(values["measurement_tolerance_percent"] ?? "") ?? 3
        )
    }

    public func setMeasurementTolerancePercent(_ value: Double) throws {
        guard value.isFinite, (0...50).contains(value) else { throw ValidationError("Tolerance must be between 0% and 50%") }
        try save("measurement_tolerance_percent", String(value))
    }

    public func setHistoryStartDate(_ text: String) throws {
        guard let parsed = ISODate(text) else { throw ValidationError("Date is not valid") }
        try save("history_start_date", parsed.string)
    }

    public func setDayLabelMode(_ mode: DayLabelMode) throws { try save("day_label_mode", mode.rawValue) }
    public func setDeloadEnabled(_ enabled: Bool) throws { try save("deload_enabled", enabled ? "1" : "0") }
    public func setIgnoreDeloadSessions(_ ignore: Bool) throws { try save("ignore_deload_sessions", ignore ? "1" : "0") }

    public func setDeloadWeightMultiplier(_ value: Double) throws {
        try save("deload_weight_multiplier", String(try positiveMultiplier(value)))
    }

    public func setDeloadRepsMultiplier(_ value: Double) throws {
        try save("deload_reps_multiplier", String(try positiveMultiplier(value)))
    }

    public func setProteinGramsPerLb(_ value: Double) throws {
        guard value > 0 else { throw ValidationError("Protein must be greater than 0") }
        try save("protein_g_per_lb", String(value))
    }

    public func setFatPercent(_ value: Double) throws {
        guard (10...60).contains(value) else { throw ValidationError("Fat share must be between 10% and 60%") }
        try save("fat_percent_of_calories", String(value))
    }

    private func positiveMultiplier(_ value: Double) throws -> Double {
        guard value > 0 else { throw ValidationError("Multiplier must be greater than 0") }
        return value
    }

    private func save(_ key: String, _ value: String) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(value)])
    }
}
