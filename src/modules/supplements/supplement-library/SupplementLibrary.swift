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

/// Every supplement the vault covers, read from the bundled output/supplement-library.json.
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

    /// The entry a product name refers to: the longest name or alias found in it as whole words,
    /// so "Becadexamine" is not the ECA stack and "D3 5000IU" is vitamin D3.
    public func match(_ productName: String) -> SupplementEntry? {
        let product = Self.words(productName)
        var best: (entry: SupplementEntry, length: Int)?
        for entry in entries {
            for alias in [entry.name] + entry.aliases {
                let aliasWords = Self.words(alias)
                guard !aliasWords.isEmpty, Self.contains(product, aliasWords), alias.count > (best?.length ?? 0) else { continue }
                best = (entry, alias.count)
            }
        }
        return best?.entry
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func contains(_ words: [String], _ run: [String]) -> Bool {
        guard run.count <= words.count else { return false }
        return (0...(words.count - run.count)).contains { Array(words[$0..<($0 + run.count)]) == run }
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
        var testedEntries: Set<String> = []
        for taken in Self.dailySupplements(plan.items, book: book) {
            let food = taken.food
            guard let entry = library.match(food.name) else { continue }
            if entry.verdict == .notRecommended {
                problems.append("\(food.name)\(taken.recipes.isEmpty ? "" : " (in \(taken.recipes.joined(separator: ", ")))") is not recommended")
                reasons.append("\(entry.name): \(entry.why)")
                continue
            }
            if let unit = entry.doseUnit, unit == food.unit, let low = entry.doseMin, let high = entry.doseMax {
                let amount = taken.amount
                let text = "\(food.name) \(Self.number(amount)) \(unit)"
                if amount > high { problems.append("\(text) is above \(Self.number(low))-\(Self.number(high)) \(unit)") }
                if amount < low { problems.append("\(text) is below \(Self.number(low))-\(Self.number(high)) \(unit)") }
            }
            if !entry.testFirst.isEmpty, testedEntries.insert(entry.id).inserted { testFirst.append("\(entry.name): \(entry.testFirst.joined(separator: ", "))") }
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

    struct DailySupplement {
        let food: Food
        var amount: Double
        var recipes: [String]
    }

    /// Each supplement once with its whole-day amount, including what sits inside recipes (a shake made with Gokhru).
    static func dailySupplements(_ items: [PlanItem], book: FoodBook) -> [DailySupplement] {
        var byFood: [Int: DailySupplement] = [:]
        var order: [Int] = []
        func visit(_ foodID: Int, _ quantity: Double, recipe: String?, depth: Int) {
            guard let food = book.food(foodID), depth < 5 else { return }
            if food.isRecipe {
                let share = quantity / (food.draft.recipeMakes ?? 1)
                for line in book.lines[foodID] ?? [] { visit(line.foodID, line.quantity * share, recipe: food.name, depth: depth + 1) }
                return
            }
            guard food.kind == .supplement else { return }
            if byFood[foodID] == nil { order.append(foodID); byFood[foodID] = DailySupplement(food: food, amount: 0, recipes: []) }
            byFood[foodID]?.amount += quantity
            if let recipe, !(byFood[foodID]?.recipes.contains(recipe) ?? true) { byFood[foodID]?.recipes.append(recipe) }
        }
        for item in items { visit(item.foodID, item.quantity, recipe: nil, depth: 0) }
        return order.compactMap { byFood[$0] }
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
        // Supplements already in the first plan were taken before the app, so they are the starting point, not new.
        guard let firstPlan = try db.query("SELECT MIN(plan_from) AS d FROM diet_plan_items").first?.optionalText("d").flatMap(ISODate.init) else { return [] }
        let added = try plan.items.compactMap { item -> (name: String, from: ISODate)? in
            guard let food = book.food(item.foodID), food.kind == .supplement,
                  let first = try db.query("SELECT MIN(plan_from) AS d FROM diet_plan_items WHERE food_id = ?", [.int(Int64(food.id))]).first?
                    .optionalText("d").flatMap(ISODate.init) else { return nil }
            return (food.name, first)
        }
        .filter { $0.from > firstPlan }
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

    /// Several vitamins actually present (explicit zeros don't count) and next to no protein, carbs or fat,
    /// so milk powder or salt with filled-in nutrient data is not mistaken for a multivitamin.
    public static func isMultivitamin(_ draft: FoodDraft) -> Bool {
        let vitamins = draft.nutrients.filter { $0.key.group == .vitamins && $0.value > 0 }.count
        return vitamins >= 4 && draft.protein + draft.carbs + draft.fat < 1
    }

    public static func rows(perTablet: NutrientProfile, tablets: Int, rest: NutrientProfile) -> [Row] {
        Nutrient.allCases.filter { perTablet[$0] != nil && ($0.group == .vitamins || $0.group == .minerals) }.map { nutrient in
            Row(nutrient: nutrient, amount: (perTablet[nutrient] ?? 0) * Double(tablets) + (rest[nutrient] ?? 0),
                target: nutrient.dailyTarget, upperLimit: nutrient.upperLimit)
        }
    }
}
