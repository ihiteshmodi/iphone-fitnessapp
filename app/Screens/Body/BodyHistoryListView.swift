import FitnessCore
import SwiftUI

/// Everything older than the 7 rows on the Body screen: every weigh-in, or any number of calorie days, each editable.
struct BodyHistoryListView: View {
    enum Kind { case weights, calories }

    let model: BodyViewModel
    let kind: Kind
    @EnvironmentObject private var session: AppSession
    @State private var weights: [BodyWeightEntry] = []
    @State private var dayCount = 30
    @State private var weightToEdit: BodyWeightEntry?
    @State private var dayToEdit: CalorieDay?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch kind {
                case .weights: weightRows
                case .calories: calorieRows
                }
            }
            .card()
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle(kind == .weights ? "All weigh-ins" : "Calories by day")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) { weights = model.allWeights() }
        .sheet(item: $weightToEdit) { entry in
            BodyValueEntrySheet(title: "Edit weigh-in", fieldLabel: "Weight", unit: "kg", initialText: Format.number(entry.kg),
                                initialDate: entry.date, today: model.today, deleteTitle: "Delete weigh-in",
                                onDelete: {
                                    try model.deleteWeight(entry)
                                    session.didChange()
                                }) { kg, day in
                try model.updateWeight(entry, kg: kg, on: day)
                session.didChange()
            }
        }
        .sheet(item: $dayToEdit) { day in CalorieDayEditSheet(model: model, day: day) { session.didChange() } }
    }

    @ViewBuilder
    private var weightRows: some View {
        if weights.isEmpty {
            Text("No weigh-ins yet.").font(.system(size: 14)).foregroundColor(Theme.muted)
        }
        ForEach(weights) { entry in
            BodyHistoryRow(date: Format.longDate(entry.date), value: "\(Format.number(entry.kg)) kg",
                           identifier: "all-weigh-in-\(entry.id)") { weightToEdit = entry }
        }
    }

    @ViewBuilder
    private var calorieRows: some View {
        ForEach(model.calorieDays(count: dayCount)) { day in
            CalorieDayRow(day: day, identifier: "calorie-day-\(day.date.string)") { dayToEdit = day }
        }
        Button("Show earlier days") { dayCount += 60 }
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(Theme.green)
            .padding(.top, 12)
            .accessibilityIdentifier("show-earlier-days-button")
    }
}

/// "Mon 26 Oct ... 3,000 kcal  Default ✎" row.
struct CalorieDayRow: View {
    let day: CalorieDay
    let identifier: String
    let action: () -> Void

    private var sourceText: String {
        switch day.source {
        case .manual: return "Edited"
        case .baseline: return "Default"
        case .none: return "Not set"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(Format.shortDate(day.date)).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                Spacer()
                Text(day.calories.map { "\(BodyNumbers.grouped($0)) kcal" } ?? "–").font(.system(size: 14)).foregroundColor(Theme.text)
                Pill(text: sourceText, tone: day.source == .manual ? .green : .grey)
                Text("✎").font(.system(size: 14, weight: .bold)).foregroundColor(Theme.green)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// Sets or clears the calories of one day; clearing returns the day to the default.
struct CalorieDayEditSheet: View {
    let model: BodyViewModel
    let day: CalorieDay
    let onChanged: () -> Void

    var body: some View {
        BodyValueEntrySheet(title: Format.longDate(day.date), fieldLabel: "Calories", unit: "kcal",
                            initialText: day.calories.map { Format.number($0) } ?? "", fixedDay: day.date, today: model.today,
                            deleteTitle: day.source == .manual ? "Use the default again" : nil,
                            deletePrompt: "Use the default for this day?",
                            onDelete: day.source == .manual ? {
                                try model.clearDay(day.date)
                                onChanged()
                            } : nil) { kcal, chosen in
            try model.saveDay(chosen, calories: kcal)
            onChanged()
        }
    }
}
