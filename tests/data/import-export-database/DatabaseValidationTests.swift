import XCTest
@testable import FitnessCore

final class DatabaseValidationTests: DatabaseFileTestCase {
    private let notFitness = ValidationError("This is not a Fitness database")
    private let needsNewerApp = ValidationError("This database needs a newer app")

    /// Scenario: Reject a file that is not a valid database / a database from a newer app
    private func assertImportRejected(_ picked: URL, as expected: ValidationError, file: StaticString = #filePath, line: UInt = #line) throws {
        try installLiveDatabase(marker: "Mine")
        let before = try Data(contentsOf: location.databaseURL)

        XCTAssertThrowsError(try service.importDatabase(from: picked, clock: clock), file: file, line: line) {
            XCTAssertEqual($0 as? ValidationError, expected, file: file, line: line)
        }

        XCTAssertEqual(try Data(contentsOf: location.databaseURL), before, "nothing changes", file: file, line: line)
        XCTAssertFalse(FileManager.default.fileExists(atPath: location.backupsDirectory.path), file: file, line: line)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: liveDirectory.path), ["fitness.sqlite"], file: file, line: line)
    }

    func test_pdfLikeFile_isRejected() throws {
        let pdf = try write(Array("%PDF-1.7\n%âãÏÓ\n1 0 obj\n<< /Type /Catalog >>\nendobj\n".utf8), to: "plan.pdf")
        try assertImportRejected(pdf, as: notFitness)
    }

    func test_emptyFile_isRejected() throws {
        try assertImportRejected(try write([], to: "empty.sqlite"), as: notFitness)
    }

    func test_randomBytes_areRejected() throws {
        try assertImportRejected(try write((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }, to: "noise.sqlite"), as: notFitness)
    }

    func test_validHeaderButGarbageBody_isRejected() throws {
        let header = Array("SQLite format 3\0".utf8)
        try assertImportRejected(try write(header + [UInt8](repeating: 0xAB, count: 4096), to: "broken.sqlite"), as: notFitness)
    }

    func test_missingFile_isRejected() throws {
        XCTAssertThrowsError(try service.validate(fileAt: scratchURL("nope.sqlite"))) {
            XCTAssertEqual($0 as? ValidationError, notFitness)
        }
    }

    func test_sqliteFileWithWrongTables_isRejected() throws {
        let url = scratchURL("other.sqlite")
        let db = try Database(path: url.path)
        try db.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT)")
        try assertImportRejected(url, as: notFitness)
    }

    func test_sqliteFileMissingOneRequiredTable_isRejected() throws {
        let url = try makeFitnessDatabase(named: "partial.sqlite")
        let db = try Database(path: url.path)
        try db.execute("DROP TABLE calorie_entries")
        try assertImportRejected(url, as: notFitness)
    }

    func test_databaseFromNewerApp_isRejected() throws {
        try assertImportRejected(try makeFitnessDatabase(named: "future.sqlite", userVersion: 99), as: needsNewerApp)
    }

    func test_olderSchemaVersion_isAccepted() throws {
        let url = try makeFitnessDatabase(named: "old.sqlite", userVersion: 0)
        XCTAssertNoThrow(try service.validate(fileAt: url))
    }

    func test_currentSchemaVersion_isAccepted() throws {
        XCTAssertNoThrow(try service.validate(fileAt: try makeFitnessDatabase(named: "ok.sqlite")))
    }

    func test_validate_doesNotModifyTheFile() throws {
        let url = try makeFitnessDatabase(named: "ok.sqlite")
        let before = try Data(contentsOf: url)
        try service.validate(fileAt: url)
        XCTAssertEqual(try Data(contentsOf: url), before)
    }

    func test_openLiveDatabase_refusesNewerSchema() throws {
        try FileManager.default.copyItem(at: try makeFitnessDatabase(named: "future.sqlite", userVersion: 99), to: location.databaseURL)
        XCTAssertThrowsError(try service.openLiveDatabase()) {
            XCTAssertEqual($0 as? ValidationError, needsNewerApp)
        }
    }
}
