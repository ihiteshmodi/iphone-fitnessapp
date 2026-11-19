import FitnessCore
import SwiftUI

@MainActor
final class BreakModeViewModel: ObservableObject {
    @Published private(set) var periods: [BreakPeriod] = []
    @Published var errorMessage: String?

    private let services: Services
    private let onChange: () -> Void

    init(services: Services, onChange: @escaping () -> Void) {
        self.services = services
        self.onChange = onChange
    }

    var today: ISODate { services.clock.today() }
    var current: BreakPeriod? { periods.first { $0.contains(today) } }
    /// Newest first, for the list.
    var listed: [BreakPeriod] { periods.reversed() }

    func load() {
        do { periods = try services.breaks.periods() } catch { errorMessage = error.localizedDescription }
    }

    func startToday() { perform { try self.services.breaks.start(on: self.today) } }
    func endToday() { perform { try self.services.breaks.end(on: self.today) } }
    func add(from start: ISODate, to end: ISODate) { perform { try self.services.breaks.add(from: start, to: end) } }
    func delete(_ period: BreakPeriod) { perform { try self.services.breaks.delete(id: period.id) } }

    func text(for period: BreakPeriod) -> String {
        "\(Format.shortDate(period.start)) – \(period.end.map(Format.shortDate) ?? "ongoing")"
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            load()
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Start, end or plan a break; break days are left out of the calorie maths.
struct BreakModeCard: View {
    @StateObject private var model: BreakModeViewModel
    @State private var planStart = Date()
    @State private var planEnd = Date()
    @State private var isPlanning = false

    init(services: Services, onChange: @escaping () -> Void) {
        _model = StateObject(wrappedValue: BreakModeViewModel(services: services, onChange: onChange))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Break mode")
            if let current = model.current {
                Text("On a break since \(Format.shortDate(current.start))").font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.text)
                Button("End break today") { model.endToday() }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("end-break-button")
            } else {
                Text("Going away? Break days need no food, workouts or weigh-ins, and the calorie maths leaves them out.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Start a break today") { model.startToday() }
                        .accessibilityIdentifier("start-break-button")
                    Button(isPlanning ? "Cancel" : "Plan dates") { isPlanning.toggle() }
                        .accessibilityIdentifier("plan-break-button")
                }
                .buttonStyle(PrimaryButtonStyle(ghost: true))
                .font(.system(size: 14))
            }
            if isPlanning && model.current == nil {
                DatePicker("From", selection: $planStart, displayedComponents: .date).tint(Theme.green)
                DatePicker("To", selection: $planEnd, in: planStart..., displayedComponents: .date).tint(Theme.green)
                Button("Add break") {
                    model.add(from: BodyDates.day(from: planStart), to: BodyDates.day(from: max(planEnd, planStart)))
                    isPlanning = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("add-break-button")
            }
            ForEach(model.listed) { period in
                HStack {
                    Text(model.text(for: period)).font(.system(size: 14)).foregroundColor(Theme.text)
                    Spacer()
                    Button("Remove", role: .destructive) { model.delete(period) }
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityIdentifier("remove-break-\(period.id)")
                }
                .padding(.vertical, 4)
            }
        }
        .card()
        .onAppear { model.load() }
        .errorAlert($model.errorMessage)
    }
}
