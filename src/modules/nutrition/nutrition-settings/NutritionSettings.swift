import Foundation

/// How protein and fat are derived when cutting. Carbs fill whatever calories are left.
public struct MacroRules: Equatable {
    public var proteinGramsPerLb: Double
    public var fatPercent: Double

    public init(proteinGramsPerLb: Double, fatPercent: Double) {
        self.proteinGramsPerLb = proteinGramsPerLb
        self.fatPercent = fatPercent
    }
}

/// The nutrition knobs on the settings screen. Validation lives in `SettingsRepository`; this only narrows it to what nutrition needs.
public final class NutritionSettings {
    private let settings: SettingsRepository

    public init(_ db: Database) { settings = SettingsRepository(db) }

    public func rules() throws -> MacroRules {
        let loaded = try settings.load()
        return MacroRules(proteinGramsPerLb: loaded.proteinGramsPerLb, fatPercent: loaded.fatPercent)
    }

    public func setProteinGramsPerLb(_ value: Double) throws { try settings.setProteinGramsPerLb(value) }

    public func setFatPercent(_ value: Double) throws { try settings.setFatPercent(value) }
}
