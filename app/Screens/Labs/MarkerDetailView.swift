import FitnessCore
import SwiftUI

struct MarkerLibraryView: View {
    @ObservedObject var model: LabsModel
    var chapter: String?
    @State private var search = ""

    private var markers: [LabMarker] {
        let found = search.isEmpty ? model.catalogue.markers : model.catalogue.search(search)
        return found.filter { chapter == nil || $0.chapter == chapter }
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
        HStack {
            Text(marker.name)
            Spacer()
            if let latest = try? model.draw.history(of: marker.id).first {
                Text("\(Format.number(latest.value)) \(latest.unit)").font(.system(size: 12)).foregroundColor(Theme.muted)
                LabStatusPill(status: LabReader.read(value: latest.value, unit: latest.unit, marker: marker, sex: model.sex).status)
            }
        }
    }
}

/// Everything the vault says about one marker: the latest reading, its bands, the trend, the seven points, doctor lines and retest.
struct MarkerDetailView: View {
    @ObservedObject var model: LabsModel
    let marker: LabMarker
    @State private var history: [LabResult] = []

    private var latest: LabResult? { history.first }
    private var reading: LabReading? {
        latest.map { LabReader.read(value: $0.value, unit: $0.unit, marker: marker, sex: model.sex) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if !bands.isEmpty { bandsCard }
                if history.count > 1 { trendCard }
                if !history.isEmpty { historyCard }
                sevenPoints
                if !doctorLines.isEmpty { doctorCard }
                if let formula = marker.formula { listCard("How the app works it out", [formulaText(formula)]) }
                if !marker.retest.isEmpty { listCard("When to retest", marker.retest.map(\.text)) }
                if !marker.prep.isEmpty { listCard("Before the draw", marker.prep.map { model.catalogue.prepStep($0)?.text ?? $0 }) }
                if !marker.disputes.isEmpty { disputesCard }
                linksCard
                Text("Source: \(marker.lesson)").font(.system(size: 11)).foregroundColor(Theme.muted)
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(marker.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { history = (try? model.draw.history(of: marker.id)) ?? [] }
    }

    private func formulaText(_ formula: LabFormula) -> String {
        var text = formula.expr
        for (id, unit) in formula.inputs {
            text = text.replacingOccurrences(of: "{\(id)}", with: "\(model.catalogue.marker(id)?.name ?? id) (\(unit))")
        }
        let condition = formula.onlyIf.map { " Only when \($0.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: ""))." } ?? ""
        return "\(text), from the same draw.\(condition) A value the lab printed is used instead."
    }

    private var bands: [LabBand] { marker.bands.filter { $0.sex == nil || $0.sex == .any || $0.sex == model.sex || $0.sex == .female } }
    private var doctorLines: [LabDoctorLine] { marker.doctor.filter { shows($0.tag) } }
    private func shows(_ tag: String?) -> Bool { tag != "drug" || model.showDrugNotes }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(marker.chapter).font(.system(size: 12)).foregroundColor(Theme.muted)
            if let latest, let reading {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.number(latest.value)).font(.system(size: 30, weight: .bold)).foregroundColor(Theme.text)
                    Text(latest.unit).foregroundColor(Theme.muted)
                    Spacer()
                    LabStatusPill(status: reading.status)
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
            } else {
                Text("Not tested yet").font(.system(size: 15)).foregroundColor(Theme.muted)
            }
            if let what = marker.what { Text(what).font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
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
        let markers = (marker.links?.markers ?? []).compactMap(model.catalogue.marker)
        let supplements = (marker.links?.supplements ?? []).map { id in
            model.services.supplementLibrary?.entries.first { $0.id == id }?.name ?? id
        }
        let genes = (marker.links?.genes ?? []).compactMap(model.catalogue.gene)
        if !markers.isEmpty || !supplements.isEmpty || !genes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Linked")
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
