import Foundation

/// A calendar day stored as `YYYY-MM-DD`, independent of time zone.
public struct ISODate: Hashable, Comparable, CustomStringConvertible {
    public let string: String

    private static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public init?(year: Int, month: Int, day: Int) {
        let components = DateComponents(calendar: Self.calendar, timeZone: Self.calendar.timeZone, year: year, month: month, day: day)
        guard let date = Self.calendar.date(from: components) else { return nil }
        let check = Self.calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        self.string = String(format: "%04d-%02d-%02d", year, month, day)
    }

    public init(date: Date, timeZone: TimeZone = .current) {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let parts = local.dateComponents([.year, .month, .day], from: date)
        self.string = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    private var date: Date {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        return Self.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    public func adding(days: Int) -> ISODate {
        ISODate(date: Self.calendar.date(byAdding: .day, value: days, to: date)!, timeZone: Self.calendar.timeZone)
    }

    /// Whole days from `other` to self (positive when self is later).
    public func days(since other: ISODate) -> Int {
        Self.calendar.dateComponents([.day], from: other.date, to: date).day!
    }

    /// ISO weekday: 1 = Monday ... 7 = Sunday.
    public var weekday: Int {
        let sundayBased = Self.calendar.component(.weekday, from: date)
        return sundayBased == 1 ? 7 : sundayBased - 1
    }

    public var description: String { string }
    public static func < (lhs: ISODate, rhs: ISODate) -> Bool { lhs.string < rhs.string }
}

/// Role for "what day is it today", so the domain never reads the system clock.
public protocol AppClock {
    func today() -> ISODate
}

public struct SystemClock: AppClock {
    public init() {}
    public func today() -> ISODate { ISODate(date: Date()) }
}

public struct FixedClock: AppClock {
    private let day: ISODate
    public init(_ day: ISODate) { self.day = day }
    public func today() -> ISODate { day }
}

public struct ValidationError: Error, Equatable, LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Python-compatible `round(x, places)`: correctly rounded, ties to even on the exact binary value.
public func pyRound(_ value: Double, _ places: Int = 2) -> Double {
    Double(String(format: "%.\(places)f", value)) ?? value
}
