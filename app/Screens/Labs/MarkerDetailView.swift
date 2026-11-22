import FitnessCore
import SwiftUI

struct MarkerLibraryView: View {
    @ObservedObject var model: LabsModel
    var chapter: String?
    @State private var search = ""

    private var markers: [LabMarker] {
        let base = search.isEmpty ? model.catalogue.visibleMarkers(for: model.sex) : model.catalogue.search(search).filter { $0.applies(to: model.sex) }
        return base.filter { chapter == nil || $0.chapter == chapter }
    }

    private var chapters: [String] {
        var seen: [String] = []
        for marker in markers where !seen.contains(marker.chapter) { seen.append(marker.chapter) }
        return seen
    }

    var body: some View {
        List {
            ForEach(chapters, id: \.self) { name in
                Section(name) {
                    ForEach(markers.filter { $0.chapter == name }) { marker in
                        NavigationLink { MarkerDetailView(model: model, marker: marker) } label: { label(marker) }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .searchable(text: $search, prompt: "Marker or alias")
        .navigationTitle(chapter ?? "Markers")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(_ marker: LabMarker) -> some View {
        let prefs = model.preferences ?? LabPreferences(sex: model.sex)
        return HStack {
            Text(marker.name)
            Spacer()
            if let latest = try? model.draw.history(of: marker.id).first {
                let text = latest.textValue ?? "\(Format.number(latest.value)) \(latest.unit)"
                Text(text).font(.system(size: 12)).foregroundColor(Theme.muted)
                LabStatusPill(status: LabReader.read(result: latest, marker: marker, preferences: prefs).status)
            }
        }
    }
}

/// Everything the vault says about one marker: the latest reading, its bands, the trend, the seven points, doctor lines and retest.
struct MarkerDetailView: View {
    @ObservedObject var model: LabsModel
    let marker: LabMarker
    @State private var history: [LabResult] = []
    @State private var latestDrawResults: [LabResult] = []

    private var prefs: LabPreferences { model.preferences ?? LabPreferences(sex: model.sex, showDrugNotes: model.showDrugNotes) }
    private var latest: LabResult? { history.first }
    private var latestDrawDraft: LabDrawDraft? {
        guard let latest else { return nil }
        return model.draws.first { $0.id == latest.drawID }?.draft
    }
    private var reading: LabReading? {
        latest.map { LabReader.read(result: $0, marker: marker, preferences: prefs, draw: latestDrawDraft) }
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
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
        .onAppear {
            let loaded = (try? model.draw.history(of: marker.id)) ?? []
            history = loaded
            if let first = loaded.first {
                latestDrawResults = (try? model.draw.results(inDraw: first.drawID)) ?? []
            }
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
            Text(marker.chapter).font(.system(size: 12)).foregroundColor(Theme.muted)
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
                if let stratum = reading.activeStratum {
                    Text("Stratum: \(stratum.population)")
                        .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                }
                if let tierLabel = reading.tierLabel, !tierLabel.isEmpty {
                    Text(tierLabel).font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Text("Latest: \(Format.longDate(latest.date))\(latest.isCalculated ? " · calculated from that draw" : "")")
                    .font(.system(size: 12)).foregroundColor(Theme.muted)
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
                HStack {
                    Text(Format.longDate(result.date)).font(.system(size: 13))
                    Spacer()
                    Text("\(Format.number(result.value)) \(result.unit)").font(.system(size: 13)).foregroundColor(Theme.muted)
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
