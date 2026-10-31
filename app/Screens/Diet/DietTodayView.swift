import FitnessCore
import SwiftUI

/// The Today section: the day's total, the protein and fat targets, every planned item with a tick, and the extras.
struct DietTodayView: View {
    @ObservedObject var model: DietViewModel
    let onAddExtra: () -> Void
    let onEditExtra: (DietExtra) -> Void
    let onEditPlan: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            dateBar
            if let typed = model.typedCalories { typedNotice(typed) }
            if let day = model.day {
                summaryCard(day)
                if day.hasPlan {
                    ForEach(day.meals, id: \.name) { meal in mealCard(meal) }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("There is no diet plan on this day. Plans start on a date and apply from then on.")
                            .font(.system(size: 13)).foregroundColor(Theme.muted)
                        Button("Edit plan", action: onEditPlan).buttonStyle(PrimaryButtonStyle(ghost: true)).accessibilityIdentifier("diet-edit-plan")
                    }
                    .card()
                }
                extrasCard(day)
            }
        }
    }

    private func typedNotice(_ typed: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You typed \(Format.grouped(typed)) kcal for this day in Body. That total is what counts, not this diet.")
                .font(.system(size: 13)).foregroundColor(Theme.amber)
            Button("Use the diet instead") { model.useDietInstead() }
                .buttonStyle(PrimaryButtonStyle(ghost: true)).font(.system(size: 14))
                .accessibilityIdentifier("diet-use-diet-instead")
        }
        .card()
        .accessibilityIdentifier("diet-typed-notice")
    }

    // MARK: Date

    private var dateBar: some View {
        HStack {
            arrow("‹", id: "diet-previous-day") { model.shift(days: -1) }
            Spacer()
            VStack(spacing: 2) {
                Text(model.dateTitle).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                    .accessibilityIdentifier("diet-date")
                if model.date != model.today {
                    Button("Back to today") { model.show(model.today) }
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityIdentifier("diet-back-to-today")
                }
            }
            Spacer()
            arrow("›", id: "diet-next-day") { model.shift(days: 1) }
        }
    }

    private func arrow(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.green)
                .frame(width: 38, height: 38)
                .background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier(id)
    }

    // MARK: Summary

    private func summaryCard(_ day: DietDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                RingView(progress: model.ringProgress, size: 92, lineWidth: 9, label: model.totalText, subLabel: "kcal")
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(model.caption)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(model.totalText).font(.system(size: 30, weight: .heavy)).foregroundColor(Theme.text)
                            .accessibilityIdentifier("diet-total-calories")
                        Text("kcal").font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    Text(model.equation).font(.system(size: 12)).foregroundColor(Theme.muted)
                    Text(model.costText).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            ForEach(model.macroRows) { macroBar($0) }
        }
        .card()
    }

    private func macroBar(_ row: DietMacroRow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(row.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                Text(row.value).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                Text(row.note).font(.system(size: 12)).foregroundColor(color(row.tone))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill(color(row.tone == .grey ? .green : row.tone)).frame(width: max(4, proxy.size.width * row.progress))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("diet-macro-\(row.name.lowercased())")
    }

    private func color(_ tone: Pill.Tone) -> Color {
        switch tone {
        case .green: return Theme.green
        case .amber: return Theme.amber
        case .red: return Theme.red
        case .gold: return Theme.gold
        case .grey: return Theme.muted
        }
    }

    // MARK: Meals

    private func mealCard(_ meal: DietMeal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { model.toggle(meal) } label: {
                HStack(spacing: 8) {
                    mealCheckbox(meal)
                    SectionLabel(meal.name)
                    Spacer()
                    Text("\(Format.grouped(meal.eatenCalories)) of \(Format.grouped(meal.plannedCalories)) kcal")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!meal.canTick)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("diet-meal-\(meal.name)")
            .accessibilityValue(meal.tickState == .all ? "all" : (meal.tickState == .some ? "some" : "none"))
            VStack(spacing: 0) {
                ForEach(meal.lines) { line in
                    DietLineRow(line: line) { model.toggle(line) }
                }
            }
            .card(padding: 4)
        }
    }

    /// One box for the whole meal: empty, a dash when some items are ticked, a tick when all are.
    private func mealCheckbox(_ meal: DietMeal) -> some View {
        ZStack {
            switch meal.tickState {
            case .all:
                RoundedRectangle(cornerRadius: 7).fill(Theme.green)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundColor(Theme.onGreen)
            case .some:
                RoundedRectangle(cornerRadius: 7).fill(Theme.green.opacity(0.18))
                RoundedRectangle(cornerRadius: 7).stroke(Theme.green, lineWidth: 2)
                Image(systemName: "minus").font(.system(size: 11, weight: .heavy)).foregroundColor(Theme.green)
            case .none:
                RoundedRectangle(cornerRadius: 7).stroke(meal.canTick ? Color(hex: 0x34403A) : Theme.line, lineWidth: 2)
            }
        }
        .frame(width: 20, height: 20)
    }

    // MARK: Extras

    private func extrasCard(_ day: DietDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Extras")
                Spacer()
                Text(day.extras.isEmpty ? "nothing added" : "+\(Format.grouped(day.extrasNutrition.calories)) kcal")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            VStack(alignment: .leading, spacing: 0) {
                if day.extras.isEmpty {
                    Text("Had something that is not in the plan? Add it here.")
                        .font(.system(size: 13)).foregroundColor(Theme.muted).padding(10)
                }
                ForEach(day.extras) { extra in
                    DietExtraRow(extra: extra, onEdit: { onEditExtra(extra) }, onDelete: { model.remove(extra) })
                }
                Button("+ Add extra", action: onAddExtra)
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .font(.system(size: 14))
                    .padding(.horizontal, 6).padding(.vertical, 6)
                    .accessibilityIdentifier("diet-add-extra")
                if let week = model.weekExtrasText {
                    Text(week).font(.system(size: 12)).foregroundColor(Theme.muted).padding(10)
                        .accessibilityIdentifier("diet-week-extras")
                }
            }
            .card(padding: 4)
        }
    }
}

