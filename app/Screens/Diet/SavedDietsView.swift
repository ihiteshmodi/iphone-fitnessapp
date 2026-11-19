import FitnessCore
import SwiftUI

@MainActor
final class SavedDietsModel: ObservableObject {
    @Published private(set) var diets: [SavedDiet] = []
    @Published var errorMessage: String?

    let day: ISODate
    private let services: Services
    private let onChange: () -> Void

    init(services: Services, day: ISODate, onChange: @escaping () -> Void) {
        self.services = services
        self.day = day
        self.onChange = onChange
    }

    var today: ISODate { services.clock.today() }

    func load() {
        do { diets = try services.savedDiets.all(inForceOn: day) } catch { errorMessage = error.localizedDescription }
    }

    func saveCurrent(as name: String) { perform { try self.services.savedDiets.saveCurrent(as: name, on: self.day) } }
    func use(_ diet: SavedDiet, from start: ISODate) { perform { try self.services.savedDiets.use(diet.id, from: start) } }
    func rename(_ diet: SavedDiet, to name: String) { perform { try self.services.savedDiets.rename(diet.id, to: name) } }
    func delete(_ diet: SavedDiet) { perform { try self.services.savedDiets.delete(diet.id) } }

    func summary(_ diet: SavedDiet) -> String {
        let effective = DigestionCost(diet.nutrition).effective(of: diet.nutrition.calories)
        return "\(diet.mealCount) meals · \(diet.itemCount) foods · \(Format.grouped(diet.nutrition.calories)) kcal (effective \(Format.grouped(effective))) · P \(Format.number(diet.nutrition.protein, maxDecimals: 0)) g"
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

/// Diets kept under a name: save the one in force, switch to any of them from a date.
struct SavedDietsView: View {
    @StateObject private var model: SavedDietsModel
    @State private var naming: NameRequest?
    @State private var choosingStart: SavedDiet?
    @State private var startDate = Date()
    @State private var nameText = ""

    private enum NameRequest: Identifiable {
        case saveCurrent
        case rename(SavedDiet)
        var id: String {
            switch self {
            case .saveCurrent: return "save"
            case .rename(let diet): return "rename-\(diet.id)"
            }
        }
    }

    init(services: Services, day: ISODate, onChange: @escaping () -> Void) {
        _model = StateObject(wrappedValue: SavedDietsModel(services: services, day: day, onChange: onChange))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Keep each diet you follow under a name, then switch back to it from any date. Earlier days keep the diet they had.")
                    .font(.system(size: 13)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Save the diet in force on \(Format.shortDate(model.day))") {
                    nameText = ""
                    naming = .saveCurrent
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("save-current-diet")
                if model.diets.isEmpty {
                    Text("No saved diets yet.").font(.system(size: 13)).foregroundColor(Theme.muted).card()
                }
                ForEach(model.diets) { diet in row(diet) }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Saved diets")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load() }
        .errorAlert($model.errorMessage)
        .alert(naming.map(title) ?? "", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $nameText).accessibilityIdentifier("saved-diet-name-field")
            Button("Save") { submitName() }
            Button("Cancel", role: .cancel) { naming = nil }
        }
        .sheet(item: $choosingStart) { diet in startSheet(diet) }
    }

    private func title(_ request: NameRequest) -> String {
        switch request {
        case .saveCurrent: return "Name this diet"
        case .rename: return "Rename diet"
        }
    }

    private func submitName() {
        switch naming {
        case .saveCurrent: model.saveCurrent(as: nameText)
        case .rename(let diet): model.rename(diet, to: nameText)
        case nil: break
        }
        naming = nil
    }

    private func row(_ diet: SavedDiet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(diet.name).font(.system(size: 16, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                if diet.isInForce { Pill(text: "In force", tone: .green) }
            }
            Text(model.summary(diet)).font(.system(size: 12)).foregroundColor(Theme.muted)
            Text("Saved \(Format.shortDate(diet.savedOn)) · " + diet.meals.map(\.name).joined(separator: ", "))
                .font(.system(size: 12)).foregroundColor(Theme.muted)
            HStack(spacing: 8) {
                Button("Use from…") {
                    startDate = BodyDates.date(from: model.today)
                    choosingStart = diet
                }
                .accessibilityIdentifier("use-diet-\(diet.name)")
                Button("Rename") {
                    nameText = diet.name
                    naming = .rename(diet)
                }
                Button("Delete", role: .destructive) { model.delete(diet) }
                    .accessibilityIdentifier("delete-diet-\(diet.name)")
            }
            .buttonStyle(PrimaryButtonStyle(ghost: true))
            .font(.system(size: 13))
        }
        .card(highlighted: diet.isInForce)
    }

    private func startSheet(_ diet: SavedDiet) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("From this day the plan becomes \(diet.name). Days before keep the diet they had.")
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
                DatePicker("Starts on", selection: $startDate, displayedComponents: .date).tint(Theme.green)
                Button("Use \(diet.name)") {
                    model.use(diet, from: BodyDates.day(from: startDate))
                    choosingStart = nil
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("confirm-use-diet")
                Spacer()
            }
            .padding(16)
            .screenBackground()
            .navigationTitle("Use saved diet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { choosingStart = nil } } }
        }
        .presentationDetents([.medium])
    }
}
