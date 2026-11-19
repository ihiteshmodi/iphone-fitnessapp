import Foundation

/// The hard nutrition rules from the Meridian vault (Vol 05) and the owner's own, as Room for improvement rules.
public enum NutritionRules {
    public static var daily: [DailyRule] {
        [TransFatRule(), LeucinePerMealRule(), FiberRule(), FatRangeRule(), EPADHARule(), LateCaffeineRule(),
         NamedFoodRule(id: "flax-chia", title: "Flax or chia", words: ["flax", "chia", "alsi"],
                       detail: "Flax and chia are on your not-recommended list.",
                       why: "This is your own rule (gel in the gut, digestion and inflammation for you); the vault only says their ALA barely turns into EPA/DHA."),
         NamedFoodRule(id: "collagen", title: "Collagen does not count", words: ["collagen", "gelatin"],
                       detail: "Collagen is not counted toward protein or leucine.",
                       why: "Vault: collagen has no tryptophan and little leucine, so it does not count toward muscle protein; you consider it not worth taking.")]
    }

    public static var setup: [SetupRule] { [ProteinMealsRule(), PlanLeucineRule(), PlanFiberRule(), PlanFatRule(), Omega3FormRule()] }

    /// A meal counts as a protein meal from this much protein.
    static let proteinMealGrams = 20.0
    /// The owner's per-meal minimum (the vault says 2.5-3 g).
    static let leucinePerMeal = 3.0
    static let fiberPerThousandKcal = 14.0
    static let epaDhaMinimumMg = 250.0

    static func grams(_ value: Double) -> String {
        value.rounded() == value || value >= 10 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    static func eatenNames(_ day: DietDay, where test: (NutrientProfile) -> Bool) -> [String] {
        day.meals.flatMap(\.lines).filter { $0.state == .eaten && test($0.profile) }.map(\.name)
            + day.extras.filter { test($0.profile) }.map(\.displayName)
    }

    static func diet(_ db: Database, _ day: ISODate) throws -> DietDay { try DietDayService(db).day(day) }

    static func isEmpty(_ day: DietDay) -> Bool { day.total.calories <= 0 && day.eatenCount == 0 && day.extras.isEmpty }
}

struct TransFatRule: DailyRule {
    let id = "trans-fat"
    let title = "Trans fat"
    let checksToday = true

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let eaten = try NutritionRules.diet(db, day)
        guard !NutritionRules.isEmpty(eaten) else { return .noData }
        let trans = eaten.eatenProfile[.trans] ?? 0
        guard trans > 0 else { return eaten.eatenProfile.unknown.contains(.trans) ? .noData : .ok }
        let foods = NutritionRules.eatenNames(eaten) { ($0[.trans] ?? 0) > 0 }
        return .fired(Insight(ruleID: id, kind: .today, severity: .fix, title: title,
                              detail: "\(NutritionRules.grams(trans)) g from \(foods.joined(separator: ", ")).",
                              why: "Vault: keep industrial trans fat near zero.", day: day))
    }
}

struct LeucinePerMealRule: DailyRule {
    let id = "leucine-per-meal"
    let title = "Leucine under 3 g"
    let checksToday = false

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let meals = try NutritionRules.diet(db, day).meals.filter { $0.eatenNutrition.protein >= NutritionRules.proteinMealGrams }
        guard !meals.isEmpty, meals.allSatisfy({ !$0.eatenProfile.unknown.contains(.leucine) }) else { return .noData }
        let short = meals.filter { ($0.eatenProfile[.leucine] ?? 0) < NutritionRules.leucinePerMeal }
        guard !short.isEmpty else { return .ok }
        let list = short.map { "\($0.name) \(NutritionRules.grams($0.eatenProfile[.leucine] ?? 0)) g" }.joined(separator: ", ")
        return .fired(Insight(ruleID: id, kind: .today, severity: .improve, title: title, detail: "\(list). Aim for at least 3 g in every protein meal.",
                              why: "Vault: about 2.5-3 g of leucine per meal switches on muscle building; your minimum is 3 g.", day: day))
    }
}

