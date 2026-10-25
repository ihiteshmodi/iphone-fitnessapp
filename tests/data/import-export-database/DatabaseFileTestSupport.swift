import XCTest
import SQLite3
@testable import FitnessCore

/// Shared scratch-directory and fixture helpers for the import/export tests.
class DatabaseFileTestCase: XCTestCase {
    var root: URL!
    var liveDirectory: URL!
    var service: DatabaseFileService!
    let clock = FixedClock(date("2026-10-25"))

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        liveDirectory = root.appendingPathComponent("live")
        try FileManager.default.createDirectory(at: liveDirectory, withIntermediateDirectories: true)
        service = DatabaseFileService(location: AppDatabaseLocation(directory: liveDirectory))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    var location: AppDatabaseLocation { service.location }

    func scratchURL(_ name: String) -> URL { root.appendingPathComponent(name) }

    /// A valid app database with one exercise carrying `marker` as its name, so tests can tell databases apart.
    @discardableResult
    func makeFitnessDatabase(named name: String, marker: String = "Squat", userVersion: Int? = nil) throws -> URL {
        let url = scratchURL(name)
        let db = try Database(path: url.path)
        try db.runScript(try Schema.sql())
        try db.execute("INSERT INTO exercises (name, source) VALUES (?, 'library')", [.text(marker)])
        if let userVersion { try db.runScript("PRAGMA user_version = \(userVersion)") }
        return url
    }

    func installLiveDatabase(marker: String) throws {
        let url = try makeFitnessDatabase(named: "seed-\(UUID().uuidString).sqlite", marker: marker)
        try FileManager.default.copyItem(at: url, to: location.databaseURL)
    }

    func exerciseNames(at url: URL) throws -> [String] {
        let db = try Database(path: url.path, readOnly: true)
        return try db.query("SELECT name FROM exercises ORDER BY id").map { $0.text("name") }
    }

    func count(_ table: String, at url: URL) throws -> Int {
        let db = try Database(path: url.path, readOnly: true)
        return try db.query("SELECT COUNT(*) AS n FROM \(table)").first!.int("n")
    }

    func write(_ bytes: [UInt8], to name: String) throws -> URL {
        let url = scratchURL(name)
        try Data(bytes).write(to: url)
        return url
    }

    func seededDatabaseCopy() throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("output/fitness.sqlite")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: source.path), "output/fitness.sqlite is missing")
        let copy = scratchURL("picked-fitness.sqlite")
        try FileManager.default.copyItem(at: source, to: copy)
        return copy
    }
}
