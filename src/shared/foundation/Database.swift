import Foundation
import SQLite3

public enum SQLValue: Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
}

extension SQLValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByNilLiteral {
    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int64) { self = .int(value) }
    public init(floatLiteral value: Double) { self = .double(value) }
    public init(nilLiteral: ()) { self = .null }

    public static func optional(_ value: String?) -> SQLValue { value.map { .text($0) } ?? .null }
    public static func optional(_ value: Double?) -> SQLValue { value.map { .double($0) } ?? .null }
    public static func optional(_ value: Int?) -> SQLValue { value.map { .int(Int64($0)) } ?? .null }
}

public struct DatabaseError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public var description: String { message }
}

public struct Row {
    fileprivate let columns: [String: SQLValue]

    public func int(_ name: String) -> Int { optionalInt(name) ?? 0 }
    public func double(_ name: String) -> Double { optionalDouble(name) ?? 0 }
    public func text(_ name: String) -> String { optionalText(name) ?? "" }

    public func optionalInt(_ name: String) -> Int? {
        switch columns[name] {
        case .int(let v): return Int(v)
        case .double(let v): return Int(v)
        default: return nil
        }
    }

    public func optionalDouble(_ name: String) -> Double? {
        switch columns[name] {
        case .double(let v): return v
        case .int(let v): return Double(v)
        default: return nil
        }
    }

    public func optionalText(_ name: String) -> String? {
        if case .text(let v) = columns[name] { return v }
        return nil
    }
}

/// Thin wrapper over the system SQLite. One connection per database file; not thread-safe, keep it on one actor.
public final class Database {
    private var handle: OpaquePointer?
    public let path: String

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            sqlite3_close(handle)
            throw DatabaseError(message: message)
        }
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit { sqlite3_close(handle) }

    /// Fresh database with the app schema, used by tests and first-run.
    public static func inMemory() throws -> Database {
        let db = try Database(path: ":memory:")
        try db.runScript(try Schema.sql())
        return db
    }

    public var lastInsertRowID: Int { Int(sqlite3_last_insert_rowid(handle)) }

    public var userVersion: Int {
        (try? query("PRAGMA user_version").first?.int("user_version")) ?? 0
    }

    public func runScript(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "script failed"
            sqlite3_free(errorPointer)
            throw DatabaseError(message: message)
        }
    }

    public func execute(_ sql: String, _ params: [SQLValue] = []) throws {
        _ = try run(sql, params, collectRows: false)
    }

    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [Row] {
        try run(sql, params, collectRows: true)
    }

    public func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func run(_ sql: String, _ params: [SQLValue], collectRows: Bool) throws -> [Row] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in params.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .null: sqlite3_bind_null(statement, position)
            case .int(let v): sqlite3_bind_int64(statement, position, v)
            case .double(let v): sqlite3_bind_double(statement, position, v)
            case .text(let v): sqlite3_bind_text(statement, position, v, -1, transient)
            }
        }

        var rows: [Row] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                guard collectRows else { continue }
                var columns: [String: SQLValue] = [:]
                for column in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, column))
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: columns[name] = .int(sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT: columns[name] = .double(sqlite3_column_double(statement, column))
                    case SQLITE_TEXT: columns[name] = .text(String(cString: sqlite3_column_text(statement, column)))
                    default: columns[name] = .null
                    }
                }
                rows.append(Row(columns: columns))
            } else if code == SQLITE_DONE {
                return rows
            } else {
                throw DatabaseError(message: String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}

public enum Schema {
    public static func sql() throws -> String {
        let bundle = Bundle.module
        let url = bundle.url(forResource: "schema", withExtension: "sql", subdirectory: "shared/database")
            ?? bundle.url(forResource: "schema", withExtension: "sql")
        guard let url else { throw DatabaseError(message: "schema.sql is missing from the bundle") }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Bump together with `PRAGMA user_version` in schema.sql, and add a step to `DatabaseFileService.migrate`.
    public static let currentVersion = 3
}
