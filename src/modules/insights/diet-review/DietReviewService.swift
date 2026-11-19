import Foundation

/// A markdown snapshot of the diet for an agent that has read the vault. It covers the checks the app deliberately
/// leaves out (meal timing against tea and coffee, soaking and sprouting, omega-6 sources...).
public struct DietReviewService {
    public static let averageDays = 14
    private let db: Database
    private let library: SupplementLibrary?

    public init(_ db: Database, library: SupplementLibrary?) {
        self.db = db
        self.library = library
    }

    public func markdown(on today: ISODate, insights: [Insight]) throws -> String {
        let diet = DietDayService(db)
        var out = ["# Diet review export · \(today.string)", "",
                   "Review this diet against the Meridian vault rules. Report only gaps that are hard rules or clear wins.", ""]
        out += try plannedDay(diet.day(today))
        out += try recentAverage(diet, endingBefore: today)
        out += try supplements()
        out += ["## Open Room for improvement items"]
        out += insights.isEmpty ? ["None"] : insights.map { "- \($0.title): \($0.detail)" }
        return out.joined(separator: "\n") + "\n"
    }

    private func plannedDay(_ day: DietDay) -> [String] {
        var out = ["## Planned day"]
        for meal in day.meals {
            let lines = meal.lines.filter { if case .offCycle = $0.state { return false } else { return true } }
            guard !lines.isEmpty else { continue }
            let nutrition = lines.reduce(Nutrition.zero) { $0 + $1.nutrition }
            let profile = lines.reduce(NutrientProfile.empty) { $0 + $1.profile }
            out.append("### \(meal.name)")
            out += lines.map { "- \($0.name): \(Self.number($0.quantity)) \($0.unit)" }
            out.append("Meal: \(Self.summary(nutrition)), leucine \(profile[.leucine].map { "\(Self.number($0)) g" } ?? "unknown")")
        }
        return out + [""]
    }

    private func recentAverage(_ diet: DietDayService, endingBefore today: ISODate) throws -> [String] {
        let days = try (1...Self.averageDays).map { try diet.day(today.adding(days: -$0)) }.filter { $0.eatenCount > 0 || !$0.extras.isEmpty }
        var out = ["## Eaten, average over \(days.count) logged day\(days.count == 1 ? "" : "s") of the last \(Self.averageDays)"]
        guard !days.isEmpty else { return out + ["No logged days.", ""] }
        let count = Double(days.count)
        let nutrition = days.reduce(Nutrition.zero) { $0 + $1.eatenNutrition + $1.extrasNutrition }
        let profile = days.reduce(NutrientProfile.empty) { total, day in
            day.meals.reduce(total) { $0 + $1.eatenProfile } + day.extras.reduce(NutrientProfile.empty) { $0 + $1.profile }
        }
        out.append(Self.summary(nutrition.scaled(by: 1 / count)))
        for nutrient in Nutrient.allCases {
            guard let value = profile[nutrient] else { continue }
            let target = nutrient.dailyTarget.map { " (\(Self.number(value / count / $0 * 100))% of target)" } ?? ""
            out.append("- \(nutrient.title): \(Self.number(value / count)) \(nutrient.unit)\(target)")
        }
        let unknown = Nutrient.allCases.filter { profile.unknown.contains($0) || profile[$0] == nil }
        if !unknown.isEmpty { out.append("Unknown (no data in some foods): \(unknown.map(\.title).joined(separator: ", "))") }
        let extras = days.flatMap(\.extras).map(\.displayName)
        if !extras.isEmpty {
            let counts: [String: Int] = Dictionary(extras.map { ($0, 1) }, uniquingKeysWith: +)
            let ordered = counts.sorted { lhs, rhs in lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value }
            out.append("Extras: " + ordered.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
        }
        return out + [""]
    }

    private func supplements() throws -> [String] {
        let foods = try FoodLibrary(db).foods(kind: .supplement)
        var out = ["## Supplements in my foods"]
        out += foods.isEmpty ? ["None"] : foods.map { food in
            guard let entry = library?.match(food.name) else { return "- \(food.name) (not in the library)" }
            return "- \(food.name) → \(entry.name) (\(entry.verdict.title))"
        }
        return out + [""]
    }

    private static func summary(_ n: Nutrition) -> String {
        "\(number(n.calories)) kcal, protein \(number(n.protein)) g, carbs \(number(n.carbs)) g, fat \(number(n.fat)) g, fibre \(number(n.fiber)) g"
    }

    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
