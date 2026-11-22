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
    /// nil shows the live numbers; a past day shows the calorie maths as it stood on that day.
    @Published private(set) var asOf: ISODate?
    @Published private(set) var currentBreak: BreakPeriod?
    @Published private(set) var effective: EffectiveCalories?
    @Published private(set) var calorieBasis = CalorieBasis.total
    @Published private(set) var goalMode = GoalMode.maintain
    /// Shown while on a break and while recalibrating after one, so the pre-break picture is never lost.
    @Published private(set) var beforeBreak: (period: BreakPeriod, summary: BeforeBreak)?

    private let services: Services

    init(services: Services) { self.services = services }

    var today: ISODate { services.clock.today() }
    var shownDay: ISODate { asOf ?? today }
    var isShowingPastDay: Bool { asOf != nil }
    var canGoForward: Bool { asOf != nil }
    var headerCaption: String { asOf.map { "As of \(Format.weekdayDate($0))" } ?? "Last 7 days" }

    func show(day: ISODate) {
        asOf = day < today ? day : nil
        load()
    }

    func showPreviousDay() { show(day: shownDay.adding(days: -1)) }
    func showNextDay() { show(day: shownDay.adding(days: 1)) }

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
            averages = try asOf.map { try services.calories.weeklyAverages(asOf: $0) } ?? services.calories.weeklyAverages()
            averagesNotice = nil
        } catch {
            averages = nil
            averagesNotice = error.localizedDescription
        }

        currentBreak = try? services.breaks.current(on: shownDay)
        let isRecalibrating = averagesNotice?.hasPrefix("Recalibrating") == true
        if currentBreak != nil || isRecalibrating,
           let period = (try? services.breaks.periods())?.last(where: { $0.start <= shownDay }),
           let summary = try? services.breaks.beforeBreak(period, calories: services.calories) {
            beforeBreak = (period, summary)
        } else {
            beforeBreak = nil
        }

        let advice = try? (asOf.map { try services.calories.advice(asOf: $0) } ?? services.calories.currentAdvice())
        target = advice?.target
        averageEaten = advice?.target.caloriesEaten ?? (try? services.calories.averageCalories(endingOn: shownDay.adding(days: -1), days: 7)) ?? nil
        let foodEnd = (advice?.averages.latestWeighIn ?? shownDay).adding(days: -1)
        effective = try? services.calories.effectiveCalories(endingOn: foodEnd, days: 7)
        let appSettings = try? services.settings.load()
        calorieBasis = appSettings?.calorieBasis ?? .total
        goalMode = appSettings?.explicitGoalMode ?? (currentDefault.map { $0.multiplier < 1 ? .cut : ($0.multiplier > 1 ? .bulk : .maintain) } ?? .maintain)
    }

    func setGoalMode(_ mode: GoalMode) {
        try? services.settings.setGoalMode(mode, since: today)
        load()
    }

    // MARK: Effective calories

    var usesEffective: Bool { calorieBasis == .effective && effective != nil }

    /// Calories digestion takes from what was eaten, per day on average; maintenance and target move by the same amount.
    private var digestion: Double { (averageEaten ?? 0) - (effective?.average ?? averageEaten ?? 0) }

    var effectiveText: String? { effective.map { BodyNumbers.grouped($0.average) } }
    var digestionText: String? {
        effective.map { "Digestion uses \(BodyNumbers.grouped(digestion)) kcal a day (\(Format.number($0.share * 100, maxDecimals: 1))%)" }
    }
    var digestionRows: [(String, String)] {
        guard let cost = effective?.typicalDayCost else { return [] }
        return [("Protein · 25%", cost.protein), ("Carbs · 7.5%", cost.carbs), ("Fat · 1.5%", cost.fat), ("Alcohol · 0%", cost.alcohol)]
            .map { ($0.0, "−\(BodyNumbers.grouped($0.1))") }
    }

    func setCalorieBasis(_ basis: CalorieBasis) {
        try? services.settings.setCalorieBasis(basis)
        load()
    }

    // MARK: Break

    var beforeBreakTitle: String? { beforeBreak.map { "Before your break · \(Format.shortDate($0.period.start.adding(days: -1)))" } }
    var beforeBreakMaintenance: String? { beforeBreak.map { BodyNumbers.grouped($0.summary.advice.target.maintenanceCalories) } }
    var beforeBreakEaten: String? { beforeBreak.map { BodyNumbers.grouped($0.summary.advice.target.caloriesEaten) } }
    var beforeBreakStatus: String? {
        guard let target = beforeBreak?.summary.advice.target else { return nil }
        let balance = target.balance == .maintenance ? "holding weight" : "\(target.balance.rawValue.lowercased()) \(BodyNumbers.grouped(abs(target.dailyBalanceKcal)))/day"
        return "\(target.plannedMode.rawValue) · \(balance)"
    }
    var weightAcrossBreak: String? {
        guard let summary = beforeBreak?.summary, let before = summary.weightBeforeKg else { return nil }
        guard let after = summary.weightAfterKg else { return "\(Format.number(before)) kg before" }
        return "\(Format.number(before)) → \(Format.number(after)) kg"
    }

    // MARK: Ring card

    var eatenText: String {
        let shown = usesEffective ? effective?.average : averageEaten
        return shown.map { BodyNumbers.grouped($0.rounded()) } ?? "–"
    }
    var eatenCaption: String { usesEffective ? "effective / day" : "eaten / day" }

    var ringProgress: Double {
        guard let target, target.maintenanceCalories > 0 else { return 0 }
        return min(max(target.caloriesEaten / target.maintenanceCalories, 0), 1)
    }

    var phaseText: String? { target?.phase.rawValue }
    var phaseTone: Pill.Tone { target?.phase == .cut ? .amber : .green }
    var maintenanceText: String {
        target.map { BodyNumbers.grouped(($0.maintenanceCalories - (usesEffective ? digestion : 0)).rounded()) } ?? "–"
    }
    var newTargetText: String? {
        target.map { t in
            let shown = usesEffective ? (t.maintenanceCalories - digestion) * t.multiplier : Double(t.adjustedTarget)
            return "New target \(BodyNumbers.grouped(shown))\(usesEffective ? " effective" : "")"
        }
    }

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
        return "\(Format.fixed(averages.pastAverageKg)) → \(Format.fixed(averages.currentAverageKg)) kg (\(sign)\(Format.fixed(abs(change)))) over the two weeks to \(Format.shortDate(averages.latestWeighIn))"
    }

    /// Says whether what the weight did matches the mode chosen with the multiplier.
    var plannedModeText: String? {
        "Mode: \(goalMode.title)"
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
    func saveCalorieSettings(caloriesText: String, multiplierText: String, proteinText: String, fatText: String,
                             goalMode chosenMode: GoalMode? = nil, from start: ISODate) throws {
        guard let calories = Format.decimal(caloriesText) else { throw ValidationError("Enter the calories per day as a number") }
        guard let multiplier = Format.decimal(multiplierText) else { throw ValidationError("Enter the goal multiplier as a number") }
        guard let protein = Format.decimal(proteinText) else { throw ValidationError("Enter protein g per lb as a number") }
        guard let fat = Format.decimal(fatText) else { throw ValidationError("Enter the fat share as a number") }

        if protein != rules.proteinGramsPerLb { try services.nutrition.setProteinGramsPerLb(protein) }
        if fat != rules.fatPercent { try services.nutrition.setFatPercent(fat) }
        try services.calories.setDefault(calories: calories, multiplier: multiplier, from: start)
        if let chosenMode {
            try services.settings.setGoalMode(chosenMode, since: start)
        }
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