struct FiberRule: DailyRule {
    let id = "fiber"
    let title = "Fiber"
    let checksToday = false

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let eaten = try NutritionRules.diet(db, day)
        guard eaten.total.calories > 0 else { return .noData }
        let needed = eaten.total.calories / 1000 * NutritionRules.fiberPerThousandKcal
        guard eaten.total.fiber < needed else { return .ok }
        return .fired(Insight(ruleID: id, kind: .today, severity: .improve, title: title,
                              detail: "\(NutritionRules.grams(eaten.total.fiber)) g of \(String(format: "%.1f", needed)) g. If short, add psyllium 1-2 tbsp with plenty of water, or lentils, beans or oats; raise by about 5 g a week.",
                              why: "Vault: about 14 g of fiber per 1,000 calories.", day: day))
    }
}

struct FatRangeRule: DailyRule {
    let id = "fat-range"
    let title = "Fat"
    let checksToday = false

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let eaten = try NutritionRules.diet(db, day)
        guard eaten.total.calories > 0 else { return .noData }
        let t = eaten.targets
        let fat = NutritionRules.grams(eaten.total.fat)
        if t.fatUnder {
            return .fired(Insight(ruleID: id, kind: .today, severity: .improve, title: "Fat under the range",
                                  detail: "\(fat) g of at least \(String(format: "%.1f", t.fatMinimumGrams)) g.",
                                  why: "Vault: fat 20-35% of calories and never under about 0.8 g per kg; too little for long can lower hormones, and fat-soluble vitamins (A, D, E, K) need fat to be absorbed.", day: day))
        }
        if t.fatOver {
            return .fired(Insight(ruleID: id, kind: .today, severity: .improve, title: "Fat over the range",
                                  detail: "\(fat) g, more than \(String(format: "%.1f", t.fatMaximumGrams)) g.",
                                  why: "Vault: fat 20-35% of calories.", day: day))
        }
        return .ok
    }
}

struct EPADHARule: DailyRule {
    let id = "epa-dha"
    let title = "EPA + DHA"
    let checksToday = false

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let profile = try NutritionRules.diet(db, day).eatenProfile
        let total = (profile[.epa] ?? 0) + (profile[.dha] ?? 0)
        if total >= NutritionRules.epaDhaMinimumMg { return .ok }
        guard !profile.unknown.contains(.epa), !profile.unknown.contains(.dha) else { return .noData }
        return .fired(Insight(ruleID: id, kind: .today, severity: .improve, title: title,
                              detail: "\(String(format: "%.0f", total)) mg of 250 mg. Maintenance is 250-500 mg a day; 1-2 g is the steady band.",
                              why: "Vault: EPA + DHA 250-500 mg a day for maintenance; ALA from flax or chia does not count.", day: day))
    }
}

struct LateCaffeineRule: DailyRule {
    let id = "late-caffeine"
    let title = "Late caffeine"
    let checksToday = true

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let late = try NutritionRules.diet(db, day).extras.filter {
            ($0.profile[.caffeine] ?? 0) > 0 && ($0.details.time == .evening || $0.details.time == .night)
        }
        guard !late.isEmpty else { return .ok }
        return .fired(Insight(ruleID: id, kind: .today, severity: .tip, title: title,
                              detail: "\(late.map(\.displayName).joined(separator: ", ")) in the \(late[0].details.time?.rawValue ?? "evening"). Stop caffeine 8-10 hours before bed.",
                              why: "Vault: caffeine cut-off 8-10 hours before bed protects sleep.", day: day))
    }
}

/// Fires when a food whose name contains one of the words is eaten.
struct NamedFoodRule: DailyRule {
    let id: String
    let title: String
    let words: [String]
    let detail: String
    let why: String
    let checksToday = true

    func evaluate(on day: ISODate, db: Database) throws -> RuleOutcome {
        let eaten = try NutritionRules.diet(db, day)
        let names = NutritionRules.eatenNames(eaten) { _ in true }
        let hits = names.filter { name in words.contains { name.lowercased().contains($0) } }
        guard !hits.isEmpty else { return .ok }
        return .fired(Insight(ruleID: id, kind: .today, severity: .tip, title: title,
                              detail: "\(hits.joined(separator: ", ")). \(detail)", why: why, day: day))
    }
}

// MARK: Setup (the diet plan itself)

private func plannedMeals(_ db: Database, _ day: ISODate) throws -> [DietMeal] { try NutritionRules.diet(db, day).meals }

