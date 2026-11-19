import Foundation

public enum SupplementVerdict: String, Decodable, Equatable {
    case recommended
    case conditional
    case notRecommended = "not_recommended"

    public var title: String {
        switch self {
        case .recommended: return "Worth taking"
        case .conditional: return "Conditional"
        case .notRecommended: return "Not recommended"
        }
    }
}

public struct SupplementEntry: Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let category: String
    public let verdict: SupplementVerdict
    public let verdictText: String?
    public let why: String
    public let doseText: String?
    public let doseMin: Double?
    public let doseMax: Double?
    public let doseUnit: String?
    public let upperLimit: Double?
    public let upperLimitUnit: String?
    public let forms: String?
    public let timing: String?
    public let cycling: String?
    public let testFirst: [String]
    public let interactions: String?
    public let sideEffects: String?
    public let contradictions: String?
    public let source: String

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, category, verdict, why, forms, timing, cycling, interactions, contradictions, source
        case verdictText = "verdict_text", doseText = "dose_text", doseMin = "dose_min", doseMax = "dose_max", doseUnit = "dose_unit"
        case upperLimit = "upper_limit", upperLimitUnit = "upper_limit_unit", testFirst = "test_first", sideEffects = "side_effects"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        verdict = try c.decode(SupplementVerdict.self, forKey: .verdict)
        verdictText = try c.decodeIfPresent(String.self, forKey: .verdictText)
        why = try c.decodeIfPresent(String.self, forKey: .why) ?? ""
        doseText = try c.decodeIfPresent(String.self, forKey: .doseText)
        doseMin = try c.decodeIfPresent(Double.self, forKey: .doseMin)
        doseMax = try c.decodeIfPresent(Double.self, forKey: .doseMax)
        doseUnit = try c.decodeIfPresent(String.self, forKey: .doseUnit)
        upperLimit = try c.decodeIfPresent(Double.self, forKey: .upperLimit)
        upperLimitUnit = try c.decodeIfPresent(String.self, forKey: .upperLimitUnit)
        forms = try c.decodeIfPresent(String.self, forKey: .forms)
        timing = try c.decodeIfPresent(String.self, forKey: .timing)
        cycling = try c.decodeIfPresent(String.self, forKey: .cycling)
        testFirst = try c.decodeIfPresent([String].self, forKey: .testFirst) ?? []
        interactions = try c.decodeIfPresent(String.self, forKey: .interactions)
        sideEffects = try c.decodeIfPresent(String.self, forKey: .sideEffects)
        contradictions = try c.decodeIfPresent(String.self, forKey: .contradictions)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
    }
}

/// Every supplement the vault covers, read from a bundled file (the vault's content, so never committed).
public struct SupplementLibrary {
    private struct File: Decodable { let entries: [SupplementEntry] }

    public let entries: [SupplementEntry]

    public init(data: Data) throws {
        do { entries = try JSONDecoder().decode(File.self, from: data).entries } catch { throw ValidationError("The supplement library could not be read") }
    }

    public init(entries: [SupplementEntry]) { self.entries = entries }

    /// Name, aliases and category, ignoring case; every word typed must match somewhere.
    public func search(_ text: String, verdict: SupplementVerdict? = nil) -> [SupplementEntry] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        return entries.filter { entry in
            guard verdict == nil || entry.verdict == verdict else { return false }
            let haystack = ([entry.name, entry.category] + entry.aliases).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) } || entry.aliases.contains { text.lowercased().contains($0) }
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// The entry a product name refers to: the longest name or alias found in it.
    public func match(_ productName: String) -> SupplementEntry? {
        let product = productName.lowercased()
        var best: (entry: SupplementEntry, length: Int)?
        for entry in entries {
            for alias in [entry.name.lowercased()] + entry.aliases where alias.count >= 3 && product.contains(alias) {
                if alias.count > (best?.length ?? 0) { best = (entry, alias.count) }
            }
        }
        return best?.entry
    }
}

/// The owner's supplements in the plan, checked against the library.
public struct SupplementCheckRule: SetupRule {
    public let id = "supplement-checks"
    let library: SupplementLibrary

    public init(library: SupplementLibrary) { self.library = library }

