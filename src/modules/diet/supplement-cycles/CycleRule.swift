import Foundation

/// A set of weekdays, stored as a bit mask (Monday = 1 ... Sunday = 64).
public struct Weekdays: Equatable {
    public enum Day: Int, CaseIterable {
        case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday
    }

    public let mask: Int

    public init(_ days: [Day]) throws {
        try self.init(mask: days.reduce(0) { $0 | (1 << ($1.rawValue - 1)) })
    }

    public init(mask: Int) throws {
        guard (1...127).contains(mask) else { throw ValidationError("Choose at least one weekday") }
        self.mask = mask
    }

    private init(unchecked mask: Int) { self.mask = mask }

    public static let workdays = Weekdays(unchecked: 0b0011111)
    public static let weekend = Weekdays(unchecked: 0b1100000)

    /// ISO weekday: 1 = Monday ... 7 = Sunday.
    public func contains(isoWeekday: Int) -> Bool { mask & (1 << (isoWeekday - 1)) != 0 }

    public var days: [Day] { Day.allCases.filter { contains(isoWeekday: $0.rawValue) } }
}

/// Whether an item is on today, and where it is in its cycle.
public struct CycleState: Equatable {
    public let isOn: Bool
    /// Position inside the current on or off stretch, for cycles counted in days or weeks.
    public let dayInPhase: Int?
    public let phaseLength: Int?
    /// The first day on which the item switches between on and off; nil when it never does.
    public let nextChange: ISODate?
}

/// The columns a cycle is stored in on a plan item.
public struct CycleColumns: Equatable {
    public let mode: String
    public let on: Int?
    public let off: Int?
    public let start: String?
    public let weekdays: Int?
}

/// The days an item is taken. Pure: given a date (and the workout weekdays for training days) it says on or off.
public enum CycleRule: Equatable {
    case daily
    case training
    case weekdays(Weekdays)
    case counted(Counted)

    /// "X on, Y off" counted from a start date, in whole days or whole weeks.
    public struct Counted: Equatable {
        public let inWeeks: Bool
        public let on: Int
        public let off: Int
        public let start: ISODate

        fileprivate var unit: Int { inWeeks ? 7 : 1 }
    }

    /// Weeks on and off, counted Monday to Sunday from the Monday the first on week begins.
    public static func weeks(on: Int, off: Int, firstMonday: ISODate) throws -> CycleRule {
        try checkLengths(on, off)
        guard firstMonday.weekday == 1 else { throw ValidationError("A weekly cycle starts on a Monday") }
        return .counted(Counted(inWeeks: true, on: on, off: off, start: firstMonday))
    }

    /// Days on and off counted from any date.
    public static func days(on: Int, off: Int, start: ISODate) throws -> CycleRule {
        try checkLengths(on, off)
        return .counted(Counted(inWeeks: false, on: on, off: off, start: start))
    }

    private static func checkLengths(_ on: Int, _ off: Int) throws {
        guard on >= 1 else { throw ValidationError("Days or weeks on must be at least 1") }
        guard off >= 1 else { throw ValidationError("Days or weeks off must be at least 1") }
    }

    public func isOn(on date: ISODate, trainingWeekdays: Set<Int>) -> Bool {
        switch self {
        case .daily: return true
        case .training: return trainingWeekdays.isEmpty || trainingWeekdays.contains(date.weekday)
        case .weekdays(let days): return days.contains(isoWeekday: date.weekday)
        case .counted(let counted): return Self.position(of: date, in: counted).isOn
        }
    }

    public func state(on date: ISODate, trainingWeekdays: Set<Int>) -> CycleState {
        let isOn = isOn(on: date, trainingWeekdays: trainingWeekdays)
        if case .counted(let counted) = self {
            let position = Self.position(of: date, in: counted)
            return CycleState(isOn: isOn, dayInPhase: position.dayInPhase, phaseLength: position.length,
                              nextChange: date.adding(days: position.length - position.dayInPhase + 1))
        }
        let next = (1...14).lazy.map { date.adding(days: $0) }.first { self.isOn(on: $0, trainingWeekdays: trainingWeekdays) != isOn }
        return CycleState(isOn: isOn, dayInPhase: nil, phaseLength: nil, nextChange: next)
    }

    private static func position(of date: ISODate, in counted: Counted) -> (isOn: Bool, dayInPhase: Int, length: Int) {
        let onDays = counted.on * counted.unit
        let period = onDays + counted.off * counted.unit
        let offset = ((date.days(since: counted.start) % period) + period) % period
        return offset < onDays
            ? (true, offset + 1, onDays)
            : (false, offset - onDays + 1, counted.off * counted.unit)
    }

    // MARK: Stored form

    public var columns: CycleColumns {
        switch self {
        case .daily: return CycleColumns(mode: "daily", on: nil, off: nil, start: nil, weekdays: nil)
        case .training: return CycleColumns(mode: "training", on: nil, off: nil, start: nil, weekdays: nil)
        case .weekdays(let days): return CycleColumns(mode: "weekdays", on: nil, off: nil, start: nil, weekdays: days.mask)
        case .counted(let c): return CycleColumns(mode: c.inWeeks ? "weeks" : "days", on: c.on, off: c.off, start: c.start.string, weekdays: nil)
        }
    }

    public init(columns: CycleColumns) throws {
        switch columns.mode {
        case "daily": self = .daily
        case "training": self = .training
        case "weekdays": self = .weekdays(try Weekdays(mask: columns.weekdays ?? 0))
        case "weeks", "days":
            guard let on = columns.on, let off = columns.off, let text = columns.start, let start = ISODate(text) else {
                throw ValidationError("The cycle is incomplete")
            }
            self = columns.mode == "weeks" ? try Self.weeks(on: on, off: off, firstMonday: start) : try Self.days(on: on, off: off, start: start)
        default: throw ValidationError("Unknown cycle")
        }
    }
}
