import FitnessCore
import SwiftUI

struct MarkerLibraryView: View {
    @ObservedObject var model: LabsModel
    var chapter: String?
    @State private var search = ""
    @State private var quickFilter: MarkerQuickFilter = .all
    @State private var customFilter = MarkerCustomFilter()
    @State private var showingCustomSheet = false

    private var vm: MarkerLibraryViewModel {
        let prefs = model.preferences ?? LabPreferences(sex: model.sex, showDrugNotes: model.showDrugNotes)
        return (try? MarkerLibraryPresenter.build(
            catalogue: model.catalogue, draws: model.draw, preferences: prefs,
            genotypes: model.genotypes, today: model.today, fixedChapter: chapter,
            search: search, quickFilter: quickFilter,
            customFilter: customFilter.isActive ? customFilter : nil))
            ?? .empty
    }

    var body: some View {
        List {
            Section {
                filterBar
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if vm.sections.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No markers match this filter.")
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Button("Reset filters") {
                            quickFilter = .all
                            customFilter = MarkerCustomFilter()
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                ForEach(vm.sections) { section in
                    Section("\(section.chapter) (\(section.rows.count))") {
                        ForEach(section.rows) { row in
                            NavigationLink { MarkerDetailView(model: model, marker: row.marker) } label: { label(row) }
                                .accessibilityIdentifier("labs-marker-row-\(row.marker.id)")
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .searchable(text: $search, prompt: "Marker or alias")
        .navigationTitle(chapter ?? "Markers (\(vm.totalMatched))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingCustomSheet = true
                } label: {
                    Label("Custom filter", systemImage: customFilter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("labs-markers-custom-filter-button")
            }
        }
        .sheet(isPresented: $showingCustomSheet) {
            MarkerCustomFilterSheet(filter: $customFilter, allChapters: vm.allChapters) {
                if customFilter.isActive { quickFilter = .all }
            }
        }
    }

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Button {
                        showingCustomSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                            Text(customFilter.isActive ? "Custom: \(customFilter.summaryText)" : "Custom filter")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(customFilter.isActive ? Theme.green : Theme.card)
                        .foregroundColor(customFilter.isActive ? Theme.onGreen : Theme.green)
                        .overlay(Capsule().stroke(Theme.green.opacity(0.6), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("labs-marker-chip-custom")

                    ForEach(MarkerQuickFilter.allCases) { option in
                        let isSelected = !customFilter.isActive && quickFilter == option
                        let count = vm.quickCounts[option] ?? 0
                        Button("\(option.rawValue) (\(count))") {
                            customFilter = MarkerCustomFilter()
                            quickFilter = option
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(isSelected ? Theme.green : Theme.card)
                        .foregroundColor(isSelected ? Theme.onGreen : Theme.muted)
                        .overlay(Capsule().stroke(isSelected ? .clear : Theme.line))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("labs-marker-chip-\(option.rawValue)")
                    }
                }
            }
        }
    }

    private func label(_ row: MarkerLibraryRowViewModel) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.marker.name)
                    if row.isCore { Pill(text: "★ Core", tone: .gold) }
                }
                if row.isRetestDue {
                    Text("Retest due").font(.system(size: 11)).foregroundColor(Theme.amber)
                }
            }
            Spacer()
            if let latest = row.latest {
                let text = latest.textValue ?? "\(Format.number(latest.value)) \(latest.unit)"
                Text(text).font(.system(size: 12)).foregroundColor(Theme.muted)
                if let reading = row.reading {
                    LabStatusPill(status: reading.status)
                }
            } else if MarkerLibraryPresenter.isTestable(row.marker) {
                Pill(text: "Not done", tone: .grey)
            }
        }
    }
}

struct MarkerCustomFilterSheet: View {
    @Binding var filter: MarkerCustomFilter
    let allChapters: [String]
    let onApply: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MarkerCustomFilter()

