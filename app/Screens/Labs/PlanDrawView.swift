import FitnessCore
import SwiftUI

/// What to ask the lab for, the prep timeline back from the draw hour, and which markers are due a retest.
struct PlanDrawView: View {
    let catalogue: LabCatalogue
    let draws: LabDrawService
    let sex: LabSex
    let genetics: GeneticsService?
    var showDrugNotes = false
    let today: ISODate
    @EnvironmentObject private var services: Services
    @State private var drawDate = Date()
    @State private var drawHour = 8
    @State private var order: [OrderItem] = []
    @State private var upgrades: [OrderTest] = []
    @State private var conditionalGenes: [LabReverseGeneticRecommendation] = []
    @State private var doNotBuyGenes: [(geneName: String, directPhenotype: String)] = []
    @State private var checklist: LabDrawChecklist?
    @State private var checkedSteps: Set<String> = []
    @State private var retests: [RetestDue] = []
    @State private var coreSummary: CoreBloodworkSummary?
    @State private var errorMessage: String?

    private var planner: DrawPlanner {
        DrawPlanner(catalogue: catalogue, draws: draws, sex: sex, genetics: genetics, showDrugNotes: showDrugNotes)
    }

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
                HowBloodworkWorksCard()
                if let coreSummary {
                    CoreBloodworkPendingCard(summary: coreSummary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Draw day", selection: $drawDate, displayedComponents: .date)
                    Stepper("Draw at \(String(format: "%02d:00", drawHour))", value: $drawHour, in: 5...20)
                }
                .card()
                orderCard
                if !conditionalGenes.isEmpty { conditionalGeneticsCard }
                if !upgrades.isEmpty { upgradesCard }
                if !doNotBuyGenes.isEmpty { doNotBuyGeneticsCard }
                if let checklist { checklistCard(checklist) }
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
    private var corePanels: [OrderItem] { standing.filter { $0.panel.when == "first" } }
    private var routinePanels: [OrderItem] { standing.filter { $0.panel.when != "first" } }
    private var triggered: [OrderItem] { order.filter { $0.reason != nil } }

    /// Each test once, in the order the panels name them: the list to hand the lab.
    private var tests: [OrderTest] {
        var seen = Set<String>()
        return standing.flatMap(\.tests).filter { seen.insert($0.markerID ?? $0.name).inserted }
    }

    private var coreTestsList: [OrderTest] {
        var seen = Set<String>()
        var base = corePanels.flatMap(\.tests).filter { seen.insert($0.markerID ?? $0.name).inserted }
        for extraID in ["lpa", "homocysteine"] {
            if let marker = catalogue.marker(extraID), marker.applies(to: sex), seen.insert(marker.id).inserted {
                base.append(OrderTest(name: marker.name, markerID: marker.id))
            }
        }
        return base
    }

    private var routineExtraTests: [OrderTest] {
        let coreSet = Set(coreTestsList.map { $0.markerID ?? $0.name })
        var seen = coreSet
        return routinePanels.flatMap(\.tests).filter { seen.insert($0.markerID ?? $0.name).inserted }
    }

    private var orderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel("★ Core baseline order (\(coreTestsList.count) markers)")
                Spacer()
                Pill(text: "★ Start here", tone: .gold)
            }
            Text("Hand your lab the pending ★ Core Tests above first — you only need the full \(coreTestsList.count)-marker baseline on your first complete checkup or annual reset.")
                .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Text(coreTestsList.map(\.name).joined(separator: " · ")).font(.system(size: 13)).foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Core panels, with what to say") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(corePanels, id: \.panel.id) { panelRow($0) }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 13, weight: .semibold))
            .tint(Theme.green)

