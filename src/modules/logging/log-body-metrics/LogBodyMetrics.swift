import Foundation

public struct BodyWeightEntry: Equatable, Identifiable {
    public let id: Int
    public let date: ISODate
    public let kg: Double
}

/// Body weight entries. Measurement readings are logged through `MeasurementService` so there is one implementation of that rule.
public final class LogBodyMetrics {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    @discardableResult
    public func logWeight(kg: Double, on date: String) throws -> Int {
        try validate(kg: kg)
        let day = try validDate(date)
        try db.execute("INSERT INTO body_weights (measured_on, weight_kg) VALUES (?, ?)", [.text(day.string), .double(kg)])
        return db.lastInsertRowID
    }

    @discardableResult
    public func logWeight(kg: Double, on date: ISODate) throws -> Int {
        try logWeight(kg: kg, on: date.string)
    }

    /// Leave `date` nil to keep the day and only fix the number.
    public func updateWeight(id: Int, kg: Double, on date: String? = nil) throws {
        try validate(kg: kg)
        let day = try date.map(validDate)
        guard try db.query("SELECT 1 AS found FROM body_weights WHERE id = ?", [.int(Int64(id))]).first != nil else {
            throw ValidationError("Entry not found")
        }
        try db.execute("UPDATE body_weights SET weight_kg = ?, measured_on = COALESCE(?, measured_on) WHERE id = ?",
                       [.double(kg), .optional(day?.string), .int(Int64(id))])
    }

    public func deleteWeight(id: Int) throws {
        try db.execute("DELETE FROM body_weights WHERE id = ?", [.int(Int64(id))])
    }

    /// Newest first.
    public func recentWeights(limit: Int = 30) throws -> [BodyWeightEntry] {
        try db.query("SELECT id, measured_on, weight_kg FROM body_weights ORDER BY measured_on DESC, id DESC LIMIT ?",
                     [.int(Int64(limit))]).compactMap { row in
            guard let day = ISODate(row.text("measured_on")) else { return nil }
            return BodyWeightEntry(id: row.int("id"), date: day, kg: row.double("weight_kg"))
        }
    }

    private func validate(kg: Double) throws {
        guard kg.isFinite, kg > 0 else { throw ValidationError("Body weight must be above 0") }
    }

    private func validDate(_ text: String) throws -> ISODate {
        guard let day = ISODate(text) else { throw ValidationError("Date is not valid") }
        return day
    }
}
