import FitnessCore
import SwiftUI

/// Pick any past day and fix whatever was logged on it: sets, weigh-ins, calories and measurement readings.
struct EditPastDataView: View {
    @EnvironmentObject private var services: Services
    var body: some View { EditPastDataContent(services: services).id(ObjectIdentifier(services)) }
}

private enum PastSheet: Identifiable {
    case set(LoggedSet)
    case weight(BodyWeightEntry)
    case newWeight
    case calories(CalorieDay)
    case reading(SiteReading)

    var id: String {
        switch self {
        case .set(let set): return "set-\(set.id)"
        case .weight(let entry): return "weight-\(entry.id)"
        case .newWeight: return "new-weight"
        case .calories(let day): return "calories-\(day.date.string)"
        case .reading(let item): return "reading-\(item.reading.id)"
        }
    }
}

private struct EditPastDataContent: View {
    @EnvironmentObject private var session: AppSession
    @StateObject private var body_: BodyViewModel
    private let services: Services

    @State private var date = Date()
    @State private var sets: [LoggedSet] = []
    @State private var weights: [BodyWeightEntry] = []
    @State private var readings: [SiteReading] = []
    @State private var calorieDay: CalorieDay?
    @State private var sheet: PastSheet?

    init(services: Services) {
        self.services = services
        _body_ = StateObject(wrappedValue: BodyViewModel(services: services))
    }

    private var day: ISODate { BodyDates.day(from: date) }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    SectionLabel("Day")
                    Spacer()
                    DatePicker("Day", selection: $date, in: ...BodyDates.date(from: body_.today), displayedComponents: .date)
                        .labelsHidden()
                        .accessibilityIdentifier("past-day-picker")
                }
                .card()
                setsCard
                weightsCard
                caloriesCard
                readingsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationTitle("Edit past data")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { date = BodyDates.date(from: body_.today) }
        .task(id: "\(day.string)-\(session.revision)") { reload() }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .set(let set):
                PastSetEditSheet(services: services, set: set) { session.didChange() }
            case .weight(let entry):
                BodyValueEntrySheet(title: "Edit weigh-in", fieldLabel: "Weight", unit: "kg", initialText: Format.number(entry.kg),
                                    initialDate: entry.date, today: body_.today, deleteTitle: "Delete weigh-in",
                                    onDelete: {
                                        try body_.deleteWeight(entry)
                                        session.didChange()
                                    }) { kg, chosen in
                    try body_.updateWeight(entry, kg: kg, on: chosen)
                    session.didChange()
                }
            case .newWeight:
                BodyValueEntrySheet(title: "Add weigh-in", fieldLabel: "Weight", unit: "kg", fixedDay: day, today: body_.today) { kg, chosen in
                    try body_.logWeight(kg: kg, on: chosen)
                    session.didChange()
                }
            case .calories(let calories):
                CalorieDayEditSheet(model: body_, day: calories) { session.didChange() }
            case .reading(let item):
                BodyValueEntrySheet(title: "Edit \(item.site)", fieldLabel: "Measurement", unit: "in", initialText: Format.fixed(item.reading.inches),
                                    initialDate: item.reading.date, today: body_.today, deleteTitle: "Delete reading",
                                    onDelete: {
                                        try services.measurements.deleteReading(id: item.reading.id)
                                        session.didChange()
                                    }) { inches, chosen in
                    try services.measurements.updateReading(id: item.reading.id, inches: inches, on: chosen.string)
                    session.didChange()
                }
            }
        }
    }

    private func reload() {
        sets = (try? services.logSets.sets(on: day)) ?? []
        weights = (try? services.logBody.weights(on: day)) ?? []
        readings = (try? services.measurements.readings(on: day)) ?? []
        calorieDay = body_.day(day)
    }

    // MARK: Cards

    private var setsCard: some View {
        card("Sets", empty: "No sets logged this day.", isEmpty: sets.isEmpty) {
            ForEach(sets) { set in
                row(title: set.exerciseName, value: "\(Format.number(set.weightKg)) kg × \(set.reps)", id: "past-set-\(set.id)") { sheet = .set(set) }
            }
        }
    }

    private var weightsCard: some View {
        card("Weigh-ins", empty: "No weigh-in this day.", isEmpty: weights.isEmpty) {
            ForEach(weights) { entry in
                row(title: Format.shortDate(entry.date), value: "\(Format.number(entry.kg)) kg", id: "past-weight-\(entry.id)") { sheet = .weight(entry) }
            }
        } footer: {
            Button("+ Add weigh-in for this day") { sheet = .newWeight }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.green)
                .padding(.top, 8)
                .accessibilityIdentifier("past-add-weight")
        }
    }

    @ViewBuilder
    private var caloriesCard: some View {
        if let calorieDay {
            card("Calories", empty: "", isEmpty: false) {
                CalorieDayRow(day: calorieDay, identifier: "past-calories") { sheet = .calories(calorieDay) }
            }
        }
    }

    private var readingsCard: some View {
        card("Measurements", empty: "No measurements this day.", isEmpty: readings.isEmpty) {
            ForEach(readings, id: \.reading.id) { item in
                row(title: item.site, value: "\(Format.fixed(item.reading.inches)) in", id: "past-reading-\(item.reading.id)") { sheet = .reading(item) }
            }
        }
    }

    private func card<Content: View>(_ title: String, empty: String, isEmpty: Bool, @ViewBuilder content: () -> Content) -> some View {
        card(title, empty: empty, isEmpty: isEmpty, content: content) { EmptyView() }
    }

    private func card<Content: View, Footer: View>(_ title: String, empty: String, isEmpty: Bool, @ViewBuilder content: () -> Content,
                                                   @ViewBuilder footer: () -> Footer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel(title).padding(.bottom, 4)
            if isEmpty {
                Text(empty).font(.system(size: 13)).foregroundColor(Theme.muted).padding(.vertical, 6)
            } else {
                content()
            }
            footer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func row(title: String, value: String, id: String, action: @escaping () -> Void) -> some View {
        BodyHistoryRow(date: title, value: value, identifier: id, action: action)
    }
}