            if !routineExtraTests.isEmpty {
                Divider().overlay(Theme.line)
                DisclosureGroup("Optional deeper & routine panels (+\(routineExtraTests.count) markers)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(routineExtraTests.map(\.name).joined(separator: " · "))
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        ForEach(routinePanels, id: \.panel.id) { panelRow($0) }
                    }
                    .padding(.top, 6)
                }
                .font(.system(size: 13, weight: .semibold))
                .tint(Theme.green)
            }
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
        let notedTests = item.tests.filter { ($0.drawNote?.isEmpty == false) }
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.panel.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
            if let reason = item.reason { Text("Added because: \(reason)").font(.system(size: 11)).foregroundColor(Theme.amber) }
            Text(item.tests.map(\.name).joined(separator: " · ")).font(.system(size: 13, weight: .regular)).foregroundColor(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            if let askFor = item.panel.askFor {
                Text("Ask for: \(askFor)").font(.system(size: 12, weight: .regular)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !notedTests.isEmpty {
                DisclosureGroup("Draw & assay notes (\(notedTests.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(notedTests, id: \.name) { test in
                            Text("• \(test.name): \(test.drawNote ?? "")")
                                .font(.system(size: 11)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 12, weight: .semibold)).tint(Theme.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var conditionalGeneticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Conditional genetic tests warranted (\(conditionalGenes.count))")
                Spacer()
                Pill(text: "Reverse trigger", tone: .amber)
            }
            ForEach(conditionalGenes) { rec in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(rec.geneName).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Spacer()
                        if rec.requiresClinicalGradeAssay {
                            Pill(text: "Clinical-grade lab", tone: .red)
                        }
                    }
                    Text(rec.triggerSummary).font(.system(size: 12, weight: .medium)).foregroundColor(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(rec.rationale).font(.system(size: 12)).foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let guardrail = rec.guardrailWarning {
                        Text("⚠️ \(guardrail)").font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let clinical = rec.clinicalGradeWarning {
                        Text("🏥 \(clinical)").font(.system(size: 11)).foregroundColor(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-plan-conditional-genetics")
    }

    private var doNotBuyGeneticsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Genetic tests NOT to buy (07.04)")
            DisclosureGroup("Skip consumer SNP panels — test phenotype directly (\(doNotBuyGenes.count))") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(doNotBuyGenes, id: \.geneName) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(item.geneName).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                                Spacer()
                                Pill(text: "Do Not Buy", tone: .red)
                            }
                            Text(item.directPhenotype).font(.system(size: 12)).foregroundColor(Theme.green)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 13, weight: .semibold)).tint(Theme.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-plan-do-not-buy-genetics")
    }

    private var upgradesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Optional Tier 2 & 3 upgrades (\(upgrades.count))")
            DisclosureGroup("Show symptom & context add-ons") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(upgrades, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            if let note = item.drawNote {
                                Text(note).font(.system(size: 12)).foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 13, weight: .semibold)).tint(Theme.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func checklistCard(_ cl: LabDrawChecklist) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Draw-day checklist")
            checklistGroup("Night before", cl.nightBefore)
            checklistGroup("Morning of draw", cl.morningOf)
            checklistGroup("Right after draw", cl.postDraw)
            checklistGroup("What to record", cl.loggingProtocol)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func checklistGroup(_ title: String, _ items: [String]) -> some View {
        if !items.isEmpty {
            DisclosureGroup(title) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items, id: \.self) { line in
                        let ticked = checkedSteps.contains(line)
                        Button {
                            if ticked { checkedSteps.remove(line) } else { checkedSteps.insert(line) }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: ticked ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(ticked ? Theme.green : Theme.muted)
                                Text(line).font(.system(size: 12)).foregroundColor(Theme.text)
                                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
            .font(.system(size: 13, weight: .semibold)).tint(Theme.green)
        }
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
                let isCore = CoreBloodworkGuide.isCoreMarker(item.marker.id, catalogue: catalogue, sex: sex)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(item.marker.name).font(.system(size: 13, weight: .semibold))
                            if isCore { Pill(text: "★ Core", tone: .gold) }
                        }
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
            upgrades = planner.upgrades()
            conditionalGenes = (try? planner.conditionalGeneticTests(db: services.db, today: today)) ?? []
            doNotBuyGenes = planner.doNotBuyGeneticTests()
            checklist = planner.checklist()
            retests = try planner.retests()
            coreSummary = try CoreBloodworkGuide.summarize(catalogue: catalogue, draws: draws, sex: sex, today: today)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

