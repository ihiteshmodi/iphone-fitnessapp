import FitnessCore
import SwiftUI

/// What the Add extra sheet would add, shown before saving.
struct ExtraPreview {
    let amountText: String
    let nutrition: Nutrition
}

@MainActor
final class AddExtraModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [Food] = []
    @Published private(set) var selected: Food?
    @Published var mode = PortionMode.amount
    @Published var valueText = ""

    let date: ISODate
    private let services: Services

    init(services: Services, date: ISODate) {
        self.services = services
        self.date = date
    }

    func search() {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard selected == nil || text != selected?.name else { return }
        results = text.isEmpty ? [] : Array(((try? services.foods.foods(matching: text)) ?? []).prefix(8))
    }

    func select(_ food: Food) {
        selected = food
        query = food.name
        results = []
        let first = Portions.modes(for: food).first ?? .amount
        mode = first
        valueText = Format.number(Portions.defaultValue(first, for: food))
    }

    func select(_ recent: RecentExtra) {
        guard let food = try? services.foods.food(recent.foodID) else { return }
        select(food)
        if let pieces = recent.pieces, modes.contains(.pieces) {
            mode = .pieces
            valueText = Format.number(pieces, maxDecimals: 1)
        } else {
            mode = modes.contains(.amount) ? .amount : (modes.first ?? .amount)
            valueText = Format.number(recent.amount, maxDecimals: 1)
        }
    }

    func clearSelection() {
        selected = nil
        query = ""
        results = []
    }

    var modes: [PortionMode] { selected.map(Portions.modes(for:)) ?? [] }

    func title(of mode: PortionMode) -> String {
        switch mode {
        case .pieces: return "Pieces"
        case .shareOfPack: return "Share of pack"
        case .amount:
            guard let unit = selected?.unit else { return "Amount" }
            switch unit {
            case "g": return "Grams"
            case "ml": return "Millilitres"
            default: return unit.prefix(1).uppercased() + unit.dropFirst() + "s"
            }
        }
    }

    func choose(_ newMode: PortionMode) {
        guard let selected, newMode != mode else { return }
        mode = newMode
        valueText = Format.number(Portions.defaultValue(newMode, for: selected))
    }

    func step(_ direction: Double) {
        guard let selected else { return }
        let current = Format.decimal(valueText) ?? 0
        let next = max(Portions.step(mode, for: selected), current + direction * Portions.step(mode, for: selected))
        valueText = Format.number(next, maxDecimals: 2)
    }

    var inputLabel: String {
        switch mode {
        case .pieces: return "How many pieces"
        case .shareOfPack: return "How much of the pack"
        case .amount: return "How much"
        }
    }

    var hint: String? {
        guard let selected else { return nil }
        switch mode {
        case .pieces:
            guard let weight = Portions.pieceWeight(of: selected) else { return nil }
            return "1 piece = \(Format.number(weight, maxDecimals: 2)) \(selected.unit) · tap the number to type"
        case .shareOfPack: return "1 = the whole pack · tap the number to type"
        case .amount: return "tap the number to type"
        }
    }

    var preview: ExtraPreview? {
        guard let selected, let value = Format.decimal(valueText),
              let portion = try? Portions.portion(of: selected, Portions.input(mode, value)),
              let nutrition = try? services.foods.nutrition(of: selected.id, quantity: portion.amount) else { return nil }
        var parts: [String] = []
        if mode == .pieces { parts.append("\(Format.number(value, maxDecimals: 1)) pieces") }
        parts.append(Format.amount(portion.amount.rounded(toPlaces: 1), unit: selected.unit))
        let base = selected.draft.baseQuantity
        let label = selected.isRecipe || base == 1 ? "" : ", label is per \(Format.number(base)) \(selected.unit)"
        return ExtraPreview(amountText: parts.joined(separator: " = ") + label, nutrition: nutrition)
    }

    func save() throws {
        guard let selected else { throw ValidationError("Choose a food first") }
        guard let value = Format.decimal(valueText) else { throw ValidationError("Enter the amount as a number") }
        try services.dietDays.addExtra(foodID: selected.id, Portions.input(mode, value), on: date)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}

/// The sheet from the mockups: pick a food (or a recent one), say how much, see the result, add it to the day.
struct DietAddExtraSheet: View {
    @EnvironmentObject private var services: Services
    @StateObject private var model: AddExtraModel
    let recent: [RecentExtra]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var creatingFood = false

    init(services: Services, date: ISODate, recent: [RecentExtra], onSaved: @escaping () -> Void) {
        _model = StateObject(wrappedValue: AddExtraModel(services: services, date: date))
        self.recent = recent
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("for \(Format.weekdayDate(model.date))").font(.system(size: 12)).foregroundColor(Theme.muted)
                    if model.selected == nil && !recent.isEmpty { recentChips }
                    searchField
                    if model.selected == nil { resultsList }
                    if let food = model.selected { selectedSection(food) }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("Add extra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .errorAlert($errorMessage)
            .sheet(isPresented: $creatingFood) {
                DietFoodFormSheet(services: services, food: nil, suggestedName: model.query) { id in
                    if let food = try? services.foods.food(id) { model.select(food) }
                }
            }
        }
    }

