import XCTest
@testable import FitnessCore

final class BundledReferenceSyncTests: XCTestCase {
    func testSyncLoadsCoachPresetsAndAppliesNutrientsAndPreservesManualEditsUntilCSVChanges() throws {
        let db = try Database.inMemory()
        let foods = FoodLibrary(db)
        let oatsID = try foods.add(FoodDraft(name: "Rolled Oats", kind: .food, unit: "g", baseQuantity: 100,
                                             protein: 13, carbs: 68, fat: 7, fiber: 10))

        let presetsJSON = """
        {
          "routines": [
            {
              "name": "Meridian · Upper",
              "exercises": [
                { "name": "Incline Press", "sets": 3, "min_reps": 8, "max_reps": 10 }
              ]
            }
          ],
          "workouts": []
        }
        """.data(using: .utf8)

        let csvV1 = """
        name,key,amount
        Rolled Oats,glycemic_index,55
        Rolled Oats,magnesium,138
        Banana,glycemic_index,51
        """

        try BundledReferenceSync.sync(db: db, presetsData: presetsJSON, nutrientsCSV: csvV1)

        XCTAssertEqual(try RoutineService(db).all().map(\.name), ["Meridian · Upper"])
        let syncedOats = try XCTUnwrap(try foods.food(named: "Rolled Oats"))
        XCTAssertEqual(syncedOats.draft.glycemicIndex, 55)
        XCTAssertEqual(syncedOats.draft.nutrients[.magnesium], 138)

        // User manually customizes Rolled Oats GI to 60 and adds Banana later.
        var customDraft = syncedOats.draft
        customDraft.glycemicIndex = 60
        try foods.update(oatsID, customDraft)
        _ = try foods.add(FoodDraft(name: "Banana", kind: .food, unit: "g", baseQuantity: 100,
                                    protein: 1.1, carbs: 22.8, fat: 0.3, fiber: 2.6))

        // Re-syncing the unchanged CSV preserves user's manual GI edit on Oats while filling Banana's missing GI.
        try BundledReferenceSync.sync(db: db, presetsData: presetsJSON, nutrientsCSV: csvV1)
        XCTAssertEqual(try RoutineService(db).all().count, 1)
        XCTAssertEqual(try foods.food(named: "Rolled Oats")?.draft.glycemicIndex, 60)
        XCTAssertEqual(try foods.food(named: "Banana")?.draft.glycemicIndex, 51)

        // Updating the bundled CSV in a new app release applies the new reference values.
        let csvV2 = """
        name,key,amount
        Rolled Oats,glycemic_index,55
        Rolled Oats,magnesium,142
        Banana,glycemic_index,51
        """
        try BundledReferenceSync.sync(db: db, presetsData: presetsJSON, nutrientsCSV: csvV2)
        XCTAssertEqual(try foods.food(named: "Rolled Oats")?.draft.nutrients[.magnesium], 142)
    }

    func testSyncCreatesBundledMultivitaminsWithBrandClaimValuesWithoutTouchingDietPlan() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let csvText = try String(contentsOf: root.appendingPathComponent("output/nutrient-values.csv"), encoding: .utf8)

        let db = try Database.inMemory()
        try BundledReferenceSync.sync(db: db, presetsData: nil, nutrientsCSV: csvText)

        let foods = FoodLibrary(db)
        let centrum = try XCTUnwrap(try foods.food(named: "Centrum Men Multivitamin"))
        XCTAssertEqual(centrum.kind, .supplement)
        XCTAssertTrue(MultivitaminWhatIf.isMultivitamin(centrum.draft))
        XCTAssertEqual(centrum.draft.nutrients[.vitaminA], 800)
        XCTAssertEqual(centrum.draft.nutrients[.b3], 15)
        XCTAssertEqual(centrum.draft.nutrients[.selenium], 17.5)

        let biozyme = try XCTUnwrap(try foods.food(named: "MuscleBlaze Biozyme 5 in 1 Multivitamin"))
        XCTAssertTrue(MultivitaminWhatIf.isMultivitamin(biozyme.draft))
        XCTAssertEqual(biozyme.draft.nutrients[.vitaminA], 1000)
        XCTAssertEqual(biozyme.draft.nutrients[.copper], 1.7)
        XCTAssertEqual(biozyme.draft.nutrients[.selenium], 40)

        let mbVite = try XCTUnwrap(try foods.food(named: "MuscleBlaze MB-Vite Daily Multivitamin"))
        XCTAssertTrue(MultivitaminWhatIf.isMultivitamin(mbVite.draft))
        XCTAssertEqual(mbVite.draft.nutrients[.vitaminC], 65)
        XCTAssertEqual(mbVite.draft.nutrients[.calcium], 100)
        XCTAssertEqual(mbVite.draft.nutrients[.zinc], 13.2)

        let aToZ = try XCTUnwrap(try foods.food(named: "A to Z Multivitamin"))
        XCTAssertTrue(MultivitaminWhatIf.isMultivitamin(aToZ.draft))
        XCTAssertEqual(aToZ.draft.nutrients[.vitaminC], 40)
        XCTAssertEqual(aToZ.draft.nutrients[.b5], 4)
        XCTAssertEqual(aToZ.draft.nutrients[.vitaminD], 5)
        XCTAssertEqual(aToZ.draft.nutrients[.selenium], 30)

        XCTAssertNil(try DietPlanService(db).plan(inForceOn: date("2026-11-26")), "Sync must never alter active meal plans")
    }
}