/// Corrects or deletes one set found by date. Unlike the exercise screen the exercise is already known.
private struct PastSetEditSheet: View {
    let services: Services
    let set: LoggedSet
    let onChanged: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weight = ""
    @State private var reps = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @State private var confirmingDelete = false
    @State private var prepared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        BodyField(label: "Weight (kg)", text: $weight, identifier: "weight-field")
                        BodyField(label: "Reps", text: $reps, identifier: "reps-field", keyboard: .numberPad)
                    }
                    HStack {
                        SectionLabel("Date")
                        Spacer()
                        DatePicker("Date", selection: $date, in: ...BodyDates.date(from: services.clock.today()), displayedComponents: .date)
                            .labelsHidden()
                    }
                    Button("Delete set") { confirmingDelete = true }
                        .buttonStyle(BodyDestructiveButtonStyle())
                        .accessibilityIdentifier("past-delete-set")
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle(set.exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.bold).accessibilityIdentifier("sheet-save-button") }
            }
            .confirmationDialog("Delete this set?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
                Button("Keep", role: .cancel) {}
            }
            .errorAlert($errorMessage)
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            weight = Format.number(set.weightKg)
            reps = String(set.reps)
            date = BodyDates.date(from: set.date)
        }
    }

    private func save() {
        guard let kg = Format.decimal(weight) else { return errorMessage = "Enter the weight in kg (0 for bodyweight)" }
        guard let count = Int(reps.trimmingCharacters(in: .whitespaces)) else { return errorMessage = "Enter the number of reps" }
        do {
            try services.logSets.updateSet(id: set.id, weightKg: kg, reps: count, on: BodyDates.day(from: date))
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        do {
            try services.logSets.deleteSet(id: set.id)
            onChanged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
