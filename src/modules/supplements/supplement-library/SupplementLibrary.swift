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
    /// With the labs catalogue, each test-first name is shown with the owner's latest result.
    let labs: LabCatalogue?

    public init(library: SupplementLibrary, labs: LabCatalogue? = nil) {
        self.library = library
        self.labs = labs
    }

    private static let compoundEntries: [(nutrient: Nutrient, entryID: String)] = [
        (.creatine, "creatine"),
        (.glycine, "glycine"),
        (.psyllium, "psyllium"),
    ]

    public func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        guard let plan = try DietPlanService(db).plan(inForceOn: day) else { return [] }
        let book = try FoodLibrary(db).book()
        var problems: [String] = []
        var reasons: [String] = []
        var testFirst: [String] = []
        var testedEntries: Set<String> = []
        let lookup = try labs.map { LabTestLookup(catalogue: $0, draws: LabDrawService(db, catalogue: $0), sex: try LabSettings(db).load().sex) }
        let takenSupplements = Self.dailySupplements(plan.items, book: book)

        let plannedProfile = try plan.items.reduce(NutrientProfile.empty) { acc, item in
            try acc + book.profile(of: item.foodID, quantity: item.quantity)
        }
        var handledCompoundEntryIDs: Set<String> = []
        for (compound, entryID) in Self.compoundEntries {
            let fromFields = plannedProfile[compound] ?? 0
            guard fromFields > 0 else { continue }
            handledCompoundEntryIDs.insert(entryID)
            let legacyExtra = takenSupplements.reduce(0.0) { sum, taken in
                guard taken.food.draft.nutrients[compound] == nil,
                      library.match(taken.food.name)?.id == entryID,
                      taken.food.unit == compound.unit else { return sum }
                return sum + taken.amount
            }
            let total = fromFields + legacyExtra
            let entry = library.entries.first { $0.id == entryID }
            let low = entry?.doseMin ?? compound.recommendedRange?.lowerBound
            let high = entry?.doseMax ?? compound.recommendedRange?.upperBound
            if let low, let high {
                let text = "\(compound.title) \(Self.number(total)) \(compound.unit)"
                if total > high { problems.append("\(text) is above \(Self.number(low))-\(Self.number(high)) \(compound.unit)") }
                if total < low { problems.append("\(text) is below \(Self.number(low))-\(Self.number(high)) \(compound.unit)") }
            }
        }

        for taken in takenSupplements {
            let food = taken.food
            guard let entry = library.match(food.name) else { continue }
            if entry.verdict == .notRecommended {
                problems.append("\(food.name)\(taken.recipes.isEmpty ? "" : " (in \(taken.recipes.joined(separator: ", ")))") is not recommended")
                reasons.append("\(entry.name): \(entry.why)")
                continue
            }
            if !handledCompoundEntryIDs.contains(entry.id),
               let unit = entry.doseUnit, unit == food.unit, let low = entry.doseMin, let high = entry.doseMax {
                let amount = taken.amount
                let text = "\(food.name) \(Self.number(amount)) \(unit)"
                if amount > high { problems.append("\(text) is above \(Self.number(low))-\(Self.number(high)) \(unit)") }
                if amount < low { problems.append("\(text) is below \(Self.number(low))-\(Self.number(high)) \(unit)") }
            }
            if !entry.testFirst.isEmpty, testedEntries.insert(entry.id).inserted {
                let tests = try lookup.map { lookup in try entry.testFirst.map(lookup.summary(of:)) } ?? entry.testFirst
                testFirst.append("\(entry.name): \(tests.joined(separator: ", "))")
            }
        }
        var items: [Insight] = []
        if !problems.isEmpty {
            items.append(Insight(ruleID: id, kind: .setup, severity: .improve, title: "Supplement checks",
                                 detail: problems.joined(separator: "; ") + ".",
                                 why: reasons.isEmpty ? "Doses from the vault's supplement chapters." : reasons.joined(separator: " ")))
        }
        if !testFirst.isEmpty {
            items.append(Insight(ruleID: "supplement-test-first", kind: .setup, severity: .tip, title: "Test first",
                                 detail: "Check with bloodwork: \(testFirst.joined(separator: "; ")).",
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

public enum MultivitaminBaselineMode: String, CaseIterable, Equatable {
    case tabletsOnly
    case withTodaysFood

    public var title: String {
        switch self {
        case .tabletsOnly: return "Tablets only"
        case .withTodaysFood: return "With today's food"
        }
    }
}

public struct MultivitaminOption: Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let unit: String
    public let perUnit: NutrientProfile

    public init(id: Int, name: String, unit: String = "unit", perUnit: NutrientProfile) {
        self.id = id
        self.name = name
        self.unit = unit
        self.perUnit = perUnit
    }

    public init(food: Food) {
        let scale = food.draft.baseQuantity > 0 ? (1.0 / food.draft.baseQuantity) : 1.0
        self.init(id: food.id, name: food.name, unit: food.unit,
                  perUnit: NutrientProfile(values: food.draft.nutrients.mapValues { $0 * scale }, unknown: []))
    }
}

public struct MultivitaminStackSuggestion: Equatable {
    public let counts: [Int: Int]
    public let coveredTargetsCount: Int
    public let totalTargetsCount: Int
    public let averageCoveragePercent: Double
    public let breachedNutrients: [Nutrient]
    public let hasUnavoidableULBreach: Bool
}

/// Multivitamin coverage & stack optimizer across 0...3 units per product, against daily targets and upper limits.
public enum MultivitaminWhatIf {
    public struct Row: Equatable {
        public let nutrient: Nutrient
        public let tabletAmount: Double
        public let foodAmount: Double
        public let amount: Double
        public let target: Double?
        public let upperLimit: Double?
        public var isFatSoluble: Bool { nutrient.isFatSoluble }
        public var isOverLimit: Bool { upperLimit.map { amount > $0 } ?? false }
        public var coverageFraction: Double? {
            guard let target, target > 0 else { return nil }
            return min(amount / target, 1.0)
        }

        public init(nutrient: Nutrient, tabletAmount: Double = 0, foodAmount: Double = 0, amount: Double, target: Double?, upperLimit: Double?) {
            self.nutrient = nutrient
            self.tabletAmount = tabletAmount
            self.foodAmount = foodAmount
            self.amount = amount
            self.target = target
            self.upperLimit = upperLimit
        }
    }

    /// Several vitamins actually present (explicit zeros don't count) and next to no protein, carbs or fat,
    /// so milk powder or salt with filled-in nutrient data is not mistaken for a multivitamin.
    public static func isMultivitamin(_ draft: FoodDraft) -> Bool {
        let vitamins = draft.nutrients.filter { $0.key.group == .vitamins && $0.value > 0 }.count
        return vitamins >= 4 && draft.protein + draft.carbs + draft.fat < 1
    }

    public static var allVitaminAndMineralNutrients: [Nutrient] {
        Nutrient.allCases.filter { $0.group == .vitamins || $0.group == .minerals }
    }

    private static func profileAmount(_ profile: NutrientProfile, of nutrient: Nutrient) -> Double {
        nutrient == .vitaminD ? profile.totalVitaminDMcg : (profile[nutrient] ?? 0)
    }

    public static func rows(perTablet: NutrientProfile, tablets: Int, rest: NutrientProfile = .empty) -> [Row] {
        allVitaminAndMineralNutrients.map { nutrient in
            let tab = profileAmount(perTablet, of: nutrient) * Double(tablets)
            let food = profileAmount(rest, of: nutrient)
            return Row(nutrient: nutrient, tabletAmount: tab, foodAmount: food, amount: tab + food,
                       target: nutrient.dailyTarget, upperLimit: nutrient.upperLimit)
        }
    }

    public static func stackRows(options: [MultivitaminOption], counts: [Int: Int],
                                 mode: MultivitaminBaselineMode = .tabletsOnly, foodRest: NutrientProfile = .empty) -> [Row] {
        allVitaminAndMineralNutrients.map { nutrient in
            let tab = options.reduce(0.0) { sum, option in
                let count = max(counts[option.id] ?? 0, 0)
                return sum + profileAmount(option.perUnit, of: nutrient) * Double(count)
            }
            let food = mode == .withTodaysFood ? profileAmount(foodRest, of: nutrient) : 0
            return Row(nutrient: nutrient, tabletAmount: tab, foodAmount: food, amount: tab + food,
                       target: nutrient.dailyTarget, upperLimit: nutrient.upperLimit)
        }
    }

    public static func suggestBestStack(options: [MultivitaminOption], mode: MultivitaminBaselineMode = .tabletsOnly,
                                        foodRest: NutrientProfile = .empty, excludeOverULPills: Bool = false,
                                        maxUnitsPerOption: Int = 3, maxTotalUnits: Int = 4) -> MultivitaminStackSuggestion {
        let totalTargets = allVitaminAndMineralNutrients.filter { $0.dailyTarget != nil }.count
        guard !options.isEmpty else {
            return MultivitaminStackSuggestion(counts: [:], coveredTargetsCount: 0, totalTargetsCount: totalTargets,
                                               averageCoveragePercent: 0, breachedNutrients: [], hasUnavoidableULBreach: false)
        }

        struct Candidate {
            let counts: [Int: Int]
            let totalUnits: Int
            let coverageSum: Double
            let coveredCount: Int
            let fatSolubleExcess: Double
            let breaches: [Nutrient]
            let fatSolubleBreaches: [Nutrient]
        }

        func evaluate(_ counts: [Int: Int], totalUnits: Int) -> Candidate {
            let evaluated = stackRows(options: options, counts: counts, mode: mode, foodRest: foodRest)
            var coverageSum = 0.0
            var coveredCount = 0
            var fatSolubleExcess = 0.0
            var breaches: [Nutrient] = []
            var fatSolubleBreaches: [Nutrient] = []
            for row in evaluated {
                if let frac = row.coverageFraction {
                    coverageSum += frac
                    if row.amount + 1e-6 >= (row.target ?? 0) { coveredCount += 1 }
                }
                if row.isFatSoluble, let target = row.target, target > 0, row.amount > target {
                    fatSolubleExcess += (row.amount / target) - 1.0
                }
                if row.isOverLimit && row.tabletAmount > 0 {
                    breaches.append(row.nutrient)
                    if row.isFatSoluble { fatSolubleBreaches.append(row.nutrient) }
                }
            }
            return Candidate(counts: counts, totalUnits: totalUnits, coverageSum: coverageSum, coveredCount: coveredCount,
                             fatSolubleExcess: fatSolubleExcess, breaches: breaches, fatSolubleBreaches: fatSolubleBreaches)
        }

        var safeBest: Candidate?
        var currentCounts: [Int: Int] = [:]

        func isBetterSafe(_ lhs: Candidate, than rhs: Candidate) -> Bool {
            if abs(lhs.coverageSum - rhs.coverageSum) > 1e-6 { return lhs.coverageSum > rhs.coverageSum }
            if lhs.coveredCount != rhs.coveredCount { return lhs.coveredCount > rhs.coveredCount }
            if lhs.totalUnits != rhs.totalUnits { return lhs.totalUnits < rhs.totalUnits }
            return lhs.fatSolubleExcess < rhs.fatSolubleExcess
        }

        func search(_ index: Int, usedUnits: Int) {
            if index == options.count {
                guard usedUnits > 0 else { return }
                let candidate = evaluate(currentCounts, totalUnits: usedUnits)
                if candidate.breaches.isEmpty {
                    if let existing = safeBest {
                        if isBetterSafe(candidate, than: existing) { safeBest = candidate }
                    } else {
                        safeBest = candidate
                    }
                }
                return
            }
            let option = options[index]
            let upper = min(maxUnitsPerOption, maxTotalUnits - usedUnits)
            for count in 0...upper {
                if count == 0 {
                    currentCounts.removeValue(forKey: option.id)
                } else {
                    currentCounts[option.id] = count
                }
                search(index + 1, usedUnits: usedUnits + count)
            }
            currentCounts.removeValue(forKey: option.id)
        }

        search(0, usedUnits: 0)

        if let safeBest {
            let avg = totalTargets > 0 ? pyRound(safeBest.coverageSum / Double(totalTargets) * 100, 1) : 0
            return MultivitaminStackSuggestion(counts: safeBest.counts, coveredTargetsCount: safeBest.coveredCount,
                                               totalTargetsCount: totalTargets, averageCoveragePercent: avg,
                                               breachedNutrients: [], hasUnavoidableULBreach: false)
        }

        if excludeOverULPills {
            let emptyEval = evaluate([:], totalUnits: 0)
            let avg = totalTargets > 0 ? pyRound(emptyEval.coverageSum / Double(totalTargets) * 100, 1) : 0
            return MultivitaminStackSuggestion(counts: [:], coveredTargetsCount: emptyEval.coveredCount,
                                               totalTargetsCount: totalTargets, averageCoveragePercent: avg,
                                               breachedNutrients: [], hasUnavoidableULBreach: false)
        }

        // Fallback when every available multivitamin breaches a water-soluble UL at 1 unit: cap at 1 unit with zero fat-soluble UL breach.
        var fallbackBest: Candidate?
        for option in options {
            let candidate = evaluate([option.id: 1], totalUnits: 1)
            guard candidate.fatSolubleBreaches.isEmpty else { continue }
            if let existing = fallbackBest {
                if candidate.breaches.count != existing.breaches.count {
                    if candidate.breaches.count < existing.breaches.count { fallbackBest = candidate }
                } else if candidate.coverageSum > existing.coverageSum {
                    fallbackBest = candidate
                }
            } else {
                fallbackBest = candidate
            }
        }

        if let fallbackBest {
            let avg = totalTargets > 0 ? pyRound(fallbackBest.coverageSum / Double(totalTargets) * 100, 1) : 0
            return MultivitaminStackSuggestion(counts: fallbackBest.counts, coveredTargetsCount: fallbackBest.coveredCount,
                                               totalTargetsCount: totalTargets, averageCoveragePercent: avg,
                                               breachedNutrients: fallbackBest.breaches, hasUnavoidableULBreach: true)
        }

        return MultivitaminStackSuggestion(counts: [:], coveredTargetsCount: 0, totalTargetsCount: totalTargets,
                                           averageCoveragePercent: 0, breachedNutrients: [], hasUnavoidableULBreach: false)
    }
}
