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
    /// Where LiveContainer's legacy file picker copies a chosen file.
    public var inboxDirectory: URL { directory.appendingPathComponent("Inbox", isDirectory: true) }
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
            // Version 3: muscles the user chose per exercise (no rows = automatic).
            try db.execute("""
                CREATE TABLE IF NOT EXISTS exercise_muscles (
                    exercise_id INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
                    part        TEXT NOT NULL,
                    role        TEXT NOT NULL CHECK (role IN ('primary', 'secondary')),
                    PRIMARY KEY (exercise_id, part)
                )
                """)
            // Version 4: calories per day that apply from a date. The newest calories ever typed become the first default.
            try db.execute("""
                CREATE TABLE IF NOT EXISTS calorie_defaults (
                    effective_from TEXT PRIMARY KEY CHECK (effective_from GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
                    calories       REAL NOT NULL CHECK (calories > 0),
                    multiplier     REAL NOT NULL DEFAULT 1 CHECK (multiplier > 0)
                )
                """)
            try db.execute("""
                INSERT OR IGNORE INTO calorie_defaults (effective_from, calories, multiplier)
                SELECT logged_on, calories, multiplier FROM calorie_entries ORDER BY logged_on DESC LIMIT 1
                """)
            // Version 5: each measured site grows or reduces. Waist-type sites are the ones where less is better.
            let targetColumns = try db.query("PRAGMA table_info(measurement_targets)").map { $0.text("name") }
            if !targetColumns.contains("direction") {
                try db.execute("ALTER TABLE measurement_targets ADD COLUMN direction TEXT NOT NULL DEFAULT 'grow' CHECK (direction IN ('grow', 'reduce'))")
                try db.execute("""
                    UPDATE measurement_targets SET direction = 'reduce'
                    WHERE site IN ('Waist', 'Waist (belly button)', 'Body Fat (belly button)')
                    """)
            }
            // Version 6: warm-up sets per planned exercise. Existing sets stay main sets, with no warm-ups.
            let entryColumns = try db.query("PRAGMA table_info(plan_entries)").map { $0.text("name") }
            if !entryColumns.contains("warmup_sets") {
                try db.execute("ALTER TABLE plan_entries ADD COLUMN warmup_sets INTEGER NOT NULL DEFAULT 0 CHECK (warmup_sets BETWEEN 0 AND 3)")
            }
            // Version 7: the clean-form answers.
            try db.execute("""
                CREATE TABLE IF NOT EXISTS form_checks (
                    exercise_id  INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
                    performed_on TEXT NOT NULL CHECK (performed_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
                    clean        INTEGER NOT NULL CHECK (clean IN (0, 1)),
                    PRIMARY KEY (exercise_id, performed_on)
                )
                """)
            // Version 8: foods, recipes, the dated diet plan, unticked items, extras, and the diet rules.
            try db.execute("""
                CREATE TABLE IF NOT EXISTS foods (
                    id              INTEGER PRIMARY KEY,
                    name            TEXT NOT NULL UNIQUE COLLATE NOCASE,
                    kind            TEXT NOT NULL DEFAULT 'food' CHECK (kind IN ('food', 'topping', 'supplement', 'herb', 'liquid', 'packaged', 'recipe')),
                    unit            TEXT NOT NULL DEFAULT 'g',
                    base_qty        REAL NOT NULL DEFAULT 100 CHECK (base_qty > 0),
                    protein         REAL NOT NULL DEFAULT 0 CHECK (protein >= 0),
                    carbs           REAL NOT NULL DEFAULT 0 CHECK (carbs >= 0),
                    fat             REAL NOT NULL DEFAULT 0 CHECK (fat >= 0),
                    fiber           REAL NOT NULL DEFAULT 0 CHECK (fiber >= 0),
                    sat_fat         REAL NOT NULL DEFAULT 0 CHECK (sat_fat >= 0),
                    sodium          REAL NOT NULL DEFAULT 0 CHECK (sodium >= 0),
                    label_calories  REAL CHECK (label_calories IS NULL OR label_calories >= 0),
                    price           REAL CHECK (price IS NULL OR price >= 0),
                    pack_size       REAL CHECK (pack_size IS NULL OR pack_size > 0),
                    pieces_per_pack REAL CHECK (pieces_per_pack IS NULL OR pieces_per_pack > 0),
                    piece_weight    REAL CHECK (piece_weight IS NULL OR piece_weight > 0),
                    recipe_makes    REAL CHECK (recipe_makes IS NULL OR recipe_makes > 0),
                    notes           TEXT
                )
                """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS recipe_items (
                    recipe_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
                    food_id   INTEGER NOT NULL REFERENCES foods(id) ON DELETE RESTRICT,
                    position  INTEGER NOT NULL DEFAULT 1,
                    quantity  REAL NOT NULL CHECK (quantity > 0),
                    PRIMARY KEY (recipe_id, food_id)
                )
                """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS diet_plans (
                    effective_from TEXT PRIMARY KEY CHECK (effective_from GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')
                )
                """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS diet_plan_items (
                    id             INTEGER PRIMARY KEY,
                    plan_from      TEXT NOT NULL REFERENCES diet_plans(effective_from) ON DELETE CASCADE,
                    meal           TEXT NOT NULL,
                    position       INTEGER NOT NULL,
                    food_id        INTEGER NOT NULL REFERENCES foods(id) ON DELETE RESTRICT,
                    quantity       REAL NOT NULL CHECK (quantity > 0),
                    cycle_mode     TEXT NOT NULL DEFAULT 'daily' CHECK (cycle_mode IN ('daily', 'weeks', 'days', 'weekdays', 'training')),
                    cycle_on       INTEGER CHECK (cycle_on IS NULL OR cycle_on >= 1),
                    cycle_off      INTEGER CHECK (cycle_off IS NULL OR cycle_off >= 1),
                    cycle_start    TEXT CHECK (cycle_start IS NULL OR cycle_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
                    cycle_weekdays INTEGER CHECK (cycle_weekdays IS NULL OR cycle_weekdays BETWEEN 1 AND 127)
                )
                """)
            try db.execute("""
                CREATE TABLE IF NOT EXISTS diet_extras (
                    id      INTEGER PRIMARY KEY,
                    day     TEXT NOT NULL CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
                    food_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE RESTRICT,
                    amount  REAL NOT NULL CHECK (amount > 0),
                    pieces  REAL CHECK (pieces IS NULL OR pieces > 0)
                )
                """)
            try db.execute("CREATE INDEX IF NOT EXISTS diet_extras_by_day ON diet_extras(day)")
            try db.execute("""
                INSERT OR IGNORE INTO settings (key, value) VALUES
                    ('protein_min_g', '180'), ('diet_fat_percent', '20'), ('fat_ceiling_g_per_lb', '0.4')
                """)
            // Version 9: nothing counts until it is ticked. Items unticked for a day (version 8 stored those) become the
            // exception, so every earlier day keeps exactly what it counted.
            try db.execute("""
                CREATE TABLE IF NOT EXISTS diet_day_ticks (
                    day     TEXT NOT NULL CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
                    meal    TEXT NOT NULL,
                    food_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
                    PRIMARY KEY (day, meal, food_id)
                )
                """)
            let hasSkips = try !db.query("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'diet_day_skips'").isEmpty
            if hasSkips {
                try db.execute("""
                    WITH RECURSIVE
                      latest(day) AS (
                        SELECT MAX(d) FROM (
                          SELECT MAX(day) AS d FROM diet_extras UNION ALL SELECT MAX(day) FROM diet_day_skips
                          UNION ALL SELECT MAX(measured_on) FROM body_weights UNION ALL SELECT MAX(performed_on) FROM set_logs)),
                      days(day) AS (
                        SELECT MIN(effective_from) FROM diet_plans
                        UNION ALL SELECT date(days.day, '+1 day') FROM days, latest WHERE days.day < latest.day)
                    INSERT OR IGNORE INTO diet_day_ticks (day, meal, food_id)
                    SELECT d.day, i.meal, i.food_id
                    FROM days d
                    JOIN diet_plan_items i ON i.plan_from = (SELECT MAX(effective_from) FROM diet_plans WHERE effective_from <= d.day)
                    WHERE d.day IS NOT NULL
                      AND NOT EXISTS (SELECT 1 FROM diet_day_skips s WHERE s.day = d.day AND s.meal = i.meal AND s.food_id = i.food_id)
                    """)
                try db.execute("DROP TABLE diet_day_skips")
            }
            try db.execute("PRAGMA user_version = \(Schema.currentVersion)")
        }
    }

    // MARK: Find

    private static let databaseExtensions: Set<String> = ["sqlite", "sqlite3", "db"]
    private static let listingLimit = 12

    /// Fitness databases lying in the app folder under another name, for example a copy made by hand ("fitness 2.sqlite")
    /// or the Inbox copy made by LiveContainer's legacy file picker. Newest first. The live database and backups are skipped.
    public func foundDatabases() -> [URL] {
        let candidates = [location.directory, location.inboxDirectory].flatMap { files(in: $0) }
            .filter { Self.databaseExtensions.contains($0.pathExtension.lowercased()) }
            .filter { $0.standardizedFileURL != location.databaseURL.standardizedFileURL }
            .filter { (try? validate(fileAt: $0)) != nil }
        return candidates.sorted { modified($0) > modified($1) }
    }

    /// Names of the files in the app folder (hidden ones left out), so the screen can show what the app sees.
    public func folderListing() -> [String] {
        Array(files(in: location.directory).map(\.lastPathComponent).sorted().prefix(Self.listingLimit))
    }

    private func files(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
    }

    private func modified(_ url: URL) -> Date {
        ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
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
