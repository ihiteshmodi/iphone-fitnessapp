import FitnessCore
import SwiftUI

@MainActor
final class DietPlanViewModel: ObservableObject {
    @Published var editFrom: ISODate
    @Published private(set) var plan: DietPlan?
    @Published private(set) var planned: DietDay?
    @Published private(set) var foods: [Int: Food] = [:]
    @Published private(set) var rules = DietRules(proteinMinimumGrams: 180, fatPercentOfCalories: 20, fatCeilingGramsPerPound: 0.4)
    @Published private(set) var training: Set<Int> = []
    @Published var errorMessage: String?

    private let services: Services

    init(services: Services) {
        self.services = services
        editFrom = services.clock.today()
    }

    var today: ISODate { services.clock.today() }

    func load() {
        do {
            plan = try services.dietPlans.plan(inForceOn: editFrom)
            planned = try services.dietDays.day(editFrom)
            foods = try services.foods.book().foods
            rules = try services.dietRules.load()
            training = try services.dietPlans.trainingWeekdays()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setEditFrom(_ date: ISODate) {
        editFrom = date
        load()
    }

    func food(_ id: Int) -> Food? { foods[id] }

    var mealNames: [String] { plan?.meals.map(\.name) ?? [] }

    // MARK: Text

    var changesText: String {
        if let plan, plan.effectiveFrom == editFrom { return "These changes are part of the plan that starts on \(Format.longDate(editFrom))." }
        return "A change you make now starts on \(Format.longDate(editFrom)). Earlier days keep the plan they had."
    }

    var totalsRows: [(value: String, label: String)] {
        guard let planned else { return [] }
        let t = planned.planned
        return [(Format.grouped(t.calories), "kcal"),
                ("\(Format.number(t.protein, maxDecimals: 0)) g", "protein (min \(Format.number(rules.proteinMinimumGrams, maxDecimals: 0)))"),
                ("\(Format.number(t.fat, maxDecimals: 0)) g", "fat (limit \(Format.number(planned.targets.fatLimitGrams, maxDecimals: 1)))")]
    }

    func cycleText(_ item: PlanItem) -> String? { item.cycle == .daily ? nil : CyclePresentation.summary(item.cycle) }

    // MARK: Edits

    func add(foodID: Int, quantity: Double, meal: String, cycle: CycleRule) -> Bool {
        run { try self.services.dietPlans.addItem(foodID: foodID, quantity: quantity, meal: meal, cycle: cycle, from: self.editFrom) }
    }

    func change(_ item: PlanItem, quantity: Double, cycle: CycleRule, meal: String) -> Bool {
        run {
            try self.services.dietPlans.changeItem(meal: item.meal, foodID: item.foodID, from: self.editFrom, quantity: quantity, cycle: cycle,
                                                   moveTo: meal == item.meal ? nil : meal)
        }
    }

    func remove(_ item: PlanItem) -> Bool {
        run { try self.services.dietPlans.removeItem(meal: item.meal, foodID: item.foodID, from: self.editFrom) }
    }

    func saveRules(protein: String, fatPercent: String, ceiling: String) -> Bool {
        run {
            guard let p = Format.decimal(protein) else { throw ValidationError("Enter the protein minimum as a number") }
            guard let f = Format.decimal(fatPercent) else { throw ValidationError("Enter the fat share as a number") }
            guard let c = Format.decimal(ceiling) else { throw ValidationError("Enter the fat ceiling as a number") }
            try self.services.dietRules.setProteinMinimum(p)
            try self.services.dietRules.setFatPercent(f)
            try self.services.dietRules.setFatCeilingPerPound(c)
        }
    }

    private func run(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// The Plan section: the daily plan by meal. Changes start on a date (today by default) and never rewrite earlier days.
struct DietPlanView: View {
    @ObservedObject var model: DietPlanViewModel
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var editing: PlanItem?
    @State private var addingToMeal: MealTarget?
    @State private var editingRules = false

    private struct MealTarget: Identifiable {
        let name: String
        var id: String { name }
    }

    var body: some View {
        VStack(spacing: 12) {
            startCard
            totalsCard
            if let plan = model.plan {
                ForEach(plan.meals, id: \.name) { meal in mealCard(meal) }
            } else {
                Text("There is no plan yet. Add a food to start one.").font(.system(size: 13)).foregroundColor(Theme.muted).card()
            }
            Button("+ Add to a new meal") { addingToMeal = MealTarget(name: "") }
                .buttonStyle(PrimaryButtonStyle(ghost: true)).font(.system(size: 14))
                .accessibilityIdentifier("plan-new-meal")
            rulesCard
        }
        .task(id: session.revision) { model.load() }
        .sheet(item: $editing) { item in
            DietPlanItemSheet(services: services, model: model, item: item, meal: item.meal) { session.didChange() }
        }
        .sheet(item: $addingToMeal) { target in
            DietPlanItemSheet(services: services, model: model, item: nil, meal: target.name) { session.didChange() }
        }
        .sheet(isPresented: $editingRules) { DietRulesSheet(model: model) { session.didChange() } }
    }

    private var startCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Changes start on")
                    Text(Format.longDate(model.editFrom)).font(.system(size: 17, weight: .bold)).foregroundColor(Theme.text)
                        .accessibilityIdentifier("plan-edit-from")
                }
                Spacer()
                DatePicker("Changes start on", selection: Binding(get: { BodyDates.date(from: model.editFrom) },
                                                                set: { model.setEditFrom(BodyDates.day(from: $0)) }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .accessibilityIdentifier("plan-edit-from-picker")
            }
            Text(model.changesText).font(.system(size: 12)).foregroundColor(Theme.muted)
        }
        .card()
    }

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Plan totals")
            HStack(alignment: .top) {
                ForEach(model.totalsRows, id: \.label) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.value).font(.system(size: 20, weight: .heavy)).foregroundColor(Theme.text)
                        Text(row.label).font(.system(size: 10.5)).foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .card()
    }

    private func mealCard(_ meal: PlanMeal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(meal.name)
                Spacer()
                Button("+ Add") { addingToMeal = MealTarget(name: meal.name) }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("plan-add-\(meal.name)")
            }
            VStack(spacing: 0) {
                ForEach(meal.items) { item in
                    Button { editing = item } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.food(item.foodID)?.name ?? "").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                                if let cycle = model.cycleText(item) { Pill(text: "⟳ \(cycle)", tone: .green) }
                            }
                            Spacer()
                            Text(Format.amount(item.quantity, unit: model.food(item.foodID)?.unit ?? "")).font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                            Text("Edit").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                        }
                        .padding(.vertical, 9).padding(.horizontal, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("plan-item-\(meal.name)-\(model.food(item.foodID)?.name ?? "")")
                    .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 10) }
                }
            }
            .card(padding: 4)
        }
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Targets")
                Spacer()
                Button("Edit") { editingRules = true }.font(.system(size: 12, weight: .semibold)).accessibilityIdentifier("plan-edit-rules")
            }
            Text("Protein at least \(Format.number(model.rules.proteinMinimumGrams, maxDecimals: 0)) g · fat up to \(Format.number(model.rules.fatPercentOfCalories))% of calories, never above \(Format.number(model.rules.fatCeilingGramsPerPound)) g per lb of body weight.")
                .font(.system(size: 13)).foregroundColor(Theme.muted)
        }
        .card()
    }
}

/// The three numbers every day is measured against.
struct DietRulesSheet: View {
    @ObservedObject var model: DietPlanViewModel
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var protein = ""
    @State private var fatPercent = ""
    @State private var ceiling = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BodyField(label: "Protein minimum", text: $protein, unit: "g", identifier: "rules-protein-field")
                    BodyField(label: "Fat share of calories", text: $fatPercent, unit: "%", identifier: "rules-fat-field")
                    BodyField(label: "Fat ceiling per lb of body weight", text: $ceiling, unit: "g", identifier: "rules-ceiling-field")
                    Text("The fat limit on a day is the smaller of the share of that day's calories and the ceiling (your 7-day average weight in lb times this number).")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                    Button("Save") {
                        if model.saveRules(protein: protein, fatPercent: fatPercent, ceiling: ceiling) {
                            onSaved()
                            dismiss()
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("rules-save-button")
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Targets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($model.errorMessage)
        }
        .onAppear {
            protein = Format.number(model.rules.proteinMinimumGrams)
            fatPercent = Format.number(model.rules.fatPercentOfCalories)
            ceiling = Format.number(model.rules.fatCeilingGramsPerPound)
        }
    }
}
