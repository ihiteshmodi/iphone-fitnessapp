import FitnessCore
import SwiftUI

struct BodyTabView: View {
    @EnvironmentObject private var services: Services

    var body: some View {
        // A new database means new services, so the view model must be rebuilt with them.
        BodyScreen(services: services).id(ObjectIdentifier(services))
    }
}

private enum BodySheet: Identifiable {
    case calories
    case logWeight
    case editWeight(BodyWeightEntry)
    case editDay(CalorieDay)

    var id: String {
        switch self {
        case .editDay(let day): return "edit-day-\(day.date.string)"
        case .calories: return "calories"
        case .logWeight: return "log-weight"
        case .editWeight(let entry): return "edit-weight-\(entry.id)"
        }
    }
}

private struct BodyScreen: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var model: BodyViewModel
    @State private var sheet: BodySheet?

    init(services: Services) {
        _model = StateObject(wrappedValue: BodyViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    BodyHeader(caption: "Last 7 days", title: "Body")
                    if let loadError = model.loadError {
                        Text(loadError).font(.system(size: 13)).foregroundColor(Theme.red).card()
                    }
                    ringCard
                    Button("Open today's diet") { session.openDiet(on: model.today) }
                        .buttonStyle(PrimaryButtonStyle(ghost: true))
                        .font(.system(size: 14))
                        .accessibilityIdentifier("open-todays-diet-button")
                    HStack(spacing: 10) {
                        Button("✎ Daily calories") { sheet = .calories }
                            .accessibilityIdentifier("calories-edit-button")
                        Button("✎ Macro rules") { sheet = .calories }
                            .accessibilityIdentifier("macro-rules-button")
                    }
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .font(.system(size: 14))

                    weeksSection
                    if model.weights.isEmpty { emptyWeightCard } else { weightCard }
                    balanceCard
                    macrosCard
                    if !model.weights.isEmpty { recentCard }
                    recentCaloriesCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .screenBackground()
            .navigationTitle("Body")
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: session.revision) { model.load() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .calories:
                BodyCaloriesSheet(model: model, onSaved: { session.didChange() })
            case .logWeight:
                BodyValueEntrySheet(title: "Log weight", fieldLabel: "Weight", unit: "kg", initialDate: model.today, today: model.today) { kg, day in
                    try model.logWeight(kg: kg, on: day)
                    session.didChange()
                }
            case .editDay(let day):
                CalorieDayEditSheet(model: model, day: day) { session.didChange() }
            case .editWeight(let entry):
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
        }
    }

    private var ringCard: some View {
        HStack(spacing: 16) {
            RingView(progress: model.ringProgress, size: 120, lineWidth: 12, label: model.eatenText, subLabel: "eaten / day")
            VStack(alignment: .leading, spacing: 4) {
                if let phase = model.phaseText { Pill(text: phase, tone: model.phaseTone) }
                SectionLabel("Maintenance").padding(.top, 6)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(model.maintenanceText).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                    Text("kcal").font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                if let newTarget = model.newTargetText {
                    Text(newTarget).font(.system(size: 12)).foregroundColor(Theme.green).padding(.top, 2)
                }
                if let hint = model.ringHint {
                    Text(hint).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                if let note = model.calorieSourceNote {
                    Text(note).font(.system(size: 11)).foregroundColor(Theme.muted)
                        .accessibilityIdentifier("calorie-source-note")
                }
            }
            Spacer(minLength: 0)
        }
        .card()
    }

    @ViewBuilder
    private var weeksSection: some View {
        if let notice = model.averagesNotice {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Weekly averages")
                Text(notice).font(.system(size: 14)).foregroundColor(Theme.text)
                Text("The target compares the average of the last 7 days with the 7 days before.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .card()
        } else {
            HStack(spacing: 10) {
                weekCard(label: "This week", value: model.thisWeekText)
                weekCard(label: "Last week", value: model.lastWeekText)
            }
        }
    }

    private func weekCard(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.text)
                Text("kg").font(.system(size: 12)).foregroundColor(Theme.muted)
            }
        }
        .card()
    }

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("Body weight · 14 days")
                Spacer()
                Button("+ Log") { sheet = .logWeight }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("log-weight-button")
            }
            if model.weights.count >= 2 {
                BodyScrollableChart(points: model.chartPoints, columns: model.weights.count)
            } else {
                Text("Log one more weigh-in to see the trend.").font(.system(size: 13)).foregroundColor(Theme.muted)
            }
        }
        .card()
    }

    private var emptyWeightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Body weight")
            Text("No weigh-ins yet").font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
            Text("Log your weight every day. Two weeks of weigh-ins unlock your calorie target.")
                .font(.system(size: 13)).foregroundColor(Theme.muted)
            Button("+ Log weight") { sheet = .logWeight }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("log-weight-button")
        }
        .card()
    }

    @ViewBuilder
    private var macrosCard: some View {
        if let title = model.macroTitle {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(title)
                    Spacer()
                    Button("Edit rules") { sheet = .calories }.font(.system(size: 12, weight: .semibold))
                }
                ForEach(model.macroRows) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(row.name).font(.system(size: 13)).foregroundColor(Theme.text)
                            Spacer()
                            Text(row.grams).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.line)
                                Capsule().fill(Theme.green).frame(width: max(4, proxy.size.width * row.share))
                            }
                        }
                        .frame(height: 6)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text(model.rulesCaption).font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .card()
        }
    }

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Recent weigh-ins")
                Spacer()
                NavigationLink("See all") { BodyHistoryListView(model: model, kind: .weights) }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("see-all-weigh-ins")
            }
            .padding(.bottom, 4)
            ForEach(model.weights.prefix(7)) { entry in
                BodyHistoryRow(date: Format.shortDate(entry.date), value: "\(Format.number(entry.kg)) kg",
                               identifier: "weigh-in-\(entry.id)") { sheet = .editWeight(entry) }
            }
        }
        .card()
    }

    private var recentCaloriesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Recent calories")
                Spacer()
                NavigationLink("See all") { BodyHistoryListView(model: model, kind: .calories) }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("see-all-calories")
            }
            Text(model.defaultCaption).font(.system(size: 12)).foregroundColor(Theme.muted).padding(.bottom, 2)
            Text("Days with a diet plan count the diet. Tap one to open it, add extras or untick an item.")
                .font(.system(size: 12)).foregroundColor(Theme.muted).padding(.bottom, 4)
            ForEach(model.calorieDays) { day in
                CalorieDayRow(day: day, identifier: "calorie-day-\(day.date.string)") {
                    if day.source == .plan { session.openDiet(on: day.date) } else { sheet = .editDay(day) }
                }
            }
        }
        .card()
    }

    /// What the weight trend says happened, next to what the multiplier says was planned.
    @ViewBuilder
    private var balanceCard: some View {
        if let headline = model.balanceHeadline {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel("What your weight says")
                    Spacer()
                    if let planned = model.plannedModeText { Pill(text: planned, tone: .grey) }
                }
                Text(headline).font(.system(size: 17, weight: .semibold)).foregroundColor(Theme.text)
                    .accessibilityIdentifier("balance-headline")
                if let change = model.weightChangeText {
                    Text(change).font(.system(size: 12)).foregroundColor(Theme.muted)
                }
            }
            .card()
        }
    }
}
