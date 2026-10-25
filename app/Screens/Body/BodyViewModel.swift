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
    @Published private(set) var latestEntry: CalorieEntry?
    @Published private(set) var target: CalorieTarget?
    @Published private(set) var averages: WeeklyAverages?
    @Published private(set) var averagesNotice: String?
    /// Newest first.
    @Published private(set) var weights: [BodyWeightEntry] = []
    @Published private(set) var rules = MacroRules(proteinGramsPerLb: 1.2, fatPercent: 25)
    @Published private(set) var loadError: String?

    private let services: Services

    init(services: Services) { self.services = services }

    var today: ISODate { services.clock.today() }

    func load() {
        do {
            latestEntry = try services.calories.latestEntry()
            rules = try services.nutrition.rules()
            weights = try services.logBody.recentWeights(limit: 14)
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

        target = latestEntry == nil ? nil : (try? services.calories.currentAdvice())?.target
    }

    // MARK: Ring card

    var eatenText: String { latestEntry.map { BodyNumbers.grouped($0.calories.rounded()) } ?? "–" }

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
        if latestEntry == nil { return "Enter the calories you eat per day to get your target." }
        return averagesNotice
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

    // MARK: Calories sheet

    var initialCaloriesText: String { latestEntry.map { Format.number($0.calories) } ?? "" }
    var initialMultiplierText: String { Format.number(latestEntry?.multiplier ?? 1) }
    var initialProteinText: String { Format.number(rules.proteinGramsPerLb) }
    var initialFatText: String { Format.number(rules.fatPercent) }

    /// Live preview for numbers typed in the sheet; nil while they cannot be used.
    func preview(caloriesText: String, multiplierText: String) -> CalorieTarget? {
        guard let calories = Format.decimal(caloriesText), let multiplier = Format.decimal(multiplierText) else { return nil }
        return (try? services.calories.advice(caloriesEaten: calories, multiplier: multiplier))?.target
    }

    /// Rules are saved first so a rejected rule never leaves a half-applied calorie entry.
    func saveCalorieSettings(caloriesText: String, multiplierText: String, proteinText: String, fatText: String) throws {
        guard let calories = Format.decimal(caloriesText) else { throw ValidationError("Enter the calories eaten per day as a number") }
        guard let multiplier = Format.decimal(multiplierText) else { throw ValidationError("Enter the goal multiplier as a number") }
        guard let protein = Format.decimal(proteinText) else { throw ValidationError("Enter protein g per lb as a number") }
        guard let fat = Format.decimal(fatText) else { throw ValidationError("Enter the fat share as a number") }

        if protein != rules.proteinGramsPerLb { try services.nutrition.setProteinGramsPerLb(protein) }
        if fat != rules.fatPercent { try services.nutrition.setFatPercent(fat) }
        try services.calories.saveCalories(on: today, calories: calories, multiplier: multiplier)
    }

    // MARK: Weigh-ins

    func logWeight(kg: Double, on date: ISODate) throws { try services.logBody.logWeight(kg: kg, on: date) }

    func updateWeight(_ entry: BodyWeightEntry, kg: Double, on date: ISODate) throws {
        try services.logBody.updateWeight(id: entry.id, kg: kg, on: date.string)
    }

    func deleteWeight(_ entry: BodyWeightEntry) throws { try services.logBody.deleteWeight(id: entry.id) }
}