    var body: some View {
        NavigationStack {
            Form {
                Section("Priority tier") {
                    Picker("Tier", selection: $draft.tier) {
                        ForEach(MarkerCustomFilter.Tier.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("labs-custom-filter-tier")
                }

                Section("Testing status") {
                    Picker("Completion", selection: $draft.completion) {
                        ForEach(MarkerCustomFilter.Completion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("labs-custom-filter-completion")
                }

                Section("Result status (for tested markers)") {
                    Picker("Reading", selection: $draft.status) {
                        ForEach(MarkerCustomFilter.Status.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .accessibilityIdentifier("labs-custom-filter-status")
                }

                if allChapters.count > 1 {
                    Section("Systems / chapters (optional)") {
                        ForEach(allChapters, id: \.self) { name in
                            let selected = draft.chapters.contains(name)
                            Button {
                                if selected { draft.chapters.remove(name) } else { draft.chapters.insert(name) }
                            } label: {
                                HStack {
                                    Text(name).foregroundColor(Theme.text)
                                    Spacer()
                                    if selected {
                                        Image(systemName: "checkmark").foregroundColor(Theme.green)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button("Reset all filters", role: .destructive) {
                        draft = MarkerCustomFilter()
                    }
                    .accessibilityIdentifier("labs-custom-filter-reset")
                }
            }
            .navigationTitle("Custom marker filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        filter = draft
                        onApply()
                        dismiss()
                    }
                    .accessibilityIdentifier("labs-custom-filter-apply")
                }
            }
            .onAppear { draft = filter }
        }
    }
}

/// Proportional color-coded horizontal range bar with Low / Normal / Optimal / High zones and a glowing "You" pin.
struct MarkerRangeBarView: View {
    let bar: LabRangeBarModel
    let status: LabStatus?

    private var pinColor: Color {
        switch status {
        case .optimal: return Theme.green
        case .disputed: return Theme.amber
        case .low, .high: return Theme.gold
        default: return Theme.text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let low = bar.lowLabel {
                    Text(low).font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 4)
                Text(bar.optimalLabel).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.green)
                Spacer(minLength: 4)
                if let high = bar.highLabel {
                    Text(high).font(.system(size: 11)).foregroundColor(Theme.muted)
                }
            }
            GeometryReader { proxy in
                let totalW = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, seg in
                            Rectangle()
                                .fill(segmentColor(seg.kind))
                                .frame(width: max(totalW * seg.widthFraction - 1, 2), height: 10)
                        }
                    }
                    .clipShape(Capsule())

                    if let pin = bar.pinFraction {
                        Circle()
                            .fill(pinColor)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(Theme.background, lineWidth: 2.5))
                            .shadow(color: pinColor.opacity(0.6), radius: 4)
                            .offset(x: min(max(totalW * pin - 8, 0), max(totalW - 16, 0)))
                            .accessibilityIdentifier("labs-range-bar-pin")
                    }
                }
            }
            .frame(height: 16)
            if let pinText = bar.pinText {
                Text("▲ \(pinText)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(pinColor)
            }
            if let shift = bar.geneticShiftSummary {
                Text("🧬 \(shift)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.green)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Theme.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("labs-range-bar-genetic-shift")
            }
        }
        .padding(.top, 4)
        .accessibilityIdentifier("labs-marker-range-bar")
    }

    private func segmentColor(_ kind: LabRangeBarModel.SegmentKind) -> Color {
        switch kind {
        case .low: return Theme.amber.opacity(0.6)
        case .normal: return Theme.line
        case .optimal: return Theme.green
        case .high: return Theme.red.opacity(0.65)
        }
    }
}

/// Compact 6pt visual spectrum bar for marker rows inside a draw.
struct MarkerMiniRangeBar: View {
    let bar: LabRangeBarModel
    let status: LabStatus?

    private var pinColor: Color {
        switch status {
        case .optimal: return Theme.green
        case .disputed: return Theme.amber
        case .low, .high: return Theme.gold
        default: return Theme.text
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let totalW = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                HStack(spacing: 1) {
                    ForEach(Array(bar.segments.enumerated()), id: \.offset) { _, seg in
                        Rectangle()
                            .fill(segmentColor(seg.kind))
                            .frame(width: max(totalW * seg.widthFraction - 1, 1), height: 5)
                    }
                }
                .clipShape(Capsule())
                if let pin = bar.pinFraction {
                    Circle()
                        .fill(pinColor)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Theme.background, lineWidth: 1.5))
                        .offset(x: min(max(totalW * pin - 4.5, 0), max(totalW - 9, 0)))
                }
            }
        }
        .frame(height: 9)
    }

    private func segmentColor(_ kind: LabRangeBarModel.SegmentKind) -> Color {
        switch kind {
        case .low: return Theme.amber.opacity(0.55)
        case .normal: return Theme.line
        case .optimal: return Theme.green
        case .high: return Theme.red.opacity(0.6)
        }
    }
}

/// Everything the vault says about one marker: the latest reading, its bands, the trend, the seven points, doctor lines and retest.
struct MarkerDetailView: View {
    @ObservedObject var model: LabsModel
    let marker: LabMarker
    @State private var history: [LabResult] = []
    @State private var latestDrawResults: [LabResult] = []
    @State private var personalOverride: LabMarkerOverride?
    @State private var editingOverride = false
    @State private var editingResult: LabResult?

    private var prefs: LabPreferences { model.preferences ?? LabPreferences(sex: model.sex, showDrugNotes: model.showDrugNotes) }
    private var latest: LabResult? { history.first }
    private var latestDrawDraft: LabDrawDraft? {
        guard let latest else { return nil }
        return model.draws.first { $0.id == latest.drawID }?.draft
    }
    private var reading: LabReading? {
        latest.map {
            LabReader.read(result: $0, marker: marker, preferences: prefs, draw: latestDrawDraft,
                           genotypes: model.genotypes, personalOverride: personalOverride)
        }
    }
    private var rangeBar: LabRangeBarModel? {
        LabRangeBarModel.build(marker: marker, sex: model.sex, reading: reading, latestResult: latest,
                               genotypes: model.genotypes, preferences: prefs)
    }
    private var isCore: Bool {
        CoreBloodworkGuide.isCoreMarker(marker.id, catalogue: model.catalogue, sex: model.sex)
    }
    private var validityWarnings: [LabValidityWarning] {
        guard let latest, let draft = latestDrawDraft else { return [] }
        return LabValidityGate.evaluate(result: latest, marker: marker, draw: draft, sameDrawResults: latestDrawResults,
                                        catalogue: model.catalogue, sex: model.sex)
    }
    private var longitudinal: LabLongitudinalSummary? {
        let drawsByID = Dictionary(uniqueKeysWithValues: model.draws.map { ($0.id, $0.draft) })
        return LabLongitudinalTracker.summarize(marker: marker, history: history, drawsByID: drawsByID)
    }
    private var markerCrossChecks: [(title: String, detail: String, isClean: Bool)] {
        guard let snap = model.dashboard?.snapshot else { return [] }
        var out: [(String, String, Bool)] = []
        for d in snap.discordances where d.markerIDs.contains(marker.id) {
            out.append((d.title, d.detail, false))
        }
        for s in snap.simplePatterns where s.markerIDs.contains(marker.id) {
            out.append((s.name, "\(s.contributingSummary) — \(s.detail)", false))
        }
        for clean in snap.cleanCompanionChecks where clean.markerIDs.contains(marker.id) {
            out.append((clean.title, clean.summary, true))
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !markerCrossChecks.isEmpty {
                    crossChecksCard
                }
                if let notes = reading?.geneticNotes, !notes.isEmpty {
                    listCard("Active genetic modifiers", notes)
                }
                if !validityWarnings.isEmpty { validityCard }
                if let longitudinal, (longitudinal.previousValue != nil || longitudinal.switchedLab || !longitudinal.driftFlags.isEmpty) {
                    longitudinalCard(longitudinal)
                }
                if !bands.isEmpty { bandsCard }
                if history.count > 1 { trendCard }
                if !history.isEmpty { historyCard }
                if let inter = marker.interventions {
                    steppedInterventionsCard(inter)
                    if !inter.whatNotToDo.isEmpty { guardrailsCard(inter.whatNotToDo) }
                }
                if !marker.discordance.isEmpty { listCard("Discordance & masking rules", marker.discordance) }
                sevenPoints
                if !doctorLines.isEmpty || !(marker.escalation?.specialists.isEmpty ?? true) { doctorCard }
                if let formula = marker.formula { listCard("How the app works it out", [formulaText(formula)]) }
                if !marker.retest.isEmpty { listCard("When to retest", marker.retest.map(\.text)) }
                if !visiblePrepSteps.isEmpty { listCard("Before the draw", visiblePrepSteps) }
                if !marker.disputes.isEmpty { disputesCard }
                linksCard
                Text("Source: \(marker.lesson)").font(.system(size: 11)).foregroundColor(Theme.muted)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(marker.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(personalOverride == nil ? "Target" : "Target ✓") {
                    editingOverride = true
                }
                .font(.system(size: 13, weight: .semibold))
                .accessibilityIdentifier("labs-marker-override-button")
            }
        }
        .onAppear(perform: reloadHistory)
        .sheet(isPresented: $editingOverride, onDismiss: {
            reloadHistory()
            model.load()
        }) {
            MarkerPersonalOverrideSheet(marker: marker, existing: personalOverride, service: model.services.markerOverrides)
        }
        .sheet(item: $editingResult) { target in
            EditResultSheet(existing: target, marker: marker, draws: model.draw, sex: model.sex) {
                reloadHistory()
                model.load()
            }
        }
    }

    private func reloadHistory() {
        let loaded = (try? model.draw.history(of: marker.id)) ?? []
        history = loaded
        personalOverride = try? model.services.markerOverrides.override(for: marker.id)
        if let first = loaded.first {
            latestDrawResults = (try? model.draw.results(inDraw: first.drawID)) ?? []
        } else {
            latestDrawResults = []
        }
    }

    private func formulaText(_ formula: LabFormula) -> String {
        var text = formula.expr
        for (id, unit) in formula.inputs {
            text = text.replacingOccurrences(of: "{\(id)}", with: "\(model.catalogue.marker(id)?.name ?? id) (\(unit))")
        }
        let condition = formula.onlyIf.map { " Only when \($0.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))." } ?? ""
        return "\(text), from the same draw.\(condition) A value the lab printed is used instead."
    }

    private var bands: [LabBand] { marker.visibleBands(for: model.sex) }
    private var doctorLines: [LabDoctorLine] { marker.visibleDoctorLines(sex: model.sex, showDrugNotes: model.showDrugNotes) }
    private var visiblePrepSteps: [String] {
        marker.prep.compactMap { id in
            guard let step = model.catalogue.prepStep(id) else { return id }
            guard model.sex.allows(sex: nil, tag: step.tag, showDrugNotes: model.showDrugNotes) else { return nil }
            return step.text
        }
    }
    private func shows(_ tag: String?) -> Bool { model.sex.allows(sex: nil, tag: tag, showDrugNotes: model.showDrugNotes) }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(marker.chapter).font(.system(size: 12)).foregroundColor(Theme.muted)
                if isCore {
                    Spacer()
                    Pill(text: "★ Mandatory Core", tone: .gold)
                }
            }
            if let latest, let reading {
                HStack(alignment: .firstTextBaseline) {
                    if let text = latest.textValue {
                        Text(text).font(.system(size: 26, weight: .bold)).foregroundColor(Theme.text)
                    } else if let sec = latest.secondaryValue {
                        Text("\(Format.number(latest.value))/\(Format.number(sec))").font(.system(size: 28, weight: .bold)).foregroundColor(Theme.text)
                        Text(latest.unit).foregroundColor(Theme.muted)
                    } else {
                        Text("\(latest.valueOperator == .belowLimit ? "< " : "")\(Format.number(latest.value))")
                            .font(.system(size: 30, weight: .bold)).foregroundColor(Theme.text)
                        Text(latest.unit).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    LabStatusPill(status: reading.status)
                }
                if let rangeBar {
                    MarkerRangeBarView(bar: rangeBar, status: reading.status)
                }
                if let stratum = reading.activeStratum {
                    Text("Stratum: \(stratum.population)")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                }
                if let tierLabel = reading.tierLabel, !tierLabel.isEmpty {
                    Text(tierLabel).font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Text("Latest: \(Format.longDate(latest.date))\(latest.isCalculated ? " · calculated from that draw" : "")")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                    Spacer()
                    if !latest.isCalculated {
                        Button("Edit result") { editingResult = latest }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Theme.green)
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("labs-marker-edit-latest")
                    }
                }
                if !reading.edgeLabels.isEmpty {
                    Text("On the edge of \(reading.edgeLabels.joined(separator: " and "))").font(.system(size: 12)).foregroundColor(Theme.amber)
                }
                ForEach(reading.disputes, id: \.self) { Text($0).font(.system(size: 12)).foregroundColor(Theme.amber) }
                ForEach(Array(reading.doctorLines.filter { shows($0.tag) }.enumerated()), id: \.offset) { _, line in
                    Text("\(line.urgency.title): \(line.text)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.red)
                }
                ForEach(Array(reading.conditionalDoctorLines.filter { shows($0.tag) }.enumerated()), id: \.offset) { _, line in
                    Text("Check symptoms (\(line.urgency.title)): \(line.requires.map { "with \($0) — " } ?? "")\(line.text)")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amber)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Not tested yet").font(.system(size: 15)).foregroundColor(Theme.muted)
                if let rangeBar {
                    MarkerRangeBarView(bar: rangeBar, status: nil)
                }
            }
            if let what = marker.what { Text(what).font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var validityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Pre-analytic validity check")
            ForEach(Array(validityWarnings.enumerated()), id: \.offset) { _, warn in
                VStack(alignment: .leading, spacing: 2) {
                    Text(warn.title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amber)
                    Text(warn.detail).font(.system(size: 12)).foregroundColor(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var crossChecksCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Combined & companion checks (latest values)")
            ForEach(Array(markerCrossChecks.enumerated()), id: \.offset) { _, check in
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.isClean ? "✓ \(check.title)" : "• \(check.title)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(check.isClean ? Theme.green : Theme.amber)
                    Text(check.detail)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-marker-cross-checks")
    }

    private func longitudinalCard(_ summary: LabLongitudinalSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Trajectory & baseline")
            if let dp = summary.deltaFromPrevious, let pp = summary.percentFromPrevious {
                let sign = dp >= 0 ? "+" : ""
                Text("Since previous draw: \(sign)\(Format.number(dp)) \(summary.unit ?? "") (\(sign)\(Format.number(pp, maxDecimals: 1))%)")
                    .font(.system(size: 13)).foregroundColor(Theme.text)
            }
            if let db = summary.deltaFromBaseline, let pb = summary.percentFromBaseline, summary.previousValue != summary.baselineValue {
                let sign = db >= 0 ? "+" : ""
                Text("Since baseline: \(sign)\(Format.number(db)) \(summary.unit ?? "") (\(sign)\(Format.number(pb, maxDecimals: 1))%)")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
            }
            ForEach(Array(summary.driftFlags.enumerated()), id: \.offset) { _, flag in
                Text("• \(flag.message)").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func steppedInterventionsCard(_ inter: LabInterventions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Stepped action plan")
            if !inter.tier1Foundations.isEmpty {
                DisclosureGroup("1. Foundations (\(inter.tier1Foundations.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(inter.tier1Foundations, id: \.self) { Text("• \($0)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 13, weight: .semibold)).tint(Theme.green)
            }
            if !inter.tier2Nutrition.isEmpty {
                DisclosureGroup("2. Nutrition (\(inter.tier2Nutrition.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(inter.tier2Nutrition, id: \.self) { Text("• \($0)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 13, weight: .semibold)).tint(Theme.green)
            }
            if !inter.tier3Supplements.isEmpty {
                DisclosureGroup("3. Supplements (\(inter.tier3Supplements.count))") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(inter.tier3Supplements.enumerated()), id: \.offset) { _, supp in
                            let dose = supp.dose.map { " (\($0))" } ?? ""
                            let notes = supp.notes.map { " — \($0)" } ?? ""
                            Text("• \(supp.name)\(dose)\(notes)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 13, weight: .semibold)).tint(Theme.green)
            }
            if model.showDrugNotes && !inter.tier4Peptides.isEmpty {
                DisclosureGroup("4. Educational compounds (\(inter.tier4Peptides.count))") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(inter.tier4Peptides, id: \.self) { Text("• \($0)").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 13, weight: .semibold)).tint(Theme.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func guardrailsCard(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.octagon.fill").foregroundColor(Theme.red)
                SectionLabel("What not to do")
            }
            ForEach(items, id: \.self) { line in
                Text("• \(line)").font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-marker-what-not-to-do")
    }

    private var bandsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Bands")
            ForEach(Array(bands.enumerated()), id: \.offset) { _, band in
                let isHere = reading?.bands.contains(band) ?? false
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(band.label).font(.system(size: 13, weight: isHere ? .bold : .regular))
                            .foregroundColor(band.kind == "optimal" ? Theme.green : Theme.text)
                        if isHere { Pill(text: "You", tone: .green) }
                        Spacer()
                        Text(LabCopy.range(band)).font(.system(size: 13)).foregroundColor(Theme.muted)
                    }
                    let notes = [band.sex == .female && model.sex != .female ? "Women only" : nil, band.condition.map { "Only when \($0)" },
                                 band.dispute.map { "Disputed: \($0)" }, LabCopy.origin(band.origin), band.meaning].compactMap { $0 }
                    ForEach(notes, id: \.self) { Text($0).font(.system(size: 11)).foregroundColor(Theme.muted) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Trend (\(marker.defaultUnit ?? "as typed"))")
            LabTrendChart(points: history.reversed().compactMap { result in
                (result.defaultValue ?? (result.defaultUnit == nil ? result.value : nil)).map { TrendPoint(date: result.date, value: $0) }
            })
            .frame(height: 140)
        }
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Every result")
            ForEach(history) { result in
                let labName = model.draws.first { $0.id == result.drawID }?.draft.lab
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Format.longDate(result.date)).font(.system(size: 13))
                        if let labName { Text(labName).font(.system(size: 11)).foregroundColor(Theme.muted) }
                    }
                    Spacer()
                    Text(result.textValue ?? "\(Format.number(result.value)) \(result.unit)")
                        .font(.system(size: 13)).foregroundColor(Theme.muted)
                    if !result.isCalculated {
                        Button { editingResult = result } label: {
                            Image(systemName: "pencil").font(.system(size: 13)).foregroundColor(Theme.green)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var sevenPoints: some View {
        if !marker.howTested.isEmpty { listCard("How it is tested", marker.howTested) }
        textCard("What pushes it up", marker.pushesUp)
        textCard("What pushes it down", marker.pushesDown)
        textCard("Read it next to", marker.nextTo)
        textCard("What to do", marker.whatToDo)
        textCard("Also worth knowing", marker.other)
    }

    @ViewBuilder
    private func textCard(_ title: String, _ items: [LabText]) -> some View {
        let shown = items.filter { shows($0.tag) }
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(title)
                ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("• \(item.text)").font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
                        let notes = [LabCopy.tagNote(item.tag), item.when.flatMap { $0 == "any" ? nil : "When \($0)" }].compactMap { $0 }
                        if !notes.isEmpty { Text(notes.joined(separator: " · ")).font(.system(size: 11)).foregroundColor(Theme.amber) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func listCard(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
            ForEach(Array(items.enumerated()), id: \.offset) { _, text in
                Text("• \(text)").font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var doctorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("See a doctor when")
            if let specs = marker.escalation?.specialists, !specs.isEmpty {
                Text("Specialists: \(specs.joined(separator: ", "))")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amber)
            }
            ForEach(Array(doctorLines.enumerated()), id: \.offset) { _, line in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Pill(text: line.urgency.title, tone: line.urgency <= .urgent ? .red : .amber)
                        if let op = line.op, let value = line.value {
                            Text("\(op) \(Format.number(value)) \(line.unit ?? "")").font(.system(size: 13, weight: .semibold))
                        }
                    }
                    Text(line.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    let notes = [line.requires.map { "Only together with: \($0)" }, LabCopy.tagNote(line.tag), LabCopy.origin(line.origin)].compactMap { $0 }
                    ForEach(notes, id: \.self) { Text($0).font(.system(size: 11)).foregroundColor(Theme.muted) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var disputesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Where the vault disagrees")
            ForEach(marker.disputes, id: \.id) { dispute in
                VStack(alignment: .leading, spacing: 2) {
                    if let topic = dispute.topic { Text(topic).font(.system(size: 13, weight: .semibold)) }
                    if let a = dispute.a { Text("One lesson: \(a)").font(.system(size: 12)) }
                    if let b = dispute.b { Text("Another: \(b)").font(.system(size: 12)) }
                    if let resolution = dispute.resolution {
                        Text("Used here: \(resolution)\(dispute.confidence.map { " (confidence: \($0))" } ?? "")")
                            .font(.system(size: 12)).foregroundColor(Theme.green)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var linksCard: some View {
        let linkedIDs = Array(Set((marker.links?.markers ?? []) + marker.coTests)).sorted()
        let markers = linkedIDs.compactMap(model.catalogue.marker).filter { $0.applies(to: model.sex) }
        let supplements = (marker.links?.supplements ?? []).map { id in
            model.services.supplementLibrary?.entries.first { $0.id == id }?.name ?? id
        }
        let genes = (marker.links?.genes ?? []).compactMap(model.catalogue.gene)
        if !markers.isEmpty || !supplements.isEmpty || !genes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Companion co-tests & links")
                ForEach(markers) { other in
                    NavigationLink(other.name) { MarkerDetailView(model: model, marker: other) }.font(.system(size: 13))
                }
                if !supplements.isEmpty {
                    Text("Supplements: \(supplements.joined(separator: ", "))").font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                }
                if !genes.isEmpty {
                    Text("Genes: \(genes.map(\.name).joined(separator: ", "))").font(.system(size: 13))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}
