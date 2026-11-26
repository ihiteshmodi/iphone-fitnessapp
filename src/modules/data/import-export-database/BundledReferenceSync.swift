import Foundation

/// Silently syncs non-personal bundled reference files (coach presets and food nutrient/GI values) on database open.
public enum BundledReferenceSync {
    private static let presetsSigKey = "bundled_presets_sig"
    private static let nutrientsSigKey = "bundled_nutrients_sig"

    /// Preloaded reference multivitamins created as 1-tablet supplements whenever present in the bundled CSV.
    public static let referenceMultivitaminNames: [String] = [
        "Centrum Men Multivitamin",
        "MuscleBlaze Biozyme 5 in 1 Multivitamin",
        "MuscleBlaze MB-Vite Daily Multivitamin",
        "A to Z Multivitamin",
    ]

    public static func sync(db: Database, presetsData: Data?, nutrientsCSV: String?) throws {
        if let presetsData {
            let sig = signature(of: presetsData)
            let storedSig = try setting(db, key: presetsSigKey)
            let hasPresets = !(try db.query("SELECT 1 FROM routines WHERE is_preset = 1 LIMIT 1")).isEmpty
            if storedSig != sig || !hasPresets {
                _ = try PresetImporter(db).load(presetsData)
                try setSetting(db, key: presetsSigKey, value: sig)
            }
        }
        if let nutrientsCSV {
            try ensureReferenceMultivitamins(in: nutrientsCSV, db: db)
            let sig = signature(of: Data(nutrientsCSV.utf8))
            let storedSig = try setting(db, key: nutrientsSigKey)
            if storedSig != sig {
                _ = try NutrientImporter(db).apply(nutrientsCSV, overwriteExisting: true)
                try setSetting(db, key: nutrientsSigKey, value: sig)
            } else {
                _ = try NutrientImporter(db).apply(nutrientsCSV, overwriteExisting: false)
            }
        }
    }

    private static func ensureReferenceMultivitamins(in csv: String, db: Database) throws {
        var namesInCSV: Set<String> = []
        for line in csv.split(whereSeparator: \.isNewline).dropFirst() {
            if let comma = line.firstIndex(of: ",") {
                namesInCSV.insert(line[..<comma].trimmingCharacters(in: .whitespaces))
            }
        }
        let library = FoodLibrary(db)
        for name in referenceMultivitaminNames where namesInCSV.contains(name) {
            if try library.food(named: name) == nil {
                _ = try library.add(FoodDraft(name: name, kind: .supplement, unit: "unit", baseQuantity: 1))
            }
        }
    }

    private static func setting(_ db: Database, key: String) throws -> String? {
        try db.query("SELECT value FROM settings WHERE key = ?", [.text(key)]).first?.optionalText("value")
    }

    private static func setSetting(_ db: Database, key: String, value: String) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(value)])
    }

    /// Deterministic FNV-1a 64-bit hex digest so bundled file updates trigger a refresh across launches.
    private static func signature(of data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return "\(data.count)-\(String(hash, radix: 16))"
    }
}
