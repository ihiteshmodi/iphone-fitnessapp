import FitnessCore
import SwiftUI

enum BodyNumbers {
    /// 3037 -> "3,037". `Format.grouped` has no separator because it uses the POSIX locale.
    static func grouped(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value.rounded())) ?? String(Int(value.rounded()))
    }
}

struct BodyMacroRow: Identifiable {
    let name: String
    let grams: String
    /// Share of the day's target calories, 0...1.
    let share: Double
    var id: String { name }
}

@MainActor
final class BodyViewModel: ObservableObject {
    /// What the weekly maths used as calories per day: the average of the last 7 days' effective values.
    @Published private(set) var averageEaten: Double?
    @Published private(set) var target: CalorieTarget?
    @Published private(set) var averages: WeeklyAverages?
    @Published private(set) var averagesNotice: String?
    /// Newest first.
    @Published private(set) var weights: [BodyWeightEntry] = []
    /// The 7 days ending today, newest first.
    @Published private(set) var calorieDays: [CalorieDay] = []
    @Published private(set) var currentDefault: CalorieDefault?
    @Published private(set) var rules = MacroRules(proteinGramsPerLb: 1.2, fatPercent: 25)
    @Published private(set) var loadError: String?

    private let services: Services

    init(services: Services) { self.services = services }

    var today: ISODate { services.clock.today() }

    func load() {
        do {
            rules = try services.nutrition.rules()
            weights = try services.logBody.recentWeights(limit: 14)
            calorieDays = try services.calories.days(endingOn: today, count: 7)
            currentDefault = try services.calories.defaults().first { $0.effectiveFrom <= today }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }

        do {
            averages = try services.calories.weeklyAverages()
            averagesNotice = nil
        } catch {
            averages = nil
            averagesNotice = error.localizedDescription
        }

        let advice = try? services.calories.currentAdvice()
        target = advice?.target
        averageEaten = advice?.target.caloriesEaten ?? (try? services.calories.averageCalories(endingOn: today, days: 7)) ?? nil
    }

    // MARK: Ring card

    var eatenText: String { averageEaten.map { BodyNumbers.grouped($0.rounded()) } ?? "–" }

    var ringProgress: Double {
        guard let target, target.maintenanceCalories > 0 else { return 0 }
        return min(max(target.caloriesEaten / target.maintenanceCalories, 0), 1)
    }

    var phaseText: String? { target?.phase.rawValue }
    var phaseTone: Pill.Tone { target?.phase == .cut ? .amber : .green }
    var maintenanceText: String { target.map { BodyNumbers.grouped($0.maintenanceCalories.rounded()) } ?? "–" }
    var newTargetText: String? { target.map { "New target \(BodyNumbers.grouped(Double($0.adjustedTarget)))" } }

    /// Explains why there is no target yet.
    var ringHint: String? {
        if target != nil { return nil }
        if averageEaten == nil { return "Enter the calories you eat per day to get your target." }
        return averagesNotice
    }

    /// Says when the calories above come from the diet plan rather than a typed default.
    var calorieSourceNote: String? {
        let planDays = calorieDays.filter { $0.source == .plan }.count
        guard planDays > 0 else { return nil }
        return planDays == calorieDays.count ? "Counted from your diet" : "\(planDays) of the last \(calorieDays.count) days counted from your diet"
    }

    // MARK: What your weight says

    var balance: CalorieTarget.Balance? {
        guard let averages else { return nil }
        return CalorieTarget.balance(currentAverageKg: averages.currentAverageKg, pastAverageKg: averages.pastAverageKg)
    }

    var balanceHeadline: String? {
        guard let balance else { return nil }
        switch balance.kind {
        case .maintenance: return "Holding weight"
        case .deficit: return "In a deficit of about \(BodyNumbers.grouped(abs(balance.dailyKcal))) kcal a day"
        case .surplus: return "In a surplus of about \(BodyNumbers.grouped(abs(balance.dailyKcal))) kcal a day"
        }
    }

    var balanceTone: Pill.Tone {
        switch balance?.kind {
        case .deficit: return .amber
        case .surplus: return .green
        default: return .grey
        }
    }

    var weightChangeText: String? {
        guard let averages else { return nil }
        let change = averages.currentAverageKg - averages.pastAverageKg
        let sign = change > 0 ? "+" : (change < 0 ? "−" : "")
        return "\(Format.fixed(averages.pastAverageKg)) → \(Format.fixed(averages.currentAverageKg)) kg (\(sign)\(Format.fixed(abs(change)))) over the last two weeks"
    }

    /// Says whether what the weight did matches the mode chosen with the multiplier.
    var plannedModeText: String? {
        guard let target else { return nil }
        return "Planned: \(target.plannedMode.rawValue)"
    }

    // MARK: Weeks, weight chart

