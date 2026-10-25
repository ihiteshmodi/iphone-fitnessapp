import XCTest
@testable import FitnessCore

/// Scenarios from import-export-database.feature about finding a database that was copied into the app folder by hand.
final class FindDatabaseFilesTests: DatabaseFileTestCase {
    private func place(_ name: String, in folder: URL? = nil, marker: String = "Squat") throws -> URL {
        let target = (folder ?? liveDirectory).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: try makeFitnessDatabase(named: "src-\(UUID().uuidString).sqlite", marker: marker), to: target)
        return target
    }

    func testNothingFoundInAnEmptyFolder() {
        XCTAssertTrue(service.foundDatabases().isEmpty)
        XCTAssertTrue(service.folderListing().isEmpty)
    }

    // Scenario: A database with another name is found
    func testFindsAFitnessDatabaseWithAnotherName() throws {
        let renamed = try place("fitness 2.sqlite")
        XCTAssertEqual(service.foundDatabases().map(\.lastPathComponent), [renamed.lastPathComponent])
    }

    func testFindsFilesWithOtherDatabaseExtensions() throws {
        _ = try place("backup.sqlite3")
        _ = try place("data.DB")
        XCTAssertEqual(Set(service.foundDatabases().map(\.lastPathComponent)), ["backup.sqlite3", "data.DB"])
    }

    // Scenario: LiveContainer's legacy file picker copies the chosen file into an Inbox folder
    func testFindsFilesInTheInboxFolder() throws {
        _ = try place("fitness.sqlite", in: liveDirectory.appendingPathComponent("Inbox"))
        XCTAssertEqual(service.foundDatabases().map(\.lastPathComponent), ["fitness.sqlite"])
    }

    func testIgnoresFilesThatAreNotFitnessDatabases() throws {
        try Data("%PDF-1.4 not a database".utf8).write(to: liveDirectory.appendingPathComponent("notes.sqlite"))
        try Data("hello".utf8).write(to: liveDirectory.appendingPathComponent("readme.txt"))
        _ = try place("other.pdf")
        XCTAssertTrue(service.foundDatabases().isEmpty)
    }

    func testIgnoresTheLiveDatabaseTheBackupsAndSideFiles() throws {
        try installLiveDatabase(marker: "Live")
        _ = try place("fitness-before-import-2026-10-25-1.sqlite", in: location.backupsDirectory)
        try Data("wal".utf8).write(to: liveDirectory.appendingPathComponent("fitness.sqlite-wal"))
        XCTAssertTrue(service.foundDatabases().isEmpty)
    }

    func testNewestFileComesFirst() throws {
        let older = try place("old.sqlite")
        let newer = try place("new.sqlite")
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: newer.path)
        XCTAssertEqual(service.foundDatabases().map(\.lastPathComponent), ["new.sqlite", "old.sqlite"])
    }

    // Scenario: Use a found database
    func testAFoundDatabaseCanBeUsedWithoutAnyPicker() throws {
        let found = try place("fitness 2.sqlite", marker: "FromFolder")

        try service.importDatabase(from: found, clock: clock)

        XCTAssertEqual(try exerciseNames(at: location.databaseURL), ["FromFolder"])
        XCTAssertTrue(service.foundDatabases().isEmpty || service.foundDatabases().allSatisfy { $0 != location.databaseURL })
    }

    // Scenario: The screen shows what the app sees
    func testFolderListingNamesTheFilesTheAppSees() throws {
        _ = try place("fitness 2.sqlite")
        try Data("x".utf8).write(to: liveDirectory.appendingPathComponent("notes.txt"))
        try Data("x".utf8).write(to: liveDirectory.appendingPathComponent(".hidden"))
        XCTAssertEqual(service.folderListing(), ["fitness 2.sqlite", "notes.txt"])
    }

    func testFolderListingIsCappedSoAHugeFolderDoesNotFloodTheScreen() throws {
        for index in 0..<30 { try Data("x".utf8).write(to: liveDirectory.appendingPathComponent("file-\(String(format: "%02d", index)).txt")) }
        XCTAssertEqual(service.folderListing().count, 12)
    }

    func testTheLiveDatabaseIsStillFoundByItsExactName() throws {
        try installLiveDatabase(marker: "Live")
        XCTAssertNotNil(try service.openLiveDatabase())
    }
}
