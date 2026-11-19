import XCTest
@testable import FitnessCore

final class LabHistoryTests: XCTestCase {
    private let csv = """
    kind,date,time,lab,marker_id,value,unit,lab_low,lab_high,note
    result,2026-05-03,08:15,Lab A,ferritin,48,ng/mL,30,400,
    result,2026-05-03,08:15,Lab A,glucose,83,mg/dL,70,100,fasting by test name
    result,2026-10-01,,Lab B,glucose,5.0,mmol/L,,,
    result,2026-10-01,,Lab B,made-up-marker,1,x,,,
    setting,,,,labs_birth_date,1990-01-15,,,,
    """
    private var db: Database!
    private var draws: LabDrawService!
    private var importer: LabHistoryImporter!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        let catalogue = try LabCatalogue(data: Data(fixtureCatalogueJSON.utf8))
        draws = LabDrawService(db, catalogue: catalogue)
        importer = LabHistoryImporter(db, catalogue: catalogue)
    }

    func testResultsBecomeDrawsByDateAndLab() throws {
        let result = try importer.apply(csv)

        XCTAssertEqual(result.drawsAdded, 2)
        XCTAssertEqual(result.resultsAdded, 3)
        XCTAssertEqual(try draws.draws().map(\.draft.lab), ["Lab B", "Lab A"])
        let ferritin = try XCTUnwrap(try draws.history(of: "ferritin").first)
        XCTAssertEqual([ferritin.labLow, ferritin.labHigh], [30, 400])
        XCTAssertEqual(try draws.draws().last?.draft.time, "08:15")
    }

    func testApplyingTwiceAddsNothing() throws {
        try importer.apply(csv)

        let again = try importer.apply(csv)

        XCTAssertEqual([again.drawsAdded, again.resultsAdded], [0, 0])
        XCTAssertEqual(try draws.history(of: "glucose").count, 2)
    }

    func testUnknownMarkersAreSkippedWithAReason() throws {
        let result = try importer.apply(csv)

        XCTAssertEqual(result.skipped.count, 1)
        XCTAssertTrue(result.skipped[0].contains("made-up-marker"), result.skipped[0])
    }

    func testTheBirthDateSettingIsApplied() throws {
        try importer.apply(csv)

        XCTAssertEqual(try LabSettings(db).load().birthDate, date("1990-01-15"))
    }
}
