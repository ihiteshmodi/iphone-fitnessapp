import Foundation

/// Where the live database file lives on disk.
public struct AppDatabaseLocation {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// The app's `Documents` folder. It is visible in the Files app (file sharing is on) and in LiveContainer's
    /// "Open Data Folder", so the database can be dropped in or copied out by hand.
    public static func documents(fileManager: FileManager = .default) throws -> AppDatabaseLocation {
        let directory = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return AppDatabaseLocation(directory: directory)
    }

    public var databaseURL: URL { directory.appendingPathComponent("fitness.sqlite") }
    public var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }
    public var exists: Bool { FileManager.default.fileExists(atPath: databaseURL.path) }
}

/// Imports, validates and exports the single SQLite file that holds all app data.
/// Callers must close any open connection to the live database before `importDatabase`,
/// and reopen it with `openLiveDatabase()` afterwards.
public struct DatabaseFileService {
    public static let notFitnessDatabase = "This is not a Fitness database"
    public static let needsNewerApp = "This database needs a newer app"

    static let requiredTables = [
        "exercises", "plan_days", "plan_entries", "set_logs", "body_weights",
        "body_measurements", "measurement_targets", "calorie_entries", "settings",
    ]
    private static let sqliteHeader = Array("SQLite format 3\0".utf8)

    public let location: AppDatabaseLocation

    public init(location: AppDatabaseLocation) { self.location = location }

    // MARK: Open

    /// Nil on first launch, before any database was imported.
    public func openLiveDatabase() throws -> Database? {
        guard location.exists else { return nil }
        let db = try Database(path: location.databaseURL.path)
        guard db.userVersion <= Schema.currentVersion else { throw ValidationError(Self.needsNewerApp) }
        try Self.migrate(db, from: db.userVersion)
        return db
    }

    /// Creates a brand-new database with the current schema and no data, for starting without any file.
    /// Never replaces an existing database.
    public func createEmptyDatabase() throws {
        guard !location.exists else { throw ValidationError("A database already exists") }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true)

        // Built under a temporary name and moved into place, so a crash never leaves a half-made database.
        let staged = location.directory.appendingPathComponent("fitness-new-\(UUID().uuidString).sqlite")
        defer { try? fileManager.removeItem(at: staged) }
        do {
            let db = try Database(path: staged.path)
            try db.runScript(try Schema.sql())
        }
        try fileManager.moveItem(at: staged, to: location.databaseURL)
    }

    /// Upgrades an older database in place. Each step checks what already exists, so a file whose version number is
    /// older than its actual schema (or a half-finished earlier upgrade) still ends up correct.
    static func migrate(_ db: Database, from version: Int) throws {
        guard version < Schema.currentVersion else { return }
        try db.transaction {
            // Version 2: sets remember whether deload was on, and a setting decides if they count for progress.
            let columns = try db.query("PRAGMA table_info(set_logs)").map { $0.text("name") }
            if !columns.contains("is_deload") {
                try db.execute("ALTER TABLE set_logs ADD COLUMN is_deload INTEGER NOT NULL DEFAULT 0 CHECK (is_deload IN (0, 1))")
            }
            try db.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('ignore_deload_sessions', '1')")
            try db.execute("PRAGMA user_version = \(Schema.currentVersion)")
        }
    }

    // MARK: Validate

    public func validate(fileAt url: URL) throws {
        let notFitness = ValidationError(Self.notFitnessDatabase)
        guard Self.hasSQLiteHeader(url) else { throw notFitness }

        let db: Database
        do { db = try Database(path: url.path, readOnly: true) } catch { throw notFitness }

        // A garbage body behind a valid header only shows up once SQLite reads pages.
        let tables: Set<String>
        do {
            tables = Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'table'").map { $0.text("name") })
        } catch { throw notFitness }
        guard Self.requiredTables.allSatisfy(tables.contains) else { throw notFitness }

        let integrity = try? db.query("PRAGMA integrity_check").map { $0.text("integrity_check") }
        guard integrity == ["ok"] else { throw notFitness }

        guard db.userVersion <= Schema.currentVersion else { throw ValidationError(Self.needsNewerApp) }
    }

    private static func hasSQLiteHeader(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: sqliteHeader.count)) ?? Data()
        return Array(header) == sqliteHeader
    }

    // MARK: Import

    /// Replaces the live database with `source`. The old one is kept in `Backups/` first, because an
    /// import is the one action that can destroy weeks of logs. The new file is staged next to the
    /// live one so the final move is a same-volume atomic rename.
    public func importDatabase(from source: URL, clock: AppClock) throws {
        try validate(fileAt: source)

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true)
        let staged = location.directory.appendingPathComponent(".import-\(UUID().uuidString).tmp")
        do {
            try fileManager.copyItem(at: source, to: staged)
            try validate(fileAt: staged)
            let stagedVersion = try Database(path: staged.path, readOnly: true).userVersion
            try Self.migrateFile(at: staged, from: stagedVersion)

            if location.exists { try backUpLiveDatabase(clock: clock) }
            try replaceLiveDatabase(with: staged)
        } catch {
            try? fileManager.removeItem(at: staged)
            throw error
        }
    }

    /// Hook for future schema upgrades; nothing to do while only version 1 exists.
    private static func migrateFile(at url: URL, from version: Int) throws {}

    private func backUpLiveDatabase(clock: AppClock) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: location.backupsDirectory, withIntermediateDirectories: true)

        var counter = 1
        var backup: URL
        repeat {
            backup = location.backupsDirectory.appendingPathComponent("fitness-before-import-\(clock.today())-\(counter).sqlite")
            counter += 1
        } while fileManager.fileExists(atPath: backup.path)

        try fileManager.moveItem(at: location.databaseURL, to: backup)
        // Leftover journal files would otherwise be applied to the new database.
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fileManager.removeItem(atPath: location.databaseURL.path + suffix)
        }
    }

    private func replaceLiveDatabase(with staged: URL) throws {
        try FileManager.default.moveItem(at: staged, to: location.databaseURL)
    }

    // MARK: Export

    /// Writes a dated copy into `directory`. `VACUUM INTO` takes a consistent snapshot through the live
    /// connection, so a plain file copy never catches a half-written page or misses WAL content.
    public func export(from db: Database, clock: AppClock, to directory: URL) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var target = directory.appendingPathComponent("fitness-\(clock.today()).sqlite")
        var suffix = 2
        while fileManager.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("fitness-\(clock.today())-\(suffix).sqlite")
            suffix += 1
        }

        do {
            try db.execute("VACUUM INTO ?", [.text(target.path)])
            try validate(fileAt: target)
        } catch {
            try? fileManager.removeItem(at: target)
            throw error
        }
        return target
    }
}
