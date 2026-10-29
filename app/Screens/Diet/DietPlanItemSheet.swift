import FitnessCore
import SwiftUI

/// Add a food to the plan, or change one planned item: quantity, meal, and how often it is taken.
struct DietPlanItemSheet: View {
    let services: Services
    @ObservedObject var model: DietPlanViewModel
    let item: PlanItem?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var meal: String
    @State private var query = ""
    @State private var results: [Food] = []
    @State private var food: Food?
    @State private var quantity = ""
    @State private var cycle: CycleDraft
    @State private var confirmingRemove = false

    init(services: Services, model: DietPlanViewModel, item: PlanItem?, meal: String, onSaved: @escaping () -> Void) {
        self.services = services
        self.model = model
        self.item = item
        self.onSaved = onSaved
        _meal = State(initialValue: meal)
        _cycle = State(initialValue: item.map { CycleDraft(rule: $0.cycle, today: model.editFrom) } ?? CycleDraft(today: model.editFrom))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let food {
                        Text(food.name).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text)
                        BodyField(label: "Quantity", text: $quantity, unit: food.unit, identifier: "plan-quantity-field")
                        mealField
                        CycleEditor(draft: $cycle, training: model.training, today: model.today)
                        Button("Save", action: save).buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("plan-item-save")
                        if item != nil {
                            Button("Remove from the plan") { confirmingRemove = true }
                                .buttonStyle(BodyDestructiveButtonStyle()).accessibilityIdentifier("plan-item-remove")
                        }
                        Text("This starts on \(Format.longDate(model.editFrom)). Earlier days keep the plan they had.")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                    } else {
                        searchSection
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(item == nil ? "Add to plan" : "Plan item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($model.errorMessage)
            .confirmationDialog("Remove this item from the plan?", isPresented: $confirmingRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    if let item, model.remove(item) {
                        onSaved()
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            guard let item, food == nil else { return }
            food = model.food(item.foodID)
            quantity = Format.number(item.quantity)
        }
    }

    private var mealField: some View {
        VStack(alignment: .leading, spacing: 8) {
            BodyField(label: "Meal", text: $meal, identifier: "plan-meal-field", keyboard: .default)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.mealNames, id: \.self) { name in
                        Button(name) { meal = name }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(meal == name ? Theme.onGreen : Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(meal == name ? Theme.green : Theme.card)
                            .overlay(Capsule().stroke(Theme.line)).clipShape(Capsule())
                    }
                }
            }
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if meal.isEmpty { BodyField(label: "New meal name", text: $meal, identifier: "plan-meal-field", keyboard: .default) }
            TextField("Search foods", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("plan-search-field")
                .onChange(of: query) { _ in
                    results = Array(((try? services.foods.foods(matching: query)) ?? []).prefix(8))
                }
            ForEach(results) { result in
                Button {
                    food = result
                    quantity = Format.number(Portions.defaultValue(.amount, for: result) == 30 && result.draft.baseQuantity >= 100 ? 50 : 1)
                } label: {
                    Text(result.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 9)
                }
                .accessibilityIdentifier("plan-result-\(result.name)")
            }
        }
    }

    private func save() {
        guard let food else { return }
        guard let value = Format.decimal(quantity) else {
            model.errorMessage = "Enter the quantity as a number"
            return
        }
        let rule: CycleRule
        do { rule = try cycle.rule() } catch {
            model.errorMessage = error.localizedDescription
            return
        }
        let saved = item.map { model.change($0, quantity: value, cycle: rule, meal: meal) }
            ?? model.add(foodID: food.id, quantity: value, meal: meal, cycle: rule)
        if saved {
            onSaved()
            dismiss()
        }
    }
}

/// How often the item is taken: every day, weeks on and off, days on and off, chosen weekdays or training days.
struct CycleEditor: View {
    @Binding var draft: CycleDraft
    let training: Set<Int>
    let today: ISODate

