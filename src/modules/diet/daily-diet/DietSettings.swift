import Foundation

/// What the diet is judged against. Fat follows the vault: 20-35 % of calories, and never under 0.8 g per kg of body weight.
public struct DietRules: Equatable {
    public var proteinMinimumGrams: Double
    public var fatMinPercent: Double
    public var fatMaxPercent: Double
    public var fatFloorGramsPerKg: Double

    public init(proteinMinimumGrams: Double, fatMinPercent: Double, fatMaxPercent: Double, fatFloorGramsPerKg: Double) {
        self.proteinMinimumGrams = proteinMinimumGrams
        self.fatMinPercent = fatMinPercent
        self.fatMaxPercent = fatMaxPercent
        self.fatFloorGramsPerKg = fatFloorGramsPerKg
    }
}

/// Protein minimum and the fat range. diet_fat_percent (once the fat share allowed) is now the bottom of the range.
public final class DietSettings {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func load() throws -> DietRules {
        var values: [String: Double] = [:]
        for row in try db.query("SELECT key, value FROM settings WHERE key IN ('protein_min_g', 'diet_fat_percent', 'fat_max_percent', 'fat_floor_g_per_kg')") {
            values[row.text("key")] = Double(row.text("value"))
        }
        return DietRules(proteinMinimumGrams: values["protein_min_g"] ?? 180,
                         fatMinPercent: values["diet_fat_percent"] ?? 20,
                         fatMaxPercent: values["fat_max_percent"] ?? 35,
                         fatFloorGramsPerKg: values["fat_floor_g_per_kg"] ?? 0.8)
    }

    public func setProteinMinimum(_ grams: Double) throws {
        guard grams.isFinite, grams > 0 else { throw ValidationError("Protein must be greater than 0") }
        try save("protein_min_g", grams)
    }

    public func setFatRange(minPercent: Double, maxPercent: Double) throws {
        guard minPercent.isFinite, maxPercent.isFinite, (1...100).contains(minPercent), (1...100).contains(maxPercent) else {
            throw ValidationError("Fat must be between 1% and 100% of calories")
        }
        guard minPercent <= maxPercent else { throw ValidationError("The lowest fat share cannot be above the highest") }
        try save("diet_fat_percent", minPercent)
        try save("fat_max_percent", maxPercent)
    }

    public func setFatFloor(gramsPerKg: Double) throws {
        guard gramsPerKg.isFinite, gramsPerKg >= 0 else { throw ValidationError("The fat floor cannot be negative") }
        try save("fat_floor_g_per_kg", gramsPerKg)
    }

    private func save(_ key: String, _ value: Double) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(String(value))])
    }
}