    public func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        guard let plan = try DietPlanService(db).plan(inForceOn: day) else { return [] }
        let book = try FoodLibrary(db).book()
        var problems: [String] = []
        var reasons: [String] = []
        var testFirst: [String] = []
        for item in plan.items {
            guard let food = book.food(item.foodID), food.kind == .supplement, let entry = library.match(food.name) else { continue }
            if entry.verdict == .notRecommended {
                problems.append("\(food.name) is not recommended")
                reasons.append("\(entry.name): \(entry.why)")
                continue
            }
            if let unit = entry.doseUnit, unit == food.unit, let low = entry.doseMin, let high = entry.doseMax {
                let amount = item.quantity
                let text = "\(food.name) \(Self.number(amount)) \(unit)"
                if amount > high { problems.append("\(text) is above \(Self.number(low))-\(Self.number(high)) \(unit)") }
                if amount < low { problems.append("\(text) is below \(Self.number(low))-\(Self.number(high)) \(unit)") }
            }
            if !entry.testFirst.isEmpty { testFirst.append("\(entry.name): \(entry.testFirst.joined(separator: ", "))") }
        }
        var items: [Insight] = []
        if !problems.isEmpty {
            items.append(Insight(ruleID: id, kind: .setup, severity: .improve, title: "Supplement checks",
                                 detail: problems.joined(separator: "; ") + ".",
                                 why: reasons.isEmpty ? "Doses from the vault's supplement chapters." : reasons.joined(separator: " ")))
        }
        if !testFirst.isEmpty {
            items.append(Insight(ruleID: "supplement-test-first", kind: .setup, severity: .tip, title: "Test first",
                                 detail: "Check with bloodwork: \(testFirst.joined(separator: "; ")). Blood Labs will link these markers.",
                                 why: "Vault: test first, then supplement for a real gap, and judge it after 8-12 weeks."))
        }
        return items
    }

    public static func number(_ value: Double) -> String { value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value) }
}

/// Vault: add one new supplement at a time and wait 2-4 weeks (or until the next test) before another.
public struct SupplementOnRampRule: SetupRule {
    public let id = "supplement-on-ramp"
    static let minimumGapDays = 14

    public init() {}

    public func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        guard let plan = try DietPlanService(db).plan(inForceOn: day) else { return [] }
        let book = try FoodLibrary(db).book()
        let added = try plan.items.compactMap { item -> (name: String, from: ISODate)? in
            guard let food = book.food(item.foodID), food.kind == .supplement,
                  let first = try db.query("SELECT MIN(plan_from) AS d FROM diet_plan_items WHERE food_id = ?", [.int(Int64(food.id))]).first?
                    .optionalText("d").flatMap(ISODate.init) else { return nil }
            return (food.name, first)
        }
        .sorted { $0.from > $1.from }
        guard added.count >= 2, day.days(since: added[0].from) <= 28,
              added[0].from.days(since: added[1].from) < Self.minimumGapDays else { return [] }
        return [Insight(ruleID: id, kind: .setup, severity: .tip, title: "One new supplement at a time",
                        detail: "\(added[0].name) was added \(added[0].from.days(since: added[1].from)) days after \(added[1].name). Wait 2-4 weeks between new ones.",
                        why: "Vault: if you start several things at once and feel something odd, you will not know the cause.")]
    }
}

/// A multivitamin at 1, 2 or 3 tablets on top of the rest of the day, against daily targets and upper limits.
public enum MultivitaminWhatIf {
    public struct Row: Equatable {
        public let nutrient: Nutrient
        public let amount: Double
        public let target: Double?
        public let upperLimit: Double?
        public var isFatSoluble: Bool { nutrient.isFatSoluble }
        public var isOverLimit: Bool { upperLimit.map { amount > $0 } ?? false }
    }

    public static func rows(perTablet: NutrientProfile, tablets: Int, rest: NutrientProfile) -> [Row] {
        Nutrient.allCases.filter { perTablet[$0] != nil && ($0.group == .vitamins || $0.group == .minerals) }.map { nutrient in
            Row(nutrient: nutrient, amount: (perTablet[nutrient] ?? 0) * Double(tablets) + (rest[nutrient] ?? 0),
                target: nutrient.dailyTarget, upperLimit: nutrient.upperLimit)
        }
    }
}
