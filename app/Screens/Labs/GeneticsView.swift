import FitnessCore
import SwiftUI

extension LabBadgeTone {
    var pillTone: Pill.Tone {
        switch self {
        case .green: return .green
        case .amber: return .amber
        case .red: return .red
        case .grey: return .grey
        }
    }
}

/// Editable initial & anytime sheet for TRT/HRT, prescription medication classes, and regular alcohol context.
struct LabClinicalContextSheet: View {
    let settings: LabSettings
    @Environment(\.dismiss) private var dismiss
    @State private var reverseGeneticsEnabled = true
    @State private var onTRTOrHRT = false
    @State private var activeMedications: Set<LabMedicationClass> = []
    @State private var drinksAlcoholRegularly = false
    @State private var oxidativeTherapyPlanned = false
    @State private var clottingRiskHistory = false
    @State private var persistentLactoseSymptoms = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Genes like Factor V Leiden, CYP2D6/2C19, G6PD, ALDH2, and HFE interact directly with hormones, prescriptions, and clinical history. Update these switches anytime.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Reverse genetics (labs & meds → DNA test suggestions)") {
                    Toggle(isOn: $reverseGeneticsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suggest DNA tests from my labs & meds").font(.system(size: 14, weight: .medium))
                            Text("Default On · recommends conditional genetic tests only when bloodwork, prescriptions, or switches warrant one.")
                                .font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("labs-context-reverse-genetics-toggle")
                }

                Section("Hormone replacement") {
                    Toggle("On TRT or systemic HRT", isOn: $onTRTOrHRT)
                        .accessibilityIdentifier("labs-context-trt-toggle")
                }