    private static let presets: [(on: Int, off: Int)] = [(2, 1), (3, 1), (4, 2), (1, 1)]
    private static let dayLetters = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("How often")
            modePicker
            switch draft.mode {
            case .everyDay: Text("Taken every day.").font(.system(size: 12)).foregroundColor(Theme.muted)
            case .weeks: weeksSection
            case .days: daysSection
            case .weekdays, .training: weekdaysSection
            }
            if draft.mode != .everyDay { summary }
        }
        .card()
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton("Every day", .everyDay)
            modeButton("Weeks", .weeks)
            modeButton("Days", .days)
            modeButton("Weekdays", .weekdays)
        }
        .padding(4)
        .background(Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func modeButton(_ title: String, _ mode: CycleDraft.Mode) -> some View {
        let selected = draft.mode == mode || (mode == .weekdays && draft.mode == .training)
        return Button(title) {
            if mode == .weekdays && draft.mode == .training { return }
            draft.mode = mode
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(selected ? Theme.onGreen : Theme.muted)
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(selected ? Theme.green : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .accessibilityIdentifier("cycle-mode-\(title)")
    }

    // MARK: Weeks

    private var weeksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.on) { preset in
                        let selected = draft.matchesPreset(on: preset.on, off: preset.off)
                        Button("\(preset.on) on · \(preset.off) off") { draft.applyPreset(on: preset.on, off: preset.off) }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(selected ? Theme.onGreen : Theme.muted)
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(selected ? Theme.green : Theme.card2)
                            .clipShape(Capsule())
                            .accessibilityIdentifier("cycle-preset-\(preset.on)-\(preset.off)")
                    }
                }
            }
            HStack(spacing: 10) {
                counter("Weeks on", value: $draft.weeksOn, id: "cycle-weeks-on")
                counter("Weeks off", value: $draft.weeksOff, id: "cycle-weeks-off")
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("First on week starts (a Monday)")
                    Text(CycleEditor.longMonday(draft.firstMonday)).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                        .accessibilityIdentifier("cycle-first-monday")
                }
                Spacer()
                datePicker("First on week", id: "cycle-start-picker")
            }
        }
    }

    private static func longMonday(_ date: ISODate) -> String { "Mon \(Format.longDate(date))" }

    // MARK: Days

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                counter("Days on", value: $draft.daysOn, id: "cycle-days-on")
                counter("Days off", value: $draft.daysOff, id: "cycle-days-off")
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("On period began")
                    Text(Format.longDate(draft.start)).font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                }
                Spacer()
                datePicker("On period began", id: "cycle-days-start-picker")
            }
        }
    }

    // MARK: Weekdays

    private var weekdaysSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.mode == .training {
                Text("Taken on the days you train (the weekdays set on your workout plan).").font(.system(size: 12)).foregroundColor(Theme.muted)
            } else {
                Text("Tap the days it should appear.").font(.system(size: 12)).foregroundColor(Theme.muted)
                HStack(spacing: 5) {
                    ForEach(Weekdays.Day.allCases, id: \.rawValue) { day in
                        let on = draft.weekdays.contains(day)
                        Button(Self.dayLetters[day.rawValue - 1]) {
                            if on { draft.weekdays.remove(day) } else { draft.weekdays.insert(day) }
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(on ? Theme.onGreen : Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(on ? Theme.green : Theme.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("cycle-day-\(Self.dayLetters[day.rawValue - 1])")
                    }
                }
            }
            SectionLabel("Quick patterns")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quick("Weekdays") { draft.selectWeekdays(.workdays) }
                    quick("Weekends") { draft.selectWeekdays(.weekend) }
                    quick("Every other day") { draft.selectEveryOtherDay() }
                    quick("Training days") { draft.mode = .training }
                }
            }
        }
    }

    private func quick(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.card2).clipShape(Capsule())
            .accessibilityIdentifier("cycle-quick-\(title)")
    }

    // MARK: Shared

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let rule = try? draft.rule() {
                let state = rule.state(on: today, trainingWeekdays: training)
                Text("\(CyclePresentation.summary(rule)) · today: \(CyclePresentation.status(state))")
                    .font(.system(size: 12)).foregroundColor(Theme.green)
                    .accessibilityIdentifier("cycle-summary")
                calendar(rule)
            } else if draft.mode == .weekdays {
                Text("Choose at least one weekday.").font(.system(size: 12)).foregroundColor(Theme.amber)
            }
        }
    }

    private func calendar(_ rule: CycleRule) -> some View {
        let weekOf = draft.mode == .weeks ? draft.firstMonday : today
        let grid = CyclePresentation.grid(rule: rule, weeks: 4, weekOf: weekOf, today: today, trainingWeekdays: training)
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Self.dayLetters, id: \.self) { Text($0).font(.system(size: 10)).foregroundColor(Theme.muted).frame(maxWidth: .infinity) }
            }
            ForEach(grid.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(grid[row], id: \.date) { cell in
                        VStack(spacing: 0) {
                            Text(cell.date.string.suffix(2).drop { $0 == "0" }).font(.system(size: 11, weight: .semibold))
                            Text(cell.isOn ? "on" : "off").font(.system(size: 8)).foregroundColor(Theme.muted)
                        }
                        .foregroundColor(cell.isOn ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 5)
                        .background(cell.isOn ? Theme.green.opacity(0.16) : Theme.amber.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(cell.isToday ? Theme.green : .clear, lineWidth: 2))
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
            }
        }
        .accessibilityIdentifier("cycle-calendar")
    }

    private func counter(_ title: String, value: Binding<Int>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(title)
            HStack {
                Button("−") { value.wrappedValue = max(1, value.wrappedValue - 1) }
                    .accessibilityIdentifier("\(id)-minus")
                Spacer()
                Text("\(value.wrappedValue)").font(.system(size: 20, weight: .heavy)).foregroundColor(Theme.text)
                    .accessibilityIdentifier(id)
                Spacer()
                Button("+") { value.wrappedValue += 1 }.accessibilityIdentifier("\(id)-plus")
            }
            .font(.system(size: 20, weight: .bold))
            .padding(10).background(Theme.card2)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity)
    }

    private func datePicker(_ title: String, id: String) -> some View {
        DatePicker(title, selection: Binding(get: { BodyDates.date(from: draft.start) }, set: { draft.start = BodyDates.day(from: $0) }),
                   displayedComponents: .date)
            .labelsHidden()
            .accessibilityIdentifier(id)
    }
}
