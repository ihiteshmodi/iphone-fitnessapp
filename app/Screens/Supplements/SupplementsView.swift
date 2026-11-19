import FitnessCore
import SwiftUI

/// Your supplements against the vault's library, the whole library to search before buying, and a multivitamin what-if.
struct SupplementsView: View {
    @EnvironmentObject private var services: Services
    @State private var query = ""
    @State private var verdict: SupplementVerdict?
    @State private var mine: [Food] = []

    private var library: SupplementLibrary? { services.supplementLibrary }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if library == nil {
                    Text("The supplement library file is not in this build. Create output/supplement-library.json and rebuild.")
                        .font(.system(size: 13)).foregroundColor(Theme.muted).card()
                }
                if !mine.isEmpty { mySupplements }
                if let library { librarySection(library) }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { mine = ((try? services.foods.foods(matching: "", kind: .supplement)) ?? []) }
    }

    private var mySupplements: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Your supplements").padding(.bottom, 4)
            ForEach(mine) { food in
                let entry = library?.match(food.name)
                NavigationLink {
                    if isMultivitamin(food) { MultivitaminWhatIfView(food: food) } else if let entry { SupplementDetailView(entry: entry) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(food.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                            Text(entry.map { "\($0.name) · \($0.verdict.title)" } ?? (isMultivitamin(food) ? "Multivitamin · what if" : "Not in the library"))
                                .font(.system(size: 12)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        if let entry { verdictPill(entry.verdict) }
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(entry == nil && !isMultivitamin(food))
                .accessibilityIdentifier("my-supplement-\(food.name)")
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
            }
        }
        .card()
    }

    private func isMultivitamin(_ food: Food) -> Bool {
        food.draft.nutrients.keys.filter { $0.group == .vitamins || $0.group == .minerals }.count >= 3
    }

    private func librarySection(_ library: SupplementLibrary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Library · \(library.entries.count) supplements")
            TextField("Search before you buy (name or alias)", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(Theme.card)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line)).clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityIdentifier("supplement-search")
            Picker("Verdict", selection: $verdict) {
                Text("All").tag(SupplementVerdict?.none)
                Text("Worth taking").tag(SupplementVerdict?.some(.recommended))
                Text("Conditional").tag(SupplementVerdict?.some(.conditional))
                Text("Not rec.").tag(SupplementVerdict?.some(.notRecommended))
            }
            .pickerStyle(.segmented)
            ForEach(library.search(query, verdict: verdict)) { entry in
                NavigationLink { SupplementDetailView(entry: entry) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                            Text(entry.verdictText ?? entry.category).font(.system(size: 12)).foregroundColor(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        verdictPill(entry.verdict)
                    }
                    .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("supplement-\(entry.id)")
            }
        }
    }

    private func verdictPill(_ verdict: SupplementVerdict) -> some View {
        Pill(text: verdict.title, tone: verdict == .recommended ? .green : (verdict == .conditional ? .amber : .red))
    }
}

struct SupplementDetailView: View {
    let entry: SupplementEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(entry.name).font(.system(size: 22, weight: .bold)).foregroundColor(Theme.text)
                    Spacer()
                    Pill(text: entry.verdict.title, tone: entry.verdict == .recommended ? .green : (entry.verdict == .conditional ? .amber : .red))
                }
                if let text = entry.verdictText { Text("“\(text)”").font(.system(size: 13)).italic().foregroundColor(Theme.muted) }
                field("Why", entry.why)
                field("Dose", entry.doseText)
                field("Upper limit", entry.upperLimit.map { "\(SupplementCheckRule.number($0)) \(entry.upperLimitUnit ?? "")" })
                field("Forms", entry.forms)
                field("Timing", entry.timing)
                field("Cycling", entry.cycling)
                field("Test first", entry.testFirst.isEmpty ? nil : entry.testFirst.joined(separator: ", "))
                field("Interactions", entry.interactions)
                field("Side effects", entry.sideEffects)
                field("Unresolved · revisit in Labs", entry.contradictions)
                Text("\(entry.category) · \(entry.source)").font(.system(size: 11)).foregroundColor(Theme.muted)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func field(_ title: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                SectionLabel(title)
                Text(text).font(.system(size: 14)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }
}

/// Read-only: 1, 2 or 3 tablets on top of today's food, against daily targets and upper limits.
struct MultivitaminWhatIfView: View {
    let food: Food
    @EnvironmentObject private var services: Services
    @State private var tablets = 1
    @State private var rest = NutrientProfile.empty

    private var perTablet: NutrientProfile {
        NutrientProfile(values: food.draft.nutrients.mapValues { $0 / food.draft.baseQuantity }, unknown: [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(food.name) on top of today's food. Nothing is logged.").font(.system(size: 13)).foregroundColor(Theme.muted)
                Picker("Tablets", selection: $tablets) {
                    ForEach(1...3, id: \.self) { Text("\($0) tablet\($0 == 1 ? "" : "s")").tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("whatif-tablets")
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MultivitaminWhatIf.rows(perTablet: perTablet, tablets: tablets, rest: rest), id: \.nutrient) { row in
                        HStack(spacing: 6) {
                            Text(row.nutrient.title).font(.system(size: 13)).foregroundColor(Theme.text)
                            if row.isFatSoluble { Pill(text: "fat-soluble", tone: .gold) }
                            Spacer()
                            Text("\(Format.number(row.amount, maxDecimals: 1)) \(row.nutrient.unit)").font(.system(size: 13, weight: .semibold))
                                .foregroundColor(row.isOverLimit ? Theme.red : Theme.text)
                            if let target = row.target {
                                Text("\(Format.number(row.amount / target * 100, maxDecimals: 0))%").font(.system(size: 11)).foregroundColor(Theme.muted)
                            }
                        }
                        .padding(.vertical, 6)
                        if row.isOverLimit || row.nutrient.upperLimitNote != nil {
                            Text(row.isOverLimit ? "Over the vault's upper limit of \(Format.number(row.upperLimit ?? 0)) \(row.nutrient.unit)\(row.isFatSoluble ? "; fat-soluble, so it builds up in the body" : "")."
                                 : "Upper limit: \(row.nutrient.upperLimitNote ?? "")")
                                .font(.system(size: 11)).foregroundColor(row.isOverLimit ? Theme.red : Theme.muted)
                        }
                    }
                }
                .card()
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("What if")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let day = try? services.dietDays.day(services.clock.today()) else { return }
            let own = day.meals.flatMap(\.lines).filter { $0.state == .eaten && $0.foodID == food.id }.reduce(NutrientProfile.empty) { $0 + $1.profile }
            rest = NutrientProfile(values: day.eatenProfile.values.merging(own.values.mapValues { -$0 }, uniquingKeysWith: +), unknown: [])
        }
    }
}