                Section("Active prescription classes") {
                    ForEach(LabMedicationClass.allCases, id: \.rawValue) { med in
                        Toggle(isOn: binding(for: med)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(med.title).font(.system(size: 14, weight: .medium))
                                Text(med.subtitle).font(.system(size: 11)).foregroundColor(Theme.muted)
                            }
                        }
                        .accessibilityIdentifier("labs-context-med-\(med.rawValue)")
                    }
                }

                Section("Personal clinical & symptom switches") {
                    Toggle(isOn: $oxidativeTherapyPlanned) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Taking or planning IV Vitamin C / Methylene Blue").font(.system(size: 14, weight: .medium))
                            Text("Triggers G6PD safety check before oxidative therapy.")
                                .font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("labs-context-oxidative-toggle")

                    Toggle(isOn: $clottingRiskHistory) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Personal or family history of blood clots").font(.system(size: 14, weight: .medium))
                            Text("Triggers Factor V Leiden & Prothrombin G20210A check.")
                                .font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("labs-context-clotting-toggle")

                    Toggle(isOn: $persistentLactoseSymptoms) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dairy causes stomach symptoms after a 2-week break").font(.system(size: 14, weight: .medium))
                            Text("Suggests optional LCT / MCM6 test; stays silent when Off.")
                                .font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("labs-context-lactose-toggle")
                }

                Section("Alcohol") {
                    Toggle("Drinks alcohol regularly", isOn: $drinksAlcoholRegularly)
                        .accessibilityIdentifier("labs-context-alcohol-toggle")
                }
            }
            .navigationTitle("TRT & Rx context")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .accessibilityIdentifier("labs-context-save")
                }
            }
            .onAppear(perform: load)
            .errorAlert($errorMessage)
        }
    }

    private func binding(for med: LabMedicationClass) -> Binding<Bool> {
        Binding(
            get: { activeMedications.contains(med) },
            set: { enabled in
                if enabled { activeMedications.insert(med) } else { activeMedications.remove(med) }
            }
        )
    }

    private func load() {
        guard let prefs = try? settings.load() else { return }
        reverseGeneticsEnabled = prefs.reverseGeneticsEnabled
        onTRTOrHRT = prefs.onTRTOrHRT
        activeMedications = prefs.activeMedications
        drinksAlcoholRegularly = prefs.drinksAlcoholRegularly
        oxidativeTherapyPlanned = prefs.oxidativeTherapyPlanned
        clottingRiskHistory = prefs.clottingRiskHistory
        persistentLactoseSymptoms = prefs.persistentLactoseSymptoms
    }

    private func save() {
        do {
            try settings.confirmContext(
                onTRTOrHRT: onTRTOrHRT,
                activeMedications: activeMedications,
                drinksAlcoholRegularly: drinksAlcoholRegularly,
                reverseGeneticsEnabled: reverseGeneticsEnabled,
                oxidativeTherapyPlanned: oxidativeTherapyPlanned,
                clottingRiskHistory: clottingRiskHistory,
                persistentLactoseSymptoms: persistentLactoseSymptoms)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Volume 07 Genetics hub: TRT/Rx context bar, active genetic findings, 5 clinical action categories, and foundational guide.
struct GeneticsView: View {
    let catalogue: LabCatalogue
    let services: Services
    @ObservedObject var labsModel: LabsModel
    @State private var screenVM: GeneticsScreenViewModel?
    @State private var quickFilter: GeneticsQuickFilter = .all
    @State private var search = ""
    @State private var editingContext = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let vm = screenVM {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        contextCard(vm)
                        quickFilterBar(vm)
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                if (quickFilter == .all || quickFilter == .conditionalTriggered || quickFilter == .conditionalAll) && !vm.reverseRecommendations.isEmpty {
                    Section("Consider genetic test (\(vm.reverseRecommendations.count))") {
                        ForEach(vm.reverseRecommendations) { rec in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 6) {
                                    Text(rec.geneName).font(.system(size: 14, weight: .bold))
                                        .foregroundColor(rec.isSafetyGate ? Theme.red : Theme.amber)
                                    Spacer()
                                    if rec.requiresClinicalGradeAssay {
                                        Pill(text: "Clinical-grade lab only", tone: .red)
                                    } else {
                                        Pill(text: "Triggered", tone: .amber)
                                    }
                                }
                                Text("Why: \(rec.triggerSummary)")
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(rec.rationale)
                                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let guardrail = rec.guardrailWarning {
                                    Text("⚠️ \(guardrail)")
                                        .font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.amber)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if let clinical = rec.clinicalGradeWarning {
                                    Text("🏥 \(clinical)")
                                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 4)
                            .accessibilityIdentifier("labs-reverse-gene-\(rec.geneID)")
                        }
                    }
                }

                if (quickFilter == .all || quickFilter == .logged) && !vm.activeFindings.isEmpty {
                    Section("Active genetic findings (\(vm.activeFindings.count))") {
                        ForEach(vm.activeFindings) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: item.severity == .fix ? "exclamationmark.triangle.fill" : "sparkles")
                                        .foregroundColor(item.severity == .fix ? Theme.red : Theme.amber)
                                    Text(item.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(item.severity == .fix ? Theme.red : Theme.text)
                                }
                                Text(item.detail)
                                    .font(.system(size: 12))
                                    .foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                if vm.sections.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No genes match this filter.")
                                .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                            Button("Reset filters") {
                                quickFilter = .all
                                search = ""
                            }
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                        }
                        .padding(.vertical, 6)
                    }
                } else {
                    ForEach(vm.sections) { section in
                        Section {
                            ForEach(section.genes) { item in
                                NavigationLink {
                                    GeneDetailView(gene: item.gene, catalogue: catalogue, labsModel: labsModel,
                                                   service: services.genetics, initialPicked: item.pickedGenotype, changed: load)
                                } label: {
                                    geneRow(item)
                                }
                                .accessibilityIdentifier("labs-gene-row-\(item.id)")
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(section.title) (\(section.genes.count))")
                                if let sub = section.subtitle {
                                    Text(sub).font(.system(size: 11, weight: .regular)).foregroundColor(Theme.muted).textCase(nil)
                                }
                            }
                        }
                    }
                }
            }

            if !catalogue.geneticsGuide.isEmpty {
                Section {
                    DisclosureGroup("Foundational genetics rules (\(catalogue.geneticsGuide.count) notes)") {
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
        .searchable(text: $search, prompt: "Gene or variant")
        .onChange(of: quickFilter) { _ in load() }
        .onChange(of: search) { _ in load() }
        .navigationTitle("Genetics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { editingContext = true } label: {
                    Label("TRT & Rx", systemImage: "pills")
                }
                .accessibilityIdentifier("labs-context-toolbar-button")
            }
        }
        .sheet(isPresented: $editingContext, onDismiss: {
            load()
            labsModel.load()
        }) {
            LabClinicalContextSheet(settings: services.labSettings)
        }
        .onAppear(perform: load)
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private func contextCard(_ vm: GeneticsScreenViewModel) -> some View {
        if vm.needsContextPrompt {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("TRT & Rx clinical context")
                Text("Confirm whether you use TRT/HRT, certain prescriptions, or regular alcohol so gene safety checks (like Factor V + TRT or CYP2D6 meds) stay accurate. You can edit this anytime later.")
                    .font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Set up TRT & Rx") { editingContext = true }
                        .buttonStyle(CompactButtonStyle())
                        .accessibilityIdentifier("labs-context-button")
                    Button("None apply right now") { confirmNone() }
                        .buttonStyle(CompactButtonStyle(ghost: true))
                        .accessibilityIdentifier("labs-context-confirm-none")
                }
            }
            .card(highlighted: true)
            .accessibilityIdentifier("labs-context-prompt-card")
        } else {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel("TRT & Rx context")
                    Text(vm.contextSummary)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Edit") { editingContext = true }
                    .buttonStyle(CompactButtonStyle(ghost: true))
                    .accessibilityIdentifier("labs-context-button")
            }
            .card()
        }
    }

    private func geneRow(_ item: GeneRowViewModel) -> some View {
        let isSkip = item.gene.changeNothingMandate || item.gene.actionCategory == .changeNothing
        return HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.gene.name).font(.system(size: 15, weight: .semibold))
                    if isSkip {
                        Pill(text: "Skip / Do Not Buy", tone: .red)
                    } else if item.pickedGenotype == nil, let triage = item.triageBadge {
                        Pill(text: triage == "Worth Knowing Once" ? "Worth knowing once" : "Conditional",
                             tone: triage == "Worth Knowing Once" ? .green : .amber)
                    }
                }
                if let sub = item.subtitle {
                    Text(sub).font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                if let direct = item.directPhenotypeNote {
                    Text(direct).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.green)
                } else if item.requiresClinicalGradeAssay && item.pickedGenotype == nil {
                    Text("Requires clinical-grade / physician lab (not consumer SNP chip)")
                        .font(.system(size: 11)).foregroundColor(Theme.amber)
                }
            }
            Spacer()
            if let picked = item.pickedGenotype {
                Pill(text: shortGenotype(picked), tone: item.pickedTone.pillTone)
            }
        }
    }

    private func quickFilterBar(_ vm: GeneticsScreenViewModel) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(GeneticsQuickFilter.allCases) { option in
                    let isSelected = quickFilter == option
                    let count = vm.quickCounts[option] ?? 0
                    Button("\(option.rawValue) (\(count))") {
                        quickFilter = option
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .background(isSelected ? Theme.green : Theme.card)
                    .foregroundColor(isSelected ? Theme.onGreen : Theme.muted)
                    .overlay(Capsule().stroke(isSelected ? .clear : Theme.line))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("labs-genetics-chip-\(option.rawValue)")
                }
            }
        }
    }

    private func shortGenotype(_ raw: String) -> String {
        if let paren = raw.firstIndex(of: "("), paren > raw.startIndex {
            let prefix = raw[..<paren].trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty && prefix.count <= 26 { return prefix }
        }
        return raw.count > 26 ? String(raw.prefix(24)) + "…" : raw
    }

    private func confirmNone() {
        do {
            try services.labSettings.confirmContext(onTRTOrHRT: false, activeMedications: [], drinksAlcoholRegularly: false)
            load()
            labsModel.load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func load() {
        do {
            screenVM = try GeneticsPresenter.screen(
                catalogue: catalogue, db: services.db, today: services.clock.today(),
                search: search, quickFilter: quickFilter)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GeneDetailView: View {
    let gene: LabGene
    let catalogue: LabCatalogue
    @ObservedObject var labsModel: LabsModel
    let service: GeneticsService?
    let initialPicked: String?
    let changed: () -> Void
    @EnvironmentObject private var services: Services
    @State private var picked: String?
    @State private var loadedInitial = false
    @State private var errorMessage: String?

    private var vm: GeneDetailViewModel {
        GeneticsPresenter.detail(gene: gene, pickedGenotype: picked)
    }

    var body: some View {
        List {
            if vm.showChangeNothingBanner {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Pill(text: "Skip / Do Not Buy — Test Phenotype Directly", tone: .red)
                            Spacer()
                        }
                        Text("Genotype alone never justifies buying this DNA test, adding supplement stacks, or altering training. Measure and manage the direct clinical or blood marker instead.")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let direct = GeneticsPresenter.directPhenotypeLabel(for: gene) {
                            Text(direct).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if vm.requiresClinicalGradeAssay, let clinicalWarn = vm.clinicalGradeWarning {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Pill(text: "Clinical-Grade / Physician Lab Required", tone: .amber)
                            Spacer()
                        }
                        Text(clinicalWarn)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let genotypes = gene.genotypes, !genotypes.isEmpty {
                Section("Your genotype") {
                    Picker("Genotype", selection: $picked) {
                        Text("Not tested / clear").tag(String?.none)
                        ForEach(genotypes, id: \.genotype) { Text($0.genotype).tag(String?.some($0.genotype)) }
                    }
                    .accessibilityIdentifier("labs-genotype-picker")
                    if let badge = vm.riskBadge {
                        HStack {
                            Text("Classification").font(.system(size: 13)).foregroundColor(Theme.muted)
                            Spacer()
                            Pill(text: badge, tone: vm.riskLevelTone.pillTone)
                        }
                    }
                }
            } else {
                Section { Text("The vault gives no genotype table for this gene.").foregroundColor(Theme.muted) }
            }

            if let row = vm.selectedRow {
                Section("What your genotype means") {
                    if let meaning = row.meaning, !meaning.isEmpty {
                        Text(meaning).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let rule = row.clinicalRule, !rule.isEmpty, rule != row.meaning {
                        Text(rule).font(.system(size: 13)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if let urgency = row.urgency {
                        Text("Urgency: \(urgency.title)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.red)
                    }
                    ForEach(row.actions ?? [], id: \.self) {
                        Text("• \($0)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let adds = row.addsMarkers, !adds.isEmpty {
                        Text("Adds to your draw: \(adds.joined(separator: ", "))")
                            .font(.system(size: 12)).foregroundColor(Theme.green)
                    }
                }
            }

            if gene.coreThesis != nil || gene.mechanismSummary != nil {
                Section("Core thesis & mechanism") {
                    if let thesis = gene.coreThesis {
                        Text(thesis).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let mech = gene.mechanismSummary {
                        DisclosureGroup("Biological mechanism") {
                            Text(mech).font(.system(size: 12)).foregroundColor(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                        }
                        .font(.system(size: 12, weight: .semibold)).tint(Theme.green)
                    }
                }
            }

            if !vm.substitutions.isEmpty {
                Section("Nutrient form swaps") {
                    ForEach(Array(vm.substitutions.enumerated()), id: \.offset) { _, sub in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Avoid: \(sub.replaceOrAvoid)")
                                .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amber)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Use instead: \(sub.useInstead)")
                                .font(.system(size: 13)).foregroundColor(Theme.green)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if !vm.verifiers.isEmpty {
                Section("Bloodwork & clinical verifiers") {
                    ForEach(vm.verifiers) { v in
                        if let mid = v.markerID, let marker = catalogue.marker(mid) {
                            NavigationLink { MarkerDetailView(model: labsModel, marker: marker) } label: {
                                verifierRowContent(v)
                            }
                        } else {
                            verifierRowContent(v)
                        }
                    }
                }
            } else if let confirm = gene.confirmWith, !confirm.isEmpty {
                Section("Confirm with bloodwork") {
                    ForEach(confirm, id: \.self) { Text($0).font(.system(size: 13)) }
                }
            }

            if !vm.shiftLines.isEmpty {
                Section("Target & timing shifts") {
                    ForEach(vm.shiftLines, id: \.self) {
                        Text("• \($0)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !vm.epistaticCells.isEmpty {
                Section("Gene × bloodwork 2×2 guide") {
                    DisclosureGroup("Show \(vm.epistaticCells.count) combinations") {
                        ForEach(Array(vm.epistaticCells.enumerated()), id: \.offset) { _, cell in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(cell.condition).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                                Text(cell.interpretation).font(.system(size: 12)).foregroundColor(Theme.muted)
                                Text("→ \(cell.action)").font(.system(size: 12, weight: .medium)).foregroundColor(Theme.green)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .tint(Theme.green)
                }
            }

            if !vm.contraindications.isEmpty {
                Section("Safety rules & doctor referrals") {
                    ForEach(Array(vm.contraindications.enumerated()), id: \.offset) { _, contra in
                        VStack(alignment: .leading, spacing: 4) {
                            if let ref = contra.mandatoryReferral, !ref.isEmpty {
                                Text("Referral: \(ref)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.red)
                            }
                            if !contra.forbiddenItems.isEmpty {
                                Text("Strictly avoid: \(contra.forbiddenItems.joined(separator: ", "))")
                                    .font(.system(size: 12)).foregroundColor(Theme.amber)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if !contra.coachStopLine.isEmpty {
                                Text(contra.coachStopLine).font(.system(size: 12)).foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            if !vm.whatNotToDo.isEmpty {
                Section("What NOT to do") {
                    ForEach(vm.whatNotToDo, id: \.self) {
                        Text("✕ \($0)").font(.system(size: 13)).foregroundColor(Theme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !vm.caveatLines.isEmpty {
                Section("Testing & ancestry blind spots") {
                    DisclosureGroup("Show \(vm.caveatLines.count) testing notes") {
                        ForEach(vm.caveatLines, id: \.self) {
                            Text("• \($0)").font(.system(size: 12)).foregroundColor(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(Theme.green)
                }
            }

            if vm.selectedRow == nil, let genotypes = gene.genotypes, !genotypes.isEmpty {
                Section("All variants in the vault") {
                    ForEach(genotypes, id: \.genotype) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.genotype).font(.system(size: 14, weight: .semibold))
                            if let meaning = item.meaning {
                                Text(meaning).font(.system(size: 12)).foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }

            if let source = gene.entryID ?? gene.source {
                Section { Text("Source: \(source)").font(.system(size: 11)).foregroundColor(Theme.muted) }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(gene.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loadedInitial {
                picked = initialPicked
                loadedInitial = true
            }
        }
        .onChange(of: picked) { save($0) }
        .errorAlert($errorMessage)
    }

    private func verifierRowContent(_ v: VerifierRowViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(v.markerName).font(.system(size: 14, weight: .semibold))
                Spacer()
                Pill(text: v.badge, tone: v.badgeTone.pillTone)
            }
            if !v.rule.isEmpty {
                Text(v.rule).font(.system(size: 12)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func save(_ genotype: String?) {
        guard loadedInitial, genotype != initialPicked || genotype == nil else { return }
        do {
            if let genotype {
                try service?.set(gene.id, genotype: genotype, on: services.clock.today())
            } else {
                try service?.clear(gene.id)
            }
            changed()
            labsModel.load()
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }
}