/// One planned item: tap to tick or untick it for the day. Items that are off their cycle are greyed and cannot be ticked.
struct DietLineRow: View {
    let line: DietLine
    let onTap: () -> Void

    private var isOff: Bool { if case .offCycle = line.state { return true } else { return false } }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                checkbox
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(line.name).font(.system(size: 14, weight: .semibold))
                            .foregroundColor(isOff ? Theme.muted : Theme.text)
                        if let cycle = line.cycle { Pill(text: cycle.isOn ? "⟳ On" : "⟳ Off week", tone: cycle.isOn ? .green : .amber) }
                    }
                    Text(subtitle).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 6)
                trailing
            }
            .padding(.vertical, 9).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOff)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("diet-line-\(line.name)")
        .accessibilityValue(stateText)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 10) }
    }

    private var checkbox: some View {
        ZStack {
            switch line.state {
            case .eaten:
                RoundedRectangle(cornerRadius: 8).fill(Theme.green)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundColor(Theme.onGreen)
            case .notEaten:
                RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0x34403A), lineWidth: 2)
            case .offCycle:
                RoundedRectangle(cornerRadius: 8).stroke(Theme.muted, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                Image(systemName: "pause.fill").font(.system(size: 9)).foregroundColor(Theme.muted)
            }
        }
        .frame(width: 24, height: 24)
    }

    private var subtitle: String {
        var text = Format.amount(line.quantity, unit: line.unit)
        if let cycle = line.cycle { text += " · \(CyclePresentation.status(cycle))" }
        return text
    }

    @ViewBuilder
    private var trailing: some View {
        switch line.state {
        case .eaten:
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Format.grouped(line.nutrition.calories)) kcal").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                if line.nutrition.protein + line.nutrition.carbs + line.nutrition.fat >= 1 {
                    Text("P \(Format.number(line.nutrition.protein, maxDecimals: 0)) · C \(Format.number(line.nutrition.carbs, maxDecimals: 0)) · F \(Format.number(line.nutrition.fat, maxDecimals: 0))")
                        .font(.system(size: 10.5)).foregroundColor(Theme.muted)
                }
            }
        case .notEaten:
            Text("\(Format.grouped(line.nutrition.calories)) kcal").font(.system(size: 13)).foregroundColor(Theme.muted)
        case .offCycle:
            Text("not counted").font(.system(size: 12)).foregroundColor(Theme.muted)
        }
    }

    private var stateText: String {
        switch line.state {
        case .eaten: return "eaten"
        case .notEaten: return "not eaten"
        case .offCycle: return "off"
        }
    }
}

/// One extra: tap it to change how much, or the cross to remove it.
struct DietExtraRow: View {
    let extra: DietExtra
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(extra.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Text(detail).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 6)
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Format.grouped(extra.nutrition.calories)) kcal").font(.system(size: 13, weight: .bold)).foregroundColor(Theme.text)
                        Text("P \(Format.number(extra.nutrition.protein, maxDecimals: 0)) · C \(Format.number(extra.nutrition.carbs, maxDecimals: 0)) · F \(Format.number(extra.nutrition.fat, maxDecimals: 0))")
                            .font(.system(size: 10.5)).foregroundColor(Theme.muted)
                    }
                    Text("✎").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.green)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("diet-extra-\(extra.name)")
            Button(action: onDelete) { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted) }
                .accessibilityLabel("Remove \(extra.name)")
                .accessibilityIdentifier("diet-remove-extra-\(extra.name)")
        }
        .padding(.vertical, 9).padding(.horizontal, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, 10) }
    }

    private var detail: String {
        if let pieces = extra.pieces, extra.unit == "g" || extra.unit == "ml" {
            return "\(Format.number(pieces, maxDecimals: 1)) piece\(pieces == 1 ? "" : "s") · \(Format.number(extra.amount, maxDecimals: 1)) \(extra.unit)"
        }
        return Format.amount(extra.amount, unit: extra.unit)
    }
}
