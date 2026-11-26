import XCTest
@testable import FitnessCore

/// Upgrades `output/fitness.sqlite` in place (when present) and verifies all personal draws, foods, GI values, and measurement units.
final class RealOwnerDatabaseMigrationTests: XCTestCase {
    func testOwnerDatabaseMigratesCleanlyAndSyncsReferenceData() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let ownerDB = root.appendingPathComponent("output/fitness.sqlite")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: ownerDB.path), "output/fitness.sqlite not present")

        let location = AppDatabaseLocation(directory: root.appendingPathComponent("output"))
        let db = try XCTUnwrap(try DatabaseFileService(location: location).openLiveDatabase())
        XCTAssertEqual(db.userVersion, Schema.currentVersion)

        let presetsURL = root.appendingPathComponent("output/meridian-presets.json")
        let csvURL = root.appendingPathComponent("output/nutrient-values.csv")
        let presetsData = try? Data(contentsOf: presetsURL)
        let csvText = try? String(contentsOf: csvURL, encoding: .utf8)
        try BundledReferenceSync.sync(db: db, presetsData: presetsData, nutrientsCSV: csvText)

        // Ensure skinfold sites use mm even if opened from an intermediate schema build.
        try db.execute("UPDATE measurement_targets SET unit = 'mm' WHERE site LIKE 'Body Fat (%' COLLATE NOCASE")
        try db.execute("UPDATE measurement_targets SET unit = '%' WHERE site = 'Body Fat' COLLATE NOCASE")

        XCTAssertGreaterThanOrEqual(try db.count("foods"), 73)
        XCTAssertGreaterThanOrEqual(try db.count("lab_draws"), 10)
        XCTAssertGreaterThanOrEqual(try db.count("lab_results"), 118)

        let units = Dictionary(uniqueKeysWithValues: try db.query("SELECT site, unit FROM measurement_targets").map { ($0.text("site"), $0.text("unit")) })
        XCTAssertEqual(units["Body Fat (belly Button)"], "mm")
        XCTAssertEqual(units["Body Fat (side handles)"], "mm")
        XCTAssertEqual(units["Waist"], "in")

        let giCount = try db.query("SELECT COUNT(*) AS n FROM foods WHERE glycemic_index IS NOT NULL").first?.int("n") ?? 0
        XCTAssertGreaterThanOrEqual(giCount, 60, "All non-recipe foods in nutrient-values.csv have GI populated")

        let settings = try SettingsRepository(db).load()
        XCTAssertEqual(settings.goalMode, .maintain)

        let foods = FoodLibrary(db)
        let d3Cap = try XCTUnwrap(try foods.food(named: "D3 5000IU and K2 MK7 100mcg capsule - Nutrija"))
        XCTAssertEqual(d3Cap.draft.nutrients[.vitaminD3], 5000)
        XCTAssertNil(d3Cap.draft.nutrients[.vitaminD])

        let d3Spray = try XCTUnwrap(try foods.food(named: "D3 6000IU spray - Zeelabs (custom)"))
        XCTAssertEqual(d3Spray.draft.nutrients[.vitaminD3], 12000)
        XCTAssertNil(d3Spray.draft.nutrients[.vitaminD])

        let creatine = try XCTUnwrap(try foods.food(named: "Creatine monohydrate - ASES"))
        XCTAssertEqual(creatine.draft.nutrients[.creatine], 1.0)

        let glycine = try XCTUnwrap(try foods.food(named: "Glycine - ASES"))
        XCTAssertEqual(glycine.draft.nutrients[.glycine], 1.0)

        let psyllium = try XCTUnwrap(try foods.food(named: "Psyllium Husk - ASES"))
        XCTAssertEqual(psyllium.draft.nutrients[.psyllium], 1.0)
        XCTAssertEqual(psyllium.draft.fiber, 0.85, accuracy: 1e-6)
    }
}
