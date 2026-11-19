import Foundation

public enum UrineColour: String, CaseIterable, Equatable {
    case clear, pale, dark

    public var title: String {
        switch self {
        case .clear: return "Clear"
        case .pale: return "Pale yellow"
        case .dark: return "Dark yellow"
        }
    }
}

/// The vault's signs of being under-recovered, ticked once a week. Keys are stored as text.
public enum RecoverySign: String, CaseIterable, Equatable {
    case tiredness, worsePerformance = "worse_performance", poorSleep = "poor_sleep", lowMood = "low_mood"
    case smallIllnesses = "small_illnesses", lowSexDrive = "low_sex_drive", lingeringSoreness = "lingering_soreness"
    case noProgress = "no_progress", achingJoints = "aching_joints", appetiteOrWeight = "appetite_or_weight"

    public var title: String {
        switch self {
        case .tiredness: return "Tiredness that rest doesn't fix"
        case .worsePerformance: return "Performance worse though I keep training"
        case .poorSleep: return "Poor sleep though tired"
        case .lowMood: return "Irritable or low mood"
        case .smallIllnesses: return "Frequent small illnesses (colds)"
        case .lowSexDrive: return "Low sex drive"
        case .lingeringSoreness: return "Soreness that lingers"
        case .noProgress: return "No progress, or going backward, in body shape"
        case .achingJoints: return "Joints ache more than usual"
        case .appetiteOrWeight: return "Appetite or weight changed without reason"
        }
    }
}

public struct CheckInDay: Equatable {
    public let urine: UrineColour?
    public let heavySweat: Bool?
    public let walkedAfter: Set<String>

    public init(urine: UrineColour?, heavySweat: Bool?, walkedAfter: Set<String>) {
        self.urine = urine
        self.heavySweat = heavySweat
        self.walkedAfter = walkedAfter
    }
}

/// The optional check-in. Nothing is required; an unanswered question is no data, never a "no".
public final class CheckInService {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func day(_ day: ISODate) throws -> CheckInDay {
        let row = try db.query("SELECT urine, heavy_sweat FROM checkins WHERE day = ?", [.text(day.string)]).first
        let walks = Set(try db.query("SELECT meal FROM meal_walks WHERE day = ?", [.text(day.string)]).map { $0.text("meal") })
        return CheckInDay(urine: row?.optionalText("urine").flatMap(UrineColour.init(rawValue:)),
                          heavySweat: row?.optionalInt("heavy_sweat").map { $0 == 1 }, walkedAfter: walks)
    }

    public func setUrine(_ colour: UrineColour?, on day: ISODate) throws {
        try db.execute("INSERT INTO checkins (day, urine) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET urine = excluded.urine",
                       [.text(day.string), .optional(colour?.rawValue)])
    }

    public func setHeavySweat(_ sweat: Bool?, on day: ISODate) throws {
        try db.execute("INSERT INTO checkins (day, heavy_sweat) VALUES (?, ?) ON CONFLICT(day) DO UPDATE SET heavy_sweat = excluded.heavy_sweat",
                       [.text(day.string), .optional(sweat.map { $0 ? 1 : 0 })])
    }

    public func setWalked(_ walked: Bool, after meal: String, on day: ISODate) throws {
        if walked {
            try db.execute("INSERT OR IGNORE INTO meal_walks (day, meal) VALUES (?, ?)", [.text(day.string), .text(meal)])
        } else {
            try db.execute("DELETE FROM meal_walks WHERE day = ? AND meal = ?", [.text(day.string), .text(meal)])
        }
    }

    /// Walks ticked over planned meals in the days ending at `end`; nil when no meal was planned.
    public func walkShare(endingOn end: ISODate, days count: Int) throws -> Double? {
        let plans = DietPlanService(db)
        var meals = 0
        var walked = 0
        for offset in 0..<count {
            let day = end.adding(days: -offset)
            let names = (try plans.plan(inForceOn: day)?.meals ?? []).map(\.name)
            meals += names.count
            walked += try self.day(day).walkedAfter.intersection(names).count
        }
        return meals == 0 ? nil : Double(walked) / Double(meals)
    }

    /// Signs ticked for the week (Monday to Sunday) that holds `day`.
    public func signs(weekOf day: ISODate) throws -> Set<RecoverySign> {
        Set(try db.query("SELECT sign FROM recovery_signs WHERE week_start = ?", [.text(Self.monday(of: day).string)])
            .compactMap { RecoverySign(rawValue: $0.text("sign")) })
    }

    public func setSigns(_ signs: Set<RecoverySign>, weekOf day: ISODate) throws {
        let week = Self.monday(of: day).string
        try db.transaction {
            try db.execute("DELETE FROM recovery_signs WHERE week_start = ?", [.text(week)])
            for sign in signs { try db.execute("INSERT INTO recovery_signs (week_start, sign) VALUES (?, ?)", [.text(week), .text(sign.rawValue)]) }
        }
    }

    public static func monday(of day: ISODate) -> ISODate { day.adding(days: -(day.weekday - 1)) }
}

public enum CheckInRules {
    public static var daily: [DailyRule] { [UrineDarkRule(), UrineClearRule(), UnderRecoveredRule()] }
    /// The vault reads 3-4 signs together, for weeks, as a pattern; one sign means little.
    static let patternSigns = 3
}

struct UrineDarkRule: DailyRule {
    let id = "urine-dark"
    let title = "Urine dark"
    let checksToday = true

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let checkIn = CheckInService(db)
        guard let colour = try checkIn.day(day).urine else { return .noData }
        guard colour == .dark, try checkIn.day(day.adding(days: -1)).urine == .dark else { return .ok }
        return .fired(Insight(ruleID: id, kind: .today, severity: .improve, title: title,
                              detail: "Dark two days in a row: drink more, about 30-40 mL per kg a day from drinks, more earlier in the day.",
                              why: "Vault: pale yellow is the aim; dark day after day means you are behind on fluids.", day: day))
    }
}

struct UrineClearRule: DailyRule {
    let id = "urine-clear"
    let title = "Urine clear"
    let checksToday = true

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let checkIn = CheckInService(db)
        guard let colour = try checkIn.day(day).urine else { return .noData }
        guard colour == .clear, try (1...2).allSatisfy({ try checkIn.day(day.adding(days: -$0)).urine == .clear }) else { return .ok }
        return .fired(Insight(ruleID: id, kind: .today, severity: .tip, title: title,
                              detail: "Clear three days in a row: you may be drinking more than needed or losing minerals with the water.",
                              why: "Vault: clear and frequent, again and again, is a sign of over-drinking.", day: day))
    }
}

struct UnderRecoveredRule: DailyRule {
    let id = "under-recovered"
    let title = "Under-recovered"
    let checksToday = false

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let checkIn = CheckInService(db)
        let thisWeek = try checkIn.signs(weekOf: day)
        let lastWeek = try checkIn.signs(weekOf: day.adding(days: -7))
        guard !thisWeek.isEmpty || !lastWeek.isEmpty else { return .noData }
        guard thisWeek.count >= CheckInRules.patternSigns, lastWeek.count >= CheckInRules.patternSigns else { return .ok }
        return .fired(Insight(ruleID: id, kind: .today, severity: .improve, title: title,
                              detail: "\(lastWeek.count) signs last week and \(thisWeek.count) this week. In this order: sleep 7-9 h, eat enough (protein and carbs around training, no hard deficit), deload 1-3 weeks, easy movement on off days, cut other stress.",
                              why: "Vault: one sign means little; 3-4 together for weeks is a pattern of under-recovery.", day: day))
    }
}