struct ProteinMealsRule: SetupRule {
    let id = "protein-meals"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        let meals = try plannedMeals(db, day)
        guard !meals.isEmpty else { return [] }
        let count = meals.filter { $0.plannedNutrition.protein >= NutritionRules.proteinMealGrams }.count
        guard count < 3 else { return [] }
        return [Insight(ruleID: id, kind: .setup, severity: .improve, title: "\(count) protein meal\(count == 1 ? "" : "s")",
                        detail: "Aim for 3-4 protein meals, 3-5 hours apart. Two big meals waste part of the muscle-building signal.",
                        why: "Vault: spreading protein evenly raised 24-hour muscle building by about 25% compared with a lopsided day.")]
    }
}

struct PlanLeucineRule: SetupRule {
    let id = "plan-leucine"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        let short = try plannedMeals(db, day).filter {
            $0.plannedNutrition.protein >= NutritionRules.proteinMealGrams && !$0.plannedProfile.unknown.contains(.leucine)
                && ($0.plannedProfile[.leucine] ?? 0) < NutritionRules.leucinePerMeal
        }
        guard !short.isEmpty else { return [] }
        let list = short.map { "\($0.name) \(NutritionRules.grams($0.plannedProfile[.leucine] ?? 0)) g" }.joined(separator: ", ")
        return [Insight(ruleID: id, kind: .setup, severity: .improve, title: "Planned meals under 3 g leucine",
                        detail: "\(list). Add a leucine-rich food (soy) to reach 3 g.", why: "Your minimum is 3 g of leucine per protein meal.")]
    }
}

struct PlanFiberRule: SetupRule {
    let id = "plan-fiber"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        let planned = try NutritionRules.diet(db, day).planned
        guard planned.calories > 0 else { return [] }
        let needed = planned.calories / 1000 * NutritionRules.fiberPerThousandKcal
        guard planned.fiber < needed else { return [] }
        return [Insight(ruleID: id, kind: .setup, severity: .improve, title: "The diet is low in fiber",
                        detail: "\(NutritionRules.grams(planned.fiber)) g of \(String(format: "%.1f", needed)) g a day as planned.",
                        why: "Vault: about 14 g of fiber per 1,000 calories.")]
    }
}

struct PlanFatRule: SetupRule {
    let id = "plan-fat"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        let eaten = try NutritionRules.diet(db, day)
        let planned = eaten.planned
        guard planned.calories > 0 else { return [] }
        let rules = try DietSettings(db).load()
        let weight = rules.fatFloorGramsPerKg > 0 ? eaten.targets.fatFloorGrams.map { $0 / rules.fatFloorGramsPerKg } : nil
        let targets = DietTargets.evaluate(calories: planned.calories, protein: planned.protein, fat: planned.fat, rules: rules, averageWeightKg: weight)
        guard targets.fatUnder || targets.fatOver else { return [] }
        let gap = targets.fatUnder ? targets.fatMinimumGrams - planned.fat : planned.fat - targets.fatMaximumGrams
        return [Insight(ruleID: id, kind: .setup, severity: .improve,
                        title: targets.fatUnder ? "The diet is low in fat" : "The diet is high in fat",
                        detail: "\(NutritionRules.grams(planned.fat)) g planned; \(targets.fatUnder ? "add" : "remove") about \(NutritionRules.grams(gap)) g (1 tbsp oil is about 14 g).",
                        why: "Vault: fat 20-35% of calories and never under about 0.8 g per kg.")]
    }
}

struct Omega3FormRule: SetupRule {
    let id = "omega3-form"

    func evaluate(on day: ISODate, db: Database) throws -> [Insight] {
        guard let plan = try DietPlanService(db).plan(inForceOn: day) else { return [] }
        let book = try FoodLibrary(db).book()
        let oils = plan.items.compactMap { book.food($0.foodID) }.filter {
            (($0.draft.nutrients[.epa] ?? 0) + ($0.draft.nutrients[.dha] ?? 0)) > 0 && $0.draft.omega3Form != .reEsterifiedTriglyceride && $0.draft.omega3Form != .algae
        }
        guard let oil = oils.first else { return [] }
        return [Insight(ruleID: id, kind: .setup, severity: .tip, title: "Omega-3 form",
                        detail: "\(oil.name) is \(oil.draft.omega3Form?.rawValue ?? "not set"). Prefer re-esterified triglyceride (rTG) or algae oil, and read mg of EPA + DHA per capsule.",
                        why: "Vault: rTG or a quality concentrate absorbs best; plant eaters can use algae oil.")]
    }
}
