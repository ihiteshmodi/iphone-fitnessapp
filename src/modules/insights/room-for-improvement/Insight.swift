import Foundation

public enum InsightKind: String, Equatable {
    /// From what was eaten or done on a day.
    case today
    /// From the plan itself (diet or workout): a one-time fix.
    case setup
    /// From bloodwork (Phase B).
    case labs
}

public enum InsightSeverity: Int, Comparable, Equatable {
    case fix = 0, improve, tip

    public var title: String {
        switch self {
        case .fix: return "Fix"
        case .improve: return "Improve"
        case .tip: return "Tip"
        }
    }

    public static func < (lhs: InsightSeverity, rhs: InsightSeverity) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Something the app can do for the owner straight from an item.
public enum InsightAction: String, Equatable {
    case turnOnDeload
}

/// One thing that could be better: what is off, the numbers, and the rule behind it.
public struct Insight: Equatable, Identifiable {
    public let ruleID: String
    public let kind: InsightKind
    public let severity: InsightSeverity
    public let title: String
    public let detail: String
    /// One line on the rule and where it comes from.
    public let why: String
    /// The day a daily item is about; nil for setup items.
    public let day: ISODate?
    public var action: InsightAction?

    public init(ruleID: String, kind: InsightKind, severity: InsightSeverity, title: String, detail: String, why: String, day: ISODate? = nil,
                action: InsightAction? = nil) {
        self.action = action
        self.ruleID = ruleID
        self.kind = kind
        self.severity = severity
        self.title = title
        self.detail = detail
        self.why = why
        self.day = day
    }

    public var id: String { day.map { "\(ruleID)@\($0.string)" } ?? ruleID }
}

public enum RuleOutcome: Equatable {
    case fired(Insight)
    case ok
    /// Not enough logged data that day (unknown nutrients, nothing eaten, a break) to say.
    case noData
}

/// A rule checked day by day; feeds Today and Trends.
public protocol DailyRule {
    var id: String { get }
    var title: String { get }
    /// False for rules that need a finished day (totals such as fiber); they are checked up to yesterday.
    var checksToday: Bool { get }
    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome
}

/// A rule about the plan itself; feeds Setup until the plan changes or the item is accepted.
public protocol SetupRule {
    var id: String { get }
    func evaluate(on day: ISODate, db: Database) throws -> [Insight]
}

public enum TrendMark: Equatable {
    case fired, ok, noData
}

public struct TrendRow: Equatable, Identifiable {
    public let ruleID: String
    public let title: String
    /// Oldest first.
    public let marks: [TrendMark]
    public var id: String { ruleID }
    public var firedCount: Int { marks.filter { $0 == .fired }.count }
    public var daysWithData: Int { marks.filter { $0 != .noData }.count }
}

public enum ArchiveStatus: String, Equatable {
    /// "I know, not changing": hidden, still tracked in Trends.
    case accepted
    /// "Doesn't apply to me": the rule stops running.
    case notApplicable = "not_applicable"
}

public struct ArchivedRule: Equatable, Identifiable {
    public let ruleID: String
    public let title: String
    public let status: ArchiveStatus
    public let note: String?
    public var id: String { ruleID }

    public init(ruleID: String, title: String, status: ArchiveStatus, note: String?) {
        self.ruleID = ruleID
        self.title = title
        self.status = status
        self.note = note
    }
}
