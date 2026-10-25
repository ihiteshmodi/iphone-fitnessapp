import Foundation

public struct Exercise: Equatable, Identifiable {
    public let id: Int
    public var name: String
    public var muscle: String?
    public var instructions: String?
    /// library = from the original spreadsheet mapping, log = only seen in old logs, user = created in the app
    public var source: String
}

/// The exercise library: names, muscles and how-to instructions. Names are unique ignoring case and spaces.
public final class ExerciseRepository {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func all() throws -> [Exercise] { try search("", muscle: nil) }

    public func search(_ text: String, muscle: String?) throws -> [Exercise] {
        var sql = "SELECT id, name, muscle, instructions, source FROM exercises WHERE 1 = 1"
        var params: [SQLValue] = []
        let needle = text.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            sql += " AND name LIKE ?"
            params.append(.text("%\(needle)%"))
        }
        if let muscle {
            sql += " AND muscle = ? COLLATE NOCASE"
            params.append(.text(muscle))
        }
        sql += " ORDER BY name COLLATE NOCASE"
        return try db.query(sql, params).map(Self.exercise)
    }

    public func exercise(id: Int) throws -> Exercise? {
        try db.query("SELECT id, name, muscle, instructions, source FROM exercises WHERE id = ?", [.int(Int64(id))]).first.map(Self.exercise)
    }

    public func exercise(named name: String) throws -> Exercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return try db.query("SELECT id, name, muscle, instructions, source FROM exercises WHERE name = ? COLLATE NOCASE", [.text(trimmed)])
            .first.map(Self.exercise)
    }

    public func muscles() throws -> [String] {
        try db.query("SELECT DISTINCT muscle FROM exercises WHERE muscle IS NOT NULL ORDER BY muscle COLLATE NOCASE")
            .compactMap { $0.optionalText("muscle") }
    }

    @discardableResult
    public func add(name: String, muscle: String?, instructions: String?, source: String = "user") throws -> Exercise {
        let cleaned = try validatedName(name, excluding: nil)
        try db.execute("INSERT INTO exercises (name, muscle, instructions, source) VALUES (?, ?, ?, ?)",
                       [.text(cleaned), .optional(blankToNil(muscle)), .optional(blankToNil(instructions)), .text(source)])
        return try exercise(id: db.lastInsertRowID)!
    }

    public func update(id: Int, name: String, muscle: String?, instructions: String?) throws {
        let cleaned = try validatedName(name, excluding: id)
        try db.execute("UPDATE exercises SET name = ?, muscle = ?, instructions = ? WHERE id = ?",
                       [.text(cleaned), .optional(blankToNil(muscle)), .optional(blankToNil(instructions)), .int(Int64(id))])
    }

    public func delete(id: Int) throws {
        let used = try db.query("SELECT (SELECT COUNT(*) FROM set_logs WHERE exercise_id = ?1) AS sets, (SELECT COUNT(*) FROM plan_entries WHERE exercise_id = ?1) AS planned",
                                [.int(Int64(id))]).first
        if (used?.int("sets") ?? 0) > 0 { throw ValidationError("This exercise has history. Remove it from days instead") }
        if (used?.int("planned") ?? 0) > 0 { throw ValidationError("Remove it from days first") }
        try db.execute("DELETE FROM exercises WHERE id = ?", [.int(Int64(id))])
    }

    private func validatedName(_ name: String, excluding id: Int?) throws -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ValidationError("Name is required") }
        if let existing = try exercise(named: cleaned), existing.id != id { throw ValidationError("Exercise already exists") }
        return cleaned
    }

    private func blankToNil(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func exercise(_ row: Row) -> Exercise {
        Exercise(id: row.int("id"), name: row.text("name"), muscle: row.optionalText("muscle"),
                 instructions: row.optionalText("instructions"), source: row.text("source"))
    }
}
