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
}
