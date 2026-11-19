import FitnessCore
import SwiftUI

/// What to ask the lab for, the prep timeline back from the draw hour, and which markers are due a retest.
struct PlanDrawView: View {
    let catalogue: LabCatalogue
    let draws: LabDrawService
    let sex: LabSex
    let genetics: GeneticsService?
    let today: ISODate
    @State private var drawDate = Date()
    @State private var drawHour = 8
    @State private var order: [OrderItem] = []
    @State private var retests: [RetestDue] = []
    @State private var errorMessage: String?

    private var planner: DrawPlanner { DrawPlanner(catalogue: catalogue, draws: draws, sex: sex, genetics: genetics) }

    private var timeline: [(date: ISODate, steps: [TimedPrepStep])] {
        let ordered = order.flatMap { $0.tests.compactMap(\.markerID) }
        var seen = Set<String>()
        let steps = planner.prepTimeline(drawDate: BodyDates.day(from: drawDate), drawHour: drawHour, ordered: ordered)
            .filter { seen.insert($0.step.text).inserted }
        var days: [(date: ISODate, steps: [TimedPrepStep])] = []
        for step in steps {
            if days.last?.date == step.date { days[days.count - 1].steps.append(step) } else { days.append((step.date, [step])) }
        }
        return days
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Draw day", selection: $drawDate, displayedComponents: .date)
                    Stepper("Draw at \(String(format: "%02d:00", drawHour))", value: $drawHour, in: 5...20)
                }
                .card()
                orderCard
                if !timeline.isEmpty { timelineCard }
                triggeredCard
                retestCard
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Plan a draw")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .errorAlert($errorMessage)
    }

    private var standing: [OrderItem] { order.filter { $0.reason == nil } }
    private var triggered: [OrderItem] { order.filter { $0.reason != nil } }

    /// Each test once, in the order the panels name them: the list to hand the lab.
    private var tests: [OrderTest] {
        var seen = Set<String>()
        return standing.flatMap(\.tests).filter { seen.insert($0.markerID ?? $0.name).inserted }
    }

    private var orderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Ask the lab for (\(tests.count) tests)")
            Text(tests.map(\.name).joined(separator: " · ")).font(.system(size: 13)).foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("By panel, with what to say") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(standing, id: \.panel.id) { panelRow($0) }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 13, weight: .semibold))
            .tint(Theme.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-order-list")
    }

    @ViewBuilder
    private var triggeredCard: some View {
        if !triggered.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Worth adding after your results (\(triggered.count))")
                Text("A marker each of these watches was outside optimal last time. Read the reason to see whether it fits.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Show them") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(triggered, id: \.panel.id) { panelRow($0) }
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 13, weight: .semibold))
                .tint(Theme.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func panelRow(_ item: OrderItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.panel.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
            if let reason = item.reason { Text("Added because: \(reason)").font(.system(size: 11)).foregroundColor(Theme.amber) }
            Text(item.tests.map(\.name).joined(separator: " · ")).font(.system(size: 13, weight: .regular)).foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let askFor = item.panel.askFor {
                Text("Ask for: \(askFor)").font(.system(size: 12, weight: .regular)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Before the draw")
            ForEach(timeline, id: \.date) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(Format.weekdayDate(day.date)).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                    ForEach(day.steps, id: \.step.id) { step in
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(format: "%02d:00", step.hour)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.muted)
                            Text(step.step.text).font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var retestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Retests")
            let due = retests.filter { $0.from != nil }
            if due.isEmpty { Text("No retest windows yet.").font(.system(size: 13)).foregroundColor(Theme.muted) }
            ForEach(due, id: \.marker.id) { item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.marker.name).font(.system(size: 13, weight: .semibold))
                        if let note = item.note ?? item.rule?.text {
                            Text(note).font(.system(size: 11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    if let from = item.from {
                        let isDue = from <= today
                        Pill(text: isDue ? "Due" : "From \(Format.longDate(from))", tone: isDue ? .amber : .grey)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func load() {
        do {
            order = try planner.order()
            retests = try planner.retests()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The vault's genetics guidance, each gene by bucket, and the genotype picked from the vault's own table (D10). APOE shows like any gene (D11).
struct GeneticsView: View {
    let catalogue: LabCatalogue
    let services: Services
    @State private var entries: [GenotypeEntry] = []
    @State private var errorMessage: String?

    /// The vault sorts every gene into form, read, priority or nothing; doctor genes come first.
    private static let bucketTitles = [("doctor", "Take to a doctor"), ("take", "Changes the form you take"),
                                       ("read", "Changes how a result is read"), ("priority", "Changes what to check first"),
                                       ("nothing", "Changes nothing")]

    private var buckets: [(id: String, title: String)] {
        let known = Self.bucketTitles.map(\.0)
        let extra = catalogue.genes.map(\.bucket).filter { !known.contains($0) }
        return (Self.bucketTitles + Array(Set(extra)).sorted().map { ($0, $0.capitalized) })
            .filter { bucket in catalogue.genes.contains { $0.bucket == bucket.0 } }.map { (id: $0.0, title: $0.1) }
    }

    var body: some View {
        List {
            ForEach(buckets, id: \.id) { bucket in
                Section(bucket.title) {
                    ForEach(catalogue.genes.filter { $0.bucket == bucket.id }) { gene in
                        NavigationLink { GeneDetailView(gene: gene, service: services.genetics, entry: entry(gene), changed: load) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(gene.name)
                                    if let variant = gene.variant { Text(variant).font(.system(size: 11)).foregroundColor(Theme.muted) }
                                }
                                Spacer()
                                if let entry = entry(gene) { Pill(text: entry.row.genotype, tone: .green) }
                            }
                        }
                    }
                }
            }
            if !catalogue.geneticsGuide.isEmpty {
                Section {
                    DisclosureGroup("How to use genetics (\(catalogue.geneticsGuide.count) notes)") {
                        ForEach(Array(catalogue.geneticsGuide.enumerated()), id: \.offset) { _, item in
                            Text(item.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.green)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Genetics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .errorAlert($errorMessage)
    }

    private func entry(_ gene: LabGene) -> GenotypeEntry? { entries.first { $0.gene.id == gene.id } }

    private func load() {
        do {
            entries = try services.genetics?.entries() ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GeneDetailView: View {
    let gene: LabGene
    let service: GeneticsService?
    let entry: GenotypeEntry?
    let changed: () -> Void
    @EnvironmentObject private var services: Services
    @State private var picked: String?
    @State private var errorMessage: String?

    private var row: LabGenotype? { gene.genotypes?.first { $0.genotype == picked } }

    var body: some View {
        List {
            if let genotypes = gene.genotypes, !genotypes.isEmpty {
                Section("Your genotype") {
                    Picker("Genotype", selection: $picked) {
                        Text("Not known").tag(String?.none)
                        ForEach(genotypes, id: \.genotype) { Text($0.genotype).tag(String?.some($0.genotype)) }
                    }
                    .accessibilityIdentifier("labs-genotype-picker")
                }
            } else {
                Section { Text("The vault gives no genotype table for this gene.").foregroundColor(Theme.muted) }
            }
            if let row {
                Section("What it means") {
                    if let meaning = row.meaning { Text(meaning).fixedSize(horizontal: false, vertical: true) }
                    if let urgency = row.urgency { Text("Urgency: \(urgency.title)").foregroundColor(Theme.amber) }
                    ForEach(row.actions ?? [], id: \.self) { Text("• \($0)").fixedSize(horizontal: false, vertical: true) }
                    if let adds = row.addsMarkers, !adds.isEmpty { Text("Adds to your draw: \(adds.joined(separator: ", "))").font(.system(size: 13)) }
                }
            }
            if row == nil, let genotypes = gene.genotypes, !genotypes.isEmpty {
                Section("The vault's table") {
                    ForEach(genotypes, id: \.genotype) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.genotype).font(.system(size: 14, weight: .semibold))
                            if let meaning = item.meaning { Text(meaning).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
                        }
                    }
                }
            }
            if let confirm = gene.confirmWith, !confirm.isEmpty {
                Section("Confirm with bloodwork") { ForEach(confirm, id: \.self) { Text($0) } }
            }
            if let source = gene.source { Section { Text("Source: \(source)").font(.system(size: 11)).foregroundColor(Theme.muted) } }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(gene.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { picked = entry?.row.genotype }
        .onChange(of: picked) { save($0) }
        .errorAlert($errorMessage)
    }

    private func save(_ genotype: String?) {
        guard genotype != entry?.row.genotype || genotype == nil else { return }
        do {
            if let genotype { try service?.set(gene.id, genotype: genotype, on: services.clock.today()) } else { try service?.clear(gene.id) }
            changed()
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }
}
