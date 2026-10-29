import Foundation

extension ISODate {
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "2026-11-09" -> "9 Nov"
    public var shortLabel: String {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return string }
        return "\(parts[2]) \(Self.monthNames[parts[1] - 1])"
    }

    /// The Monday of the week this day is in (the day itself when it is a Monday).
    public var mondayOfWeek: ISODate { adding(days: 1 - weekday) }
}

public struct CycleCell: Equatable {
    public let date: ISODate
    public let isOn: Bool
    public let isToday: Bool
}

/// Words and calendar rows for a cycle. Pure, so every screen says the same thing.
public enum CyclePresentation {
    private static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    public static func summary(_ rule: CycleRule) -> String {
        switch rule {
        case .daily: return "Every day"
        case .training: return "Training days"
        case .weekdays(let days):
            if days == .workdays { return "Weekdays" }
            if days == .weekend { return "Weekends" }
            return days.days.map { dayNames[$0.rawValue - 1] }.joined(separator: ", ")
        case .counted(let counted):
            if !counted.inWeeks && counted.on == 1 && counted.off == 1 { return "Every other day" }
            let unit = counted.inWeeks ? "week" : "day"
            func amount(_ n: Int) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
            return "\(amount(counted.on)) on · \(amount(counted.off)) off"
        }
    }

    /// Where the item is today: "Day 4 of 14 · off from 9 Nov", "Off · back on 16 Nov", "On".
    public static func status(_ state: CycleState) -> String {
        if state.isOn {
            let change = state.nextChange.map { "off from \($0.shortLabel)" }
            let position = state.dayInPhase.flatMap { day in state.phaseLength.map { "Day \(day) of \($0)" } } ?? "On"
            return [position, change].compactMap { $0 }.joined(separator: " · ")
        }
        return state.nextChange.map { "Off · back on \($0.shortLabel)" } ?? "Off"
    }

    /// `weeks` rows of seven days, each row starting on a Monday, beginning with the week of `weekOf`.
    public static func grid(rule: CycleRule, weeks: Int, weekOf: ISODate, today: ISODate, trainingWeekdays: Set<Int>) -> [[CycleCell]] {
        let first = weekOf.mondayOfWeek
        return (0..<weeks).map { week in
            (0..<7).map { dayIndex in
                let day = first.adding(days: week * 7 + dayIndex)
                return CycleCell(date: day, isOn: rule.isOn(on: day, trainingWeekdays: trainingWeekdays), isToday: day == today)
            }
        }
    }
}

/// What the cycle editor is showing while the person chooses. `rule()` turns it into a validated `CycleRule`.
public struct CycleDraft: Equatable {
    public enum Mode: Equatable { case everyDay, weeks, days, weekdays, training }

    public var mode: Mode = .everyDay
    public var weeksOn = 2
    public var weeksOff = 1
    public var daysOn = 5
    public var daysOff = 2
    /// The date picked for the start; a weekly cycle moves it back to that week's Monday.
    public var start: ISODate
    public var weekdays: Set<Weekdays.Day> = [.monday, .wednesday, .friday]

    public init(today: ISODate) { start = today }

    public init(rule: CycleRule, today: ISODate) {
        start = today
        switch rule {
        case .daily: mode = .everyDay
        case .training: mode = .training
        case .weekdays(let days):
            mode = .weekdays
            weekdays = Set(days.days)
        case .counted(let counted):
            start = counted.start
            if counted.inWeeks {
                mode = .weeks
                weeksOn = counted.on
                weeksOff = counted.off
            } else {
                mode = .days
                daysOn = counted.on
                daysOff = counted.off
            }
        }
    }

    public var firstMonday: ISODate { start.mondayOfWeek }

    public func rule() throws -> CycleRule {
        switch mode {
        case .everyDay: return .daily
        case .training: return .training
        case .weeks: return try .weeks(on: weeksOn, off: weeksOff, firstMonday: firstMonday)
        case .days: return try .days(on: daysOn, off: daysOff, start: start)
        case .weekdays: return .weekdays(try Weekdays(Array(weekdays)))
        }
    }

    public mutating func applyPreset(on: Int, off: Int) {
        mode = .weeks
        weeksOn = on
        weeksOff = off
    }

    public func matchesPreset(on: Int, off: Int) -> Bool { mode == .weeks && weeksOn == on && weeksOff == off }

    public mutating func selectWeekdays(_ days: Weekdays) {
        mode = .weekdays
        weekdays = Set(days.days)
    }

    public mutating func selectEveryOtherDay() {
        mode = .days
        daysOn = 1
        daysOff = 1
    }
}
