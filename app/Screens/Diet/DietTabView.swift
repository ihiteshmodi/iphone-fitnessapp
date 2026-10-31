import FitnessCore
import SwiftUI

struct DietTabView: View {
    @EnvironmentObject private var services: Services

    var body: some View {
        // A new database means new services, so the view model must be rebuilt with them.
        DietScreen(services: services).id(ObjectIdentifier(services))
    }
}

enum DietSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case plan = "Plan"
    case foods = "Foods"
    var id: String { rawValue }
}

private struct DietScreen: View {
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var services: Services
    @StateObject private var model: DietViewModel
    @StateObject private var planModel: DietPlanViewModel
    @StateObject private var foodsModel: FoodsViewModel
    @State private var section = DietSection.today
    @State private var addingExtra = false
    @State private var editingExtra: ExtraEntry?

    init(services: Services) {
        _model = StateObject(wrappedValue: DietViewModel(services: services))
        _planModel = StateObject(wrappedValue: DietPlanViewModel(services: services))
        _foodsModel = StateObject(wrappedValue: FoodsViewModel(services: services))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    DietSegmentPicker(selection: $section)
                    switch section {
                    case .today: DietTodayView(model: model, onAddExtra: { addingExtra = true }, onEditExtra: { editingExtra = try? services.dietDays.entry(of: $0.id) }, onEditPlan: { section = .plan })
                    case .plan: DietPlanView(model: planModel)
                    case .foods: DietFoodsView(model: foodsModel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .task(id: session.revision) { model.load() }
        .onAppear(perform: openRequestedDay)
        .onChange(of: session.dietDayToOpen) { _ in openRequestedDay() }
        .errorAlert($model.errorMessage)
        .errorAlert($planModel.errorMessage)
        .sheet(item: $editingExtra) { entry in
            DietAddExtraSheet(services: services, date: model.date, editing: entry) { session.didChange() }
        }
        .sheet(isPresented: $addingExtra) {
            DietAddExtraSheet(services: services, date: model.date, recent: model.recentExtras) { session.didChange() }
        }
    }

    /// Another screen (Body) asked to see a day here.
    private func openRequestedDay() {
        guard let day = session.dietDayToOpen else { return }
        session.dietDayToOpen = nil
        section = .today
        model.show(day)
    }

    private var header: some View {
        BodyHeader(caption: section == .foods ? foodsModel.countText : model.caption, title: "Diet")
    }
}

/// Today | Plan | Foods switch, drawn like the mockups.
struct DietSegmentPicker<Value: Hashable & CaseIterable & Identifiable & RawRepresentable>: View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Value.allCases)) { item in
                Button(item.rawValue) { selection = item }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(selection == item ? Theme.onGreen : Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selection == item ? Theme.green : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .accessibilityIdentifier("diet-segment-\(item.rawValue.lowercased())")
                    .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
