import XCTest
@testable import FitnessCore

final class ImportExportDatabaseTests: DatabaseFileTestCase {
    private func backups() throws -> [String] {
        guard FileManager.default.fileExists(atPath: location.backupsDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: location.backupsDirectory.path).sorted()
    }

    // Scenario: First launch with no data
    func test_firstLaunch_hasNoDatabase() throws {
        XCTAssertFalse(location.exists)
        XCTAssertNil(try service.openLiveDatabase())
    }

    func test_defaultLocation_isTheAppDocumentsFolderSoItShowsInFilesAndLiveContainer() throws {
        let location = try AppDatabaseLocation.documents()
        XCTAssertEqual(location.databaseURL.lastPathComponent, "fitness.sqlite")
        XCTAssertEqual(location.databaseURL.deletingLastPathComponent().lastPathComponent, "Documents")
        XCTAssertEqual(location.backupsDirectory.deletingLastPathComponent(), location.directory)
        XCTAssertEqual(location.backupsDirectory.lastPathComponent, "Backups")
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: location.directory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    func test_aDatabaseDroppedIntoTheFolderIsOpenedWithoutImporting() throws {
        try FileManager.default.copyItem(at: try seededDatabaseCopy(), to: location.databaseURL)

        let live = try XCTUnwrap(try service.openLiveDatabase())

        XCTAssertGreaterThan(try live.query("SELECT COUNT(*) AS n FROM set_logs").first!.int("n"), 1000)
    }

    // Scenario: Start empty without any file
    func test_startEmpty_createsACurrentVersionDatabaseWithNoDataAndNoFile() throws {
        try service.createEmptyDatabase()

        let live = try XCTUnwrap(try service.openLiveDatabase())
        XCTAssertEqual(live.userVersion, Schema.currentVersion)
        XCTAssertEqual(try live.query("SELECT COUNT(*) AS n FROM plan_days").first!.int("n"), 0)
        XCTAssertEqual(try live.query("SELECT COUNT(*) AS n FROM set_logs").first!.int("n"), 0)
        XCTAssertEqual(try SettingsRepository(live).load().historyStartDate, date("2026-08-31"))
        XCTAssertNoThrow(try service.validate(fileAt: location.databaseURL))
    }

    func test_startEmpty_neverReplacesAnExistingDatabase() throws {
        try installLiveDatabase(marker: "Mine")

        XCTAssertThrowsError(try service.createEmptyDatabase()) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("A database already exists"))
        }
        XCTAssertEqual(try exerciseNames(at: location.databaseURL), ["Mine"])
    }

    func test_startEmpty_leavesNoTemporaryFilesBehind() throws {
        try service.createEmptyDatabase()

        let files = try FileManager.default.contentsOfDirectory(atPath: liveDirectory.path)
        XCTAssertEqual(files, ["fitness.sqlite"])
    }

    // Scenario: Import the seeded database
    func test_importSeededDatabase_opensWithPlanAndHistory() throws {
        let picked = try seededDatabaseCopy()

        try service.importDatabase(from: picked, clock: clock)

        XCTAssertTrue(location.exists)
        let live = try XCTUnwrap(try service.openLiveDatabase())
        XCTAssertGreaterThanOrEqual(try live.query("SELECT COUNT(*) AS n FROM plan_days").first!.int("n"), 1)
        XCTAssertGreaterThan(try live.query("SELECT COUNT(*) AS n FROM set_logs").first!.int("n"), 1000)
        XCTAssertEqual(try backups(), [], "no previous database, so nothing to back up")
        XCTAssertTrue(FileManager.default.fileExists(atPath: picked.path), "the picked file is left alone")
    }

    func test_importOverExistingDatabase_keepsSafetyBackup() throws {
        try installLiveDatabase(marker: "Old")
        let picked = try makeFitnessDatabase(named: "new.sqlite", marker: "New")

        try service.importDatabase(from: picked, clock: clock)

        XCTAssertEqual(try exerciseNames(at: location.databaseURL), ["New"])
        XCTAssertEqual(try backups(), ["fitness-before-import-2026-10-25-1.sqlite"])
        let backup = location.backupsDirectory.appendingPathComponent("fitness-before-import-2026-10-25-1.sqlite")
        XCTAssertEqual(try exerciseNames(at: backup), ["Old"])
    }

    func test_secondImportSameDay_neverOverwritesEarlierBackup() throws {
        try installLiveDatabase(marker: "First")
        try service.importDatabase(from: try makeFitnessDatabase(named: "b.sqlite", marker: "Second"), clock: clock)
        try service.importDatabase(from: try makeFitnessDatabase(named: "c.sqlite", marker: "Third"), clock: clock)

        XCTAssertEqual(try backups(), ["fitness-before-import-2026-10-25-1.sqlite", "fitness-before-import-2026-10-25-2.sqlite"])
        let dir = location.backupsDirectory
        XCTAssertEqual(try exerciseNames(at: dir.appendingPathComponent("fitness-before-import-2026-10-25-1.sqlite")), ["First"])
        XCTAssertEqual(try exerciseNames(at: dir.appendingPathComponent("fitness-before-import-2026-10-25-2.sqlite")), ["Second"])
        XCTAssertEqual(try exerciseNames(at: location.databaseURL), ["Third"])
    }

    func test_importRemovesStaleWalAndShmOfOldDatabase() throws {
        try installLiveDatabase(marker: "Old")
        let wal = URL(fileURLWithPath: location.databaseURL.path + "-wal")
        let shm = URL(fileURLWithPath: location.databaseURL.path + "-shm")
        try Data([1, 2, 3]).write(to: wal)
        try Data([4, 5, 6]).write(to: shm)

        try service.importDatabase(from: try makeFitnessDatabase(named: "new.sqlite", marker: "New"), clock: clock)

        XCTAssertFalse(FileManager.default.fileExists(atPath: wal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shm.path))
        XCTAssertEqual(try exerciseNames(at: location.databaseURL), ["New"])
    }

    func test_importLeavesNoTemporaryFilesBehind() throws {
        try service.importDatabase(from: try makeFitnessDatabase(named: "new.sqlite"), clock: clock)

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: liveDirectory.path), ["fitness.sqlite"])
    }

    func test_importThatFailsMidWay_keepsOldDatabaseUnchangedAndCleansUp() throws {
        try installLiveDatabase(marker: "Old")
        let before = try Data(contentsOf: location.databaseURL)
        // A plain file where the Backups folder must go makes the backup step fail after the copy was made.
        try Data("blocker".utf8).write(to: location.backupsDirectory)

        XCTAssertThrowsError(try service.importDatabase(from: try makeFitnessDatabase(named: "new.sqlite", marker: "New"), clock: clock))

        XCTAssertEqual(try Data(contentsOf: location.databaseURL), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: liveDirectory.path).sorted(), ["Backups", "fitness.sqlite"])
    }

    // Scenario: Export for the weekly Drive upload
    func test_export_writesDatedCopyThatValidatesWithSameRowCounts() throws {
        let picked = try seededDatabaseCopy()
        try service.importDatabase(from: picked, clock: clock)
        let live = try XCTUnwrap(try service.openLiveDatabase())
        let exportDirectory = scratchURL("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let exported = try service.export(from: live, clock: clock, to: exportDirectory)

        XCTAssertEqual(exported.lastPathComponent, "fitness-2026-10-25.sqlite")
        XCTAssertEqual(exported.deletingLastPathComponent().standardizedFileURL, exportDirectory.standardizedFileURL)
        XCTAssertNoThrow(try service.validate(fileAt: exported))
        for table in ["exercises", "plan_days", "plan_entries", "set_logs", "body_weights", "body_measurements", "measurement_targets", "calorie_entries", "settings"] {
            XCTAssertEqual(try count(table, at: exported), try count(table, at: location.databaseURL), table)
        }
    }

    func test_secondExportSameDay_getsNumericSuffix() throws {
        try installLiveDatabase(marker: "Squat")
        let live = try XCTUnwrap(try service.openLiveDatabase())
        let exportDirectory = scratchURL("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let names = try (0..<3).map { _ in try service.export(from: live, clock: clock, to: exportDirectory).lastPathComponent }

        XCTAssertEqual(names, ["fitness-2026-10-25.sqlite", "fitness-2026-10-25-2.sqlite", "fitness-2026-10-25-3.sqlite"])
    }

    func test_export_leavesLiveDatabaseUsableAndUnchanged() throws {
        try installLiveDatabase(marker: "Squat")
        let live = try XCTUnwrap(try service.openLiveDatabase())
        let exportDirectory = scratchURL("exports")
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let exported = try service.export(from: live, clock: clock, to: exportDirectory)
        try live.execute("INSERT INTO exercises (name, source) VALUES ('Deadlift', 'library')")

        XCTAssertEqual(try live.query("SELECT COUNT(*) AS n FROM exercises").first!.int("n"), 2)
        XCTAssertEqual(try exerciseNames(at: exported), ["Squat"], "the export is a snapshot")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: liveDirectory.path), ["fitness.sqlite"])
    }
}