    private var recentChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(recent, id: \.foodID) { item in
                    Button(chipText(item)) { model.select(item) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.green)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Theme.green.opacity(0.14))
                        .clipShape(Capsule())
                        .accessibilityIdentifier("recent-extra-\(item.name)")
                }
            }
        }
    }

    private func chipText(_ item: RecentExtra) -> String {
        "\(item.name) · \(Format.number(item.pieces ?? item.amount, maxDecimals: 1))"
    }

    private var searchField: some View {
        HStack {
            TextField("Search foods", text: $model.query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundColor(Theme.text)
                .accessibilityIdentifier("extra-search-field")
                .onChange(of: model.query) { _ in model.search() }
            if model.selected != nil {
                Button { model.clearSelection() } label: { Image(systemName: "xmark.circle.fill").foregroundColor(Theme.muted) }
                    .accessibilityIdentifier("extra-clear-food")
            }
        }
        .padding(12)
        .background(Theme.card)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(model.results) { food in
                Button { model.select(food) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Text(DietFoodText.summary(food)).font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("extra-result-\(food.name)")
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
            Button("+ New food") { creatingFood = true }
                .font(.system(size: 14, weight: .semibold))
                .padding(.vertical, 10)
                .accessibilityIdentifier("extra-new-food")
        }
        .card(padding: 12)
    }

    @ViewBuilder
    private func selectedSection(_ food: Food) -> some View {
        if model.modes.count > 1 {
            HStack(spacing: 4) {
                ForEach(model.modes, id: \.self) { mode in
                    Button(model.title(of: mode)) { model.choose(mode) }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(model.mode == mode ? Theme.onGreen : Theme.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(model.mode == mode ? Theme.green : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityIdentifier("extra-mode-\(model.title(of: mode))")
                }
            }
            .padding(4)
            .background(Theme.card)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        stepper
        if let preview = model.preview { previewCard(preview) }
        Button("Add to \(model.date == services.clock.today() ? "today" : Format.shortDate(model.date))", action: save)
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("extra-add-button")
    }

    private var stepper: some View {
        VStack(spacing: 8) {
            SectionLabel(model.inputLabel)
            HStack {
                stepButton("−", id: "extra-minus") { model.step(-1) }
                Spacer()
                TextField("", text: $model.valueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundColor(Theme.text)
                    .accessibilityIdentifier("extra-amount-field")
                Spacer()
                stepButton("+", id: "extra-plus") { model.step(1) }
            }
            if let hint = model.hint { Text(hint).font(.system(size: 11)).foregroundColor(Theme.muted) }
        }
        .padding(12)
        .background(Theme.card2)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stepButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(symbol).font(.system(size: 24, weight: .bold)).foregroundColor(Theme.green)
                .frame(width: 46, height: 46)
                .background(Color(hex: 0x202824))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityIdentifier(id)
    }

    private func previewCard(_ preview: ExtraPreview) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(preview.amountText).font(.system(size: 11)).foregroundColor(Theme.muted)
            Text("\(Format.grouped(preview.nutrition.calories)) kcal").font(.system(size: 24, weight: .heavy)).foregroundColor(Theme.text)
                .accessibilityIdentifier("extra-preview-calories")
            HStack(spacing: 8) {
                macro(Format.number(preview.nutrition.protein, maxDecimals: 1), "protein")
                macro(Format.number(preview.nutrition.carbs, maxDecimals: 1), "carbs")
                macro(Format.number(preview.nutrition.fat, maxDecimals: 1), "fat")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.green.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.green.opacity(0.3)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func macro(_ value: String, _ name: String) -> some View {
        VStack(spacing: 1) {
            Text("\(value) g").font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
            Text(name).font(.system(size: 11)).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func save() {
        do {
            try model.save()
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Words for a food, shared by the lists.
enum DietFoodText {
    /// "per 100 g · P 12 · C 68 · F 8" or "250 g pack · 35 pieces"
    static func summary(_ food: Food) -> String {
        let d = food.draft
        if food.isRecipe { return "per 1 \(food.unit)" }
        var parts = ["per \(Format.number(d.baseQuantity)) \(d.unit)"]
        if d.protein + d.carbs + d.fat > 0 {
            parts.append("P \(Format.number(d.protein, maxDecimals: 1)) · C \(Format.number(d.carbs, maxDecimals: 1)) · F \(Format.number(d.fat, maxDecimals: 1))")
        }
        if let pack = d.packSize, let pieces = d.piecesPerPack { parts.append("\(Format.number(pieces)) pieces in \(Format.number(pack)) \(d.unit)") }
        return parts.joined(separator: " · ")
    }
}
