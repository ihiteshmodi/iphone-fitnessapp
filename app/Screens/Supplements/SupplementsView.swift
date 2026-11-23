import FitnessCore
import SwiftUI

/// Your supplements against the vault's library, the whole library to search before buying, and a multivitamin stack optimizer.
struct SupplementsView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var query = ""
    @State private var verdict: SupplementVerdict?
    @State private var mine: [Food] = []
    @State private var addingMultivitamin = false

    private var library: SupplementLibrary? { services.supplementLibrary }
    private var multivitamins: [Food] { mine.filter(isMultivitamin) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if library == nil {
                    Text("The supplement library file is not in this build. Create output/supplement-library.json and rebuild.")
                        .font(.system(size: 13)).foregroundColor(Theme.muted).card()
                }
                multivitaminStackCard
                if !mine.isEmpty { mySupplements }
                if let library { librarySection(library) }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Supplements")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) { loadMine() }
        .sheet(isPresented: $addingMultivitamin) {
            DietFoodFormSheet(services: services, food: nil, defaultKind: .supplement, defaultUnit: "unit") { _ in
                loadMine()
            }
        }
    }

    private func loadMine() {
        mine = ((try? services.foods.foods(matching: "", kind: .supplement)) ?? [])
    }

    private var multivitaminStackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Multivitamin stack & optimizer")
                Spacer()
                Button("+ Add multivitamin") { addingMultivitamin = true }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .accessibilityIdentifier("add-multivitamin-button")
            }
            Text("Compare every vitamin & mineral with 0 / target for gaps, combine multiple multivitamins (Becadexamine, A to Z, Supradyn), and auto-pick the safest high-coverage stack.")
                .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let primary = multivitamins.first {
                NavigationLink {
                    MultivitaminWhatIfView(food: primary)
                } label: {
                    HStack {
                        Text("Open stack builder (\(multivitamins.count) multivitamin\(multivitamins.count == 1 ? "" : "s"))")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.onGreen)
                        Spacer()
                        Image(systemName: "sparkles").foregroundColor(Theme.onGreen)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.green)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-multivitamin-stack")
            }
        }
        .card()
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

    private func isMultivitamin(_ food: Food) -> Bool { MultivitaminWhatIf.isMultivitamin(food.draft) }

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
    @EnvironmentObject private var services: Services

    /// Each test with the owner's latest result when the labs catalogue is bundled.
    private var testFirst: String? {
        guard !entry.testFirst.isEmpty else { return nil }
        guard let catalogue = services.labCatalogue, let sex = try? services.labSettings.load().sex else { return entry.testFirst.joined(separator: ", ") }
        let lookup = LabTestLookup(catalogue: catalogue, draws: LabDrawService(services.db, catalogue: catalogue), sex: sex)
        return entry.testFirst.map { (try? lookup.summary(of: $0)) ?? $0 }.joined(separator: "\n")
    }

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
                field("Test first", testFirst)
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

/// Multi-multivitamin stack builder & optimizer: combines 0...3 units across all multivitamins, shows 0 / target for absent nutrients, and finds the highest-coverage safe stack.
struct MultivitaminWhatIfView: View {
    let food: Food
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var options: [MultivitaminOption] = []
    @State private var counts: [Int: Int] = [:]
    @State private var mode: MultivitaminBaselineMode = .tabletsOnly
    @State private var excludeOverULPills = false
    @State private var rest = NutrientProfile.empty
    @State private var suggestionNote: String?
    @State private var addingMultivitamin = false

    private var rows: [MultivitaminWhatIf.Row] {
        MultivitaminWhatIf.stackRows(options: options, counts: counts, mode: mode, foodRest: rest)
    }

    private var coveredCount: Int {
        rows.filter { ($0.target ?? 0) > 0 && $0.amount + 1e-6 >= ($0.target ?? 0) }.count
    }

    private var totalTargetCount: Int {
        rows.filter { $0.target != nil }.count
    }

