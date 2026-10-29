import Foundation

/// The three numbers the diet is judged against.
public struct DietRules: Equatable {
    public var proteinMinimumGrams: Double
    public var fatPercentOfCalories: Double
    public var fatCeilingGramsPerPound: Double

    public init(proteinMinimumGrams: Double, fatPercentOfCalories: Double, fatCeilingGramsPerPound: Double) {
        self.proteinMinimumGrams = proteinMinimumGrams
        self.fatPercentOfCalories = fatPercentOfCalories
        self.fatCeilingGramsPerPound = fatCeilingGramsPerPound
    }
}

/// Protein minimum, the share of calories allowed as fat, and the weight-based fat ceiling.
public final class DietSettings {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func load() throws -> DietRules {
        var values: [String: Double] = [:]
        for row in try db.query("SELECT key, value FROM settings WHERE key IN ('protein_min_g', 'diet_fat_percent', 'fat_ceiling_g_per_lb')") {
            values[row.text("key")] = Double(row.text("value"))
        }
        return DietRules(proteinMinimumGrams: values["protein_min_g"] ?? 180,
                         fatPercentOfCalories: values["diet_fat_percent"] ?? 20,
                         fatCeilingGramsPerPound: values["fat_ceiling_g_per_lb"] ?? 0.4)
    }

    public func setProteinMinimum(_ grams: Double) throws {
        guard grams.isFinite, grams > 0 else { throw ValidationError("Protein must be greater than 0") }
        try save("protein_min_g", grams)
    }

    public func setFatPercent(_ percent: Double) throws {
        guard percent.isFinite, (1...100).contains(percent) else { throw ValidationError("Fat must be between 1% and 100% of calories") }
        try save("diet_fat_percent", percent)
    }

    public func setFatCeilingPerPound(_ grams: Double) throws {
        guard grams.isFinite, grams > 0 else { throw ValidationError("The fat ceiling must be greater than 0") }
        try save("fat_ceiling_g_per_lb", grams)
    }

    private func save(_ key: String, _ value: Double) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(String(value))])
    }
}