    var thisWeekText: String { averages.map { Format.fixed($0.currentAverageKg) } ?? "–" }
    var lastWeekText: String { averages.map { Format.fixed($0.pastAverageKg) } ?? "–" }

    /// Day of the month keeps 14 labels short and unique; the chart has no room for more.
    var chartPoints: [ChartPoint] {
        weights.reversed().map { entry in
            ChartPoint(label: String(entry.date.string.suffix(2)), value: entry.kg)
        }
    }

    // MARK: Macros

    var macroTitle: String? { target?.macros == nil ? nil : "Cutting macros · \(BodyNumbers.grouped(Double(target?.adjustedTarget ?? 0))) kcal" }

    var macroRows: [BodyMacroRow] {
        guard let target, let macros = target.macros, target.adjustedTarget > 0 else { return [] }
        let total = Double(target.adjustedTarget)
        func share(_ calories: Double) -> Double { min(max(calories / total, 0), 1) }
        return [
            BodyMacroRow(name: "Protein", grams: "\(Format.number(macros.proteinGrams, maxDecimals: 1)) g", share: share(macros.proteinCalories)),
            BodyMacroRow(name: "Carbs", grams: "\(Format.number(macros.carbsGrams, maxDecimals: 1)) g", share: share(macros.carbsCalories)),
            BodyMacroRow(name: "Fat", grams: "\(Format.number(macros.fatGrams, maxDecimals: 1)) g", share: share(macros.fatCalories)),
        ]
    }

    var rulesCaption: String {
        "Rules: protein \(Format.number(rules.proteinGramsPerLb)) g per lb · fat \(Format.number(rules.fatPercent))% of calories"
    }

    // MARK: Calories sheet (the default per day)

    var initialCaloriesText: String { currentDefault.map { Format.number($0.calories) } ?? "" }
    var initialMultiplierText: String { Format.number(currentDefault?.multiplier ?? 1) }
    var initialProteinText: String { Format.number(rules.proteinGramsPerLb) }
    var initialFatText: String { Format.number(rules.fatPercent) }

    var defaultCaption: String {
        guard let currentDefault else { return "No default yet. Set the calories you usually eat per day." }
        return "Default \(BodyNumbers.grouped(currentDefault.calories)) kcal per day since \(Format.longDate(currentDefault.effectiveFrom))"
    }

    /// Live preview for numbers typed in the sheet; nil while they cannot be used.
    func preview(caloriesText: String, multiplierText: String) -> CalorieTarget? {
        guard let calories = Format.decimal(caloriesText), let multiplier = Format.decimal(multiplierText) else { return nil }
        return (try? services.calories.advice(caloriesEaten: calories, multiplier: multiplier))?.target
    }

    /// Rules are saved first so a rejected rule never leaves a half-applied default.
    func saveCalorieSettings(caloriesText: String, multiplierText: String, proteinText: String, fatText: String, from start: ISODate) throws {
        guard let calories = Format.decimal(caloriesText) else { throw ValidationError("Enter the calories per day as a number") }
        guard let multiplier = Format.decimal(multiplierText) else { throw ValidationError("Enter the goal multiplier as a number") }
        guard let protein = Format.decimal(proteinText) else { throw ValidationError("Enter protein g per lb as a number") }
        guard let fat = Format.decimal(fatText) else { throw ValidationError("Enter the fat share as a number") }

        if protein != rules.proteinGramsPerLb { try services.nutrition.setProteinGramsPerLb(protein) }
        if fat != rules.fatPercent { try services.nutrition.setFatPercent(fat) }
        try services.calories.setDefault(calories: calories, multiplier: multiplier, from: start)
    }

    // MARK: Single days

    func saveDay(_ day: ISODate, calories: Double) throws { try services.calories.saveCalories(on: day, calories: calories) }

    func clearDay(_ day: ISODate) throws { try services.calories.deleteCalories(on: day) }

    func day(_ date: ISODate) -> CalorieDay? { try? services.calories.day(date) }

    /// Further back than the 7 days on the Body screen, newest first.
    func calorieDays(count: Int) -> [CalorieDay] { (try? services.calories.days(endingOn: today, count: count)) ?? [] }

    func allWeights() -> [BodyWeightEntry] { (try? services.logBody.recentWeights(limit: 100_000)) ?? [] }

    // MARK: Weigh-ins

    func logWeight(kg: Double, on date: ISODate) throws { try services.logBody.logWeight(kg: kg, on: date) }

    func updateWeight(_ entry: BodyWeightEntry, kg: Double, on date: ISODate) throws {
        try services.logBody.updateWeight(id: entry.id, kg: kg, on: date.string)
    }

    func deleteWeight(_ entry: BodyWeightEntry) throws { try services.logBody.deleteWeight(id: entry.id) }
}
