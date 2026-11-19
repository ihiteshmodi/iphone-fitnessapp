import XCTest
@testable import FitnessCore

final class LabSettingsTests: XCTestCase {
    func testDefaultsAreMaleNoBirthDateAndDrugNotesHidden() throws {
        let settings = LabSettings(try Database.inMemory())

        let loaded = try settings.load()

        XCTAssertEqual(loaded.sex, .male)
        XCTAssertNil(loaded.birthDate)
        XCTAssertFalse(loaded.showDrugNotes)
    }

    func testChangesAreKept() throws {
        let db = try Database.inMemory()
        let settings = LabSettings(db)

        try settings.setBirthDate(date("1990-01-15"))
        try settings.setShowDrugNotes(true)
        try settings.setSex(.female)

        let loaded = try LabSettings(db).load()
        XCTAssertEqual(loaded.birthDate, date("1990-01-15"))
        XCTAssertTrue(loaded.showDrugNotes)
        XCTAssertEqual(loaded.sex, .female)
    }
}
