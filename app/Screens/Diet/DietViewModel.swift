import FitnessCore
import SwiftUI

/// One bar of the day card: protein against its minimum, carbs as a share of calories, fat against its limit.
struct DietMacroRow: Identifiable {
    let name: String
    let value: String
    let note: String
    let tone: Pill.Tone
    /// 0...1 filled part of the bar.
    let progress: Double
    var id: String { name }
}

@MainActor
final class DietViewModel: ObservableObject {
    @Published private(set) var day: DietDay?
    @Published private(set) var weekExtras: ExtrasSummary?
    @Published private(set) var recentExtras: [RecentExtra] = []
    /// Calories typed for this day in the Body tab; they win over the diet until cleared.
    @Published private(set) var typedCalories: Double?
    @Published private(set) var rules = DietRules(proteinMinimumGrams: 180, fatPercentOfCalories: 20, fatCeilingGramsPerPound: 0.4)
    @Published private(set) var date: ISODate
    @Published var errorMessage: String?

    private let services: Services

    init(services: Services, date: ISODate? = nil) {
        self.services = services
        self.date = date ?? services.clock.today()
    }

    var today: ISODate { services.clock.today() }

    func load() {
        do {
            day = try services.dietDays.day(date)
            weekExtras = try services.dietDays.extrasSummary(endingOn: date, days: 7)
            recentExtras = try services.dietDays.recentExtras(limit: 5)
            rules = try services.dietRules.load()
            let counted = try services.calories.day(date)
            typedCalories = counted.source == .manual ? counted.calories : nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func show(_ newDate: ISODate) {
        date = newDate
        load()
    }

    func shift(days: Int) { show(date.adding(days: days)) }

    // MARK: Actions

    /// Ticks or unticks a planned item for this day. An item that is off its cycle has nothing to tick.
    func toggle(_ line: DietLine) {
        if case .offCycle = line.state { return }
        perform { try self.services.dietDays.setEaten(line.state != .eaten, meal: line.meal, foodID: line.foodID, on: self.date) }
    }

    /// Ticks the whole meal, or clears it when everything in it is already ticked.
    func toggle(_ meal: DietMeal) {
        guard meal.canTick else { return }
        perform { try self.services.dietDays.setMealEaten(meal.tickState != .all, meal: meal.name, on: self.date) }
    }

    /// Clears the calories typed for this day so the diet counts again.
    func useDietInstead() {
        perform { try self.services.calories.deleteCalories(on: self.date) }
    }

    func remove(_ extra: DietExtra) {
        perform { try self.services.dietDays.removeExtra(extra.id) }
    }

    func perform(_ action: () throws -> Void) {
        do {
            try action()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Header and summary text

    var dateTitle: String { Format.weekdayDate(date) }

    var caption: String {
        guard let day else { return "" }
        if !day.hasPlan { return "No plan on this day" }
        if day.plannedCount == 0 { return "Nothing planned today" }
        return day.eatenCount == 0 ? "Nothing ticked yet" : "\(day.eatenCount) of \(day.plannedCount) ticked"
    }

    var totalText: String { day.map { Format.grouped($0.total.calories) } ?? "–" }

    var ringProgress: Double {
        guard let day else { return 0 }
        guard day.planned.calories > 0 else { return day.total.calories > 0 ? 1 : 0 }
        return min(max(day.total.calories / day.planned.calories, 0), 1)
    }

    /// "Ticked 1,300 of plan 2,839 + extras 137"
    var equation: String {
        guard let day else { return "" }
        var parts = ["Ticked \(Format.grouped(day.eatenNutrition.calories)) of plan \(Format.grouped(day.planned.calories))"]
        if !day.extras.isEmpty { parts.append("+ extras \(Format.grouped(day.extrasNutrition.calories))") }
        return parts.joined(separator: " ")
    }

    var costText: String {
        guard let day else { return "" }
        return "Cost today \(Format.money(day.cost))\(day.cost.isComplete ? "" : " (some prices missing)")"
    }

    var macroRows: [DietMacroRow] {
        guard let day else { return [] }
        let t = day.targets
        let protein = day.total.protein, fat = day.total.fat
        let sourceText = t.fatLimitSource == .weightCap ? "weight cap" : "\(Format.number(rules.fatPercentOfCalories))% of cal"
        let fatRatio = t.fatLimitGrams > 0 ? fat / t.fatLimitGrams : 0
        let carbShare = day.total.calories > 0 ? min(day.total.carbs * 4 / day.total.calories, 1) : 0
        return [
            DietMacroRow(name: "Protein", value: "\(Format.number(protein, maxDecimals: 0)) g",
                         note: t.proteinMet ? "min \(Format.number(t.proteinMinimumGrams, maxDecimals: 0)) ✓" : "short by \(Format.number(t.proteinShortBy, maxDecimals: 0)) g",
                         tone: t.proteinMet ? .green : .amber, progress: min(protein / max(t.proteinMinimumGrams, 1), 1)),
            DietMacroRow(name: "Carbs", value: "\(Format.number(day.total.carbs, maxDecimals: 0)) g", note: "rest of calories", tone: .grey,
                         progress: carbShare),
            DietMacroRow(name: "Fat", value: "\(Format.number(fat, maxDecimals: 1)) g",
                         note: "limit \(Format.number(t.fatLimitGrams, maxDecimals: 1)) · \(sourceText)",
                         tone: t.fatOver ? .red : (fatRatio >= 0.9 ? .amber : .green), progress: min(fatRatio, 1)),
        ]
    }

    var weekExtrasText: String? {
        guard let weekExtras, weekExtras.days > 0 else { return nil }
        let days = "\(weekExtras.days) day\(weekExtras.days == 1 ? "" : "s")"
        return "Extras this week: \(days) · \(Format.grouped(weekExtras.nutrition.calories)) kcal · \(Format.money(weekExtras.cost))"
    }
}