    private var breachedRows: [MultivitaminWhatIf.Row] {
        rows.filter(\.isOverLimit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerControls
                stackSelectorCard
                summaryBanner
                ForEach([NutrientGroup.vitamins, .minerals], id: \.self) { group in
                    let groupRows = rows.filter { $0.nutrient.group == group }
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(group.rawValue).padding(.bottom, 4)
                        ForEach(groupRows, id: \.nutrient) { rowView($0) }
                    }
                    .card()
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Multivitamin stack")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.revision) { reload() }
        .sheet(isPresented: $addingMultivitamin) {
            DietFoodFormSheet(services: services, food: nil, defaultKind: .supplement, defaultUnit: "unit") { newID in
                reload()
                counts[newID] = 1
            }
        }
    }

    private var headerControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .tabletsOnly
                 ? "Comparing multivitamin tablets alone against daily targets and upper limits. Missing nutrients show 0 / target."
                 : "Stack combined with today's eaten non-multivitamin food. Nothing here is logged.")
                .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Picker("Baseline", selection: $mode) {
                ForEach(MultivitaminBaselineMode.allCases, id: \.self) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("whatif-mode-picker")
        }
    }

    private var stackSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("Combine multivitamins")
                Spacer()
                Button("+ Add multivitamin") { addingMultivitamin = true }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .accessibilityIdentifier("stack-add-multivitamin")
            }
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                    Picker(option.name, selection: Binding(
                        get: { counts[option.id] ?? 0 },
                        set: { value in
                            suggestionNote = nil
                            if value == 0 { counts.removeValue(forKey: option.id) } else { counts[option.id] = value }
                        }
                    )) {
                        Text("0").tag(0)
                        Text("1 tablet").tag(1)
                        Text("2 tablets").tag(2)
                        Text("3 tablets").tag(3)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(index == 0 ? "whatif-tablets" : "whatif-tablets-\(option.name)")
                }
            }
            Toggle(isOn: $excludeOverULPills) {
                Text("Exclude single pills that exceed an Upper Limit")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            .tint(Theme.green)
            .accessibilityIdentifier("exclude-over-ul-toggle")

            Button(action: applyBestStack) {
                HStack {
                    Image(systemName: "sparkles")
                    Text("Suggest Best Stack")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityIdentifier("suggest-best-stack-button")

            if let suggestionNote {
                Text(suggestionNote)
                    .font(.system(size: 12))
                    .foregroundColor(breachedRows.isEmpty ? Theme.green : Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stack-suggestion-note")
            }
        }
        .card()
    }

    private var summaryBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(coveredCount) / \(totalTargetCount) daily targets hit")
                    .font(.system(size: 15, weight: .bold)).foregroundColor(Theme.text)
                Spacer()
                Pill(text: breachedRows.isEmpty ? "Within ULs" : "\(breachedRows.count) over UL",
                     tone: breachedRows.isEmpty ? .green : .red)
            }
            if !breachedRows.isEmpty {
                let names = breachedRows.map { "\($0.nutrient.title) (\(Format.number($0.amount, maxDecimals: 1)) > \(Format.number($0.upperLimit ?? 0, maxDecimals: 0)) \($0.nutrient.unit))" }
                Text("Upper Limit exceeded: \(names.joined(separator: ", ")).")
                    .font(.system(size: 12)).foregroundColor(Theme.red).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("stack-ul-warning")
            }
        }
        .card()
    }

    private func rowView(_ row: MultivitaminWhatIf.Row) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.nutrient.title).font(.system(size: 13)).foregroundColor(Theme.text)
                if row.isFatSoluble { Pill(text: "fat-soluble", tone: .gold) }
                Spacer()
                if let target = row.target {
                    Text(DailyTargetRow(nutrient: row.nutrient, amount: row.amount, target: target).formattedProgress)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(row.isOverLimit ? Theme.red : (row.amount >= target ? Theme.green : (row.amount == 0 ? Theme.muted : Theme.text)))
                    Text("\(Format.number(row.amount / target * 100, maxDecimals: 0))%")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                        .frame(minWidth: 34, alignment: .trailing)
                } else {
                    Text("\(Format.number(row.amount, maxDecimals: 1)) \(row.nutrient.unit)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(row.isOverLimit ? Theme.red : (row.amount == 0 ? Theme.muted : Theme.text))
                }
            }
            if let target = row.target, target > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(row.isOverLimit ? Theme.red : (row.amount >= target ? Theme.green : Theme.amber))
                            .frame(width: proxy.size.width * min(max(row.amount / target, 0), 1))
                    }
                }
                .frame(height: 4)
            }
            if row.isOverLimit || row.nutrient.upperLimitNote != nil {
                Text(row.isOverLimit
                     ? "Over the vault's upper limit of \(Format.number(row.upperLimit ?? 0)) \(row.nutrient.unit)\(row.isFatSoluble ? "; fat-soluble, so it builds up in the body" : "")."
                     : "Upper limit: \(row.nutrient.upperLimitNote ?? "")")
                    .font(.system(size: 11)).foregroundColor(row.isOverLimit ? Theme.red : Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("mvi-row-\(row.nutrient.rawValue)")
    }

    private func reload() {
        let allSupplements = ((try? services.foods.foods(matching: "", kind: .supplement)) ?? [])
        var mviFoods = allSupplements.filter { MultivitaminWhatIf.isMultivitamin($0.draft) }
        if !mviFoods.contains(where: { $0.id == food.id }) {
            mviFoods.insert(food, at: 0)
        }
        options = mviFoods.map(MultivitaminOption.init(food:))
        if counts.isEmpty {
            counts = [food.id: 1]
        }
        let mviIDs = Set(options.map(\.id))
        if let day = try? services.dietDays.day(services.clock.today()) {
            let mviEaten = day.meals.flatMap(\.lines)
                .filter { $0.state == .eaten && mviIDs.contains($0.foodID) }
                .reduce(NutrientProfile.empty) { $0 + $1.profile }
            rest = NutrientProfile(values: day.eatenProfile.values.merging(mviEaten.values.mapValues { -$0 }, uniquingKeysWith: +)
                .mapValues { max($0, 0) }, unknown: [])
        }
    }

    private func applyBestStack() {
        let suggestion = MultivitaminWhatIf.suggestBestStack(
            options: options,
            mode: mode,
            foodRest: rest,
            excludeOverULPills: excludeOverULPills
        )
        counts = suggestion.counts
        if suggestion.counts.isEmpty {
            suggestionNote = "No safe tablet combination found without exceeding an Upper Limit. Add a lower-dose multivitamin (e.g. A to Z or Supradyn) to optimize."
        } else if suggestion.hasUnavoidableULBreach {
            let breached = suggestion.breachedNutrients.map(\.title).joined(separator: ", ")
            suggestionNote = "Every multivitamin currently in your library exceeds an Upper Limit at 1 unit (\(breached)). Capped at 1 unit so fat-soluble vitamins stay safe — add A to Z or Supradyn to find a zero-breach combination."
        } else {
            let chosen = options.compactMap { opt -> String? in
                guard let c = suggestion.counts[opt.id], c > 0 else { return nil }
                return "\(c)× \(opt.name)"
            }.joined(separator: " + ")
            suggestionNote = "Recommended: \(chosen) — \(suggestion.coveredTargetsCount)/\(suggestion.totalTargetsCount) targets met (\(Format.number(suggestion.averageCoveragePercent, maxDecimals: 0))% avg coverage) with zero Upper Limit breaches."
        }
    }
}
