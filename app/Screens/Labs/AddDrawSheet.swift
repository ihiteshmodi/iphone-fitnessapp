import FitnessCore
import SwiftUI

/// One result being typed: the unit comes from the catalogue, and the lab's own range is asked for where the vault needs it (D8).
struct PendingResult: Identifiable {
    let id = UUID()
    let marker: LabMarker
    var value = ""
    var unit: String
    var labLow = ""
    var labHigh = ""

    init(marker: LabMarker) {
        self.marker = marker
        unit = marker.defaultUnit ?? ""
    }

    static func number(_ text: String) -> Double? { Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)) }
}

/// Yes / no / not answered, because an unanswered prep question must not read as "no".
private enum Answer: String, CaseIterable {
    case unknown = "—", yes = "Yes", no = "No"
    var value: Bool? { self == .unknown ? nil : self == .yes }
}

struct AddDrawSheet: View {
    let catalogue: LabCatalogue
    let draws: LabDrawService
    let today: ISODate
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var time = ""
    @State private var lab = ""
    @State private var fastedHours = ""
    @State private var trained = Answer.unknown
    @State private var alcohol = Answer.unknown
    @State private var biotin = Answer.unknown
    @State private var iron = Answer.unknown
    @State private var ill = Answer.unknown
    @State private var note = ""
    @State private var results: [PendingResult] = []
    @State private var pickingMarker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Draw") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Time (e.g. 08:15)", text: $time).keyboardType(.numbersAndPunctuation)
                    TextField("Lab", text: $lab)
                }
                Section("How you came in") {
                    TextField("Hours fasted", text: $fastedHours).keyboardType(.decimalPad)
                    answer("Hard training in the last 72 h", $trained)
                    answer("Alcohol in the last 5 days", $alcohol)
                    answer("Biotin stopped beforehand", $biotin)
                    answer("Iron stopped beforehand", $iron)
                    answer("Ill recently", $ill)
                    TextField("Note", text: $note)
                }
                Section("Results") {
                    ForEach($results) { $row in ResultFields(row: $row) }
                        .onDelete { results.remove(atOffsets: $0) }
                    Button("+ Add a result") { pickingMarker = true }
                        .accessibilityIdentifier("labs-add-result")
                }
            }
            .navigationTitle("New draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("labs-save-draw") }
            }
            .sheet(isPresented: $pickingMarker) {
                MarkerPicker(catalogue: catalogue) { results.append(PendingResult(marker: $0)) }
            }
            .errorAlert($errorMessage)
            .onAppear { date = BodyDates.date(from: today) }
        }
    }

    private func answer(_ title: String, _ value: Binding<Answer>) -> some View {
        Picker(title, selection: value) {
            ForEach(Answer.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
    }

    private func save() {
        let blank = { (text: String) -> String? in text.trimmingCharacters(in: .whitespaces).isEmpty ? nil : text.trimmingCharacters(in: .whitespaces) }
        let draft = LabDrawDraft(date: BodyDates.day(from: date), time: blank(time), lab: blank(lab), fastedHours: PendingResult.number(fastedHours),
                                 trainedHard72h: trained.value, alcohol5d: alcohol.value, biotinStopped: biotin.value,
                                 ironStopped: iron.value, illRecently: ill.value, note: blank(note))
        do {
            try ResultFields.validate(results)
            let drawID = try draws.addDraw(draft)
            try ResultFields.save(results, drawID: drawID, draws: draws)
            dismiss()
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }
}

struct ResultFields: View {
    @Binding var row: PendingResult
    @State private var showRange = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.marker.name).font(.system(size: 14, weight: .semibold))
            HStack {
                TextField("Value", text: $row.value).keyboardType(.decimalPad).accessibilityIdentifier("labs-result-value")
                if row.marker.units.count > 1 {
                    Picker("Unit", selection: $row.unit) {
                        ForEach(row.marker.units, id: \.unit) { Text($0.unit).tag($0.unit) }
                    }
                    .labelsHidden()
                } else if row.marker.units.isEmpty {
                    TextField("Unit", text: $row.unit).frame(width: 90)
                } else {
                    Text(row.unit).foregroundColor(Theme.muted)
                }
            }
            if row.marker.needsLabRange || showRange {
                if row.marker.needsLabRange {
                    Text("The vault reads this against your lab's own range.").font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                HStack {
                    TextField("Lab low", text: $row.labLow).keyboardType(.decimalPad)
                    TextField("Lab high", text: $row.labHigh).keyboardType(.decimalPad)
                }
            } else {
                Button("Add the lab's range") { showRange = true }.font(.system(size: 12))
            }
        }
    }

    static func validate(_ rows: [PendingResult]) throws {
        for row in rows where PendingResult.number(row.value) == nil {
            throw ValidationError("Type a number for \(row.marker.name), or swipe the row away")
        }
    }

    static func save(_ rows: [PendingResult], drawID: Int, draws: LabDrawService) throws {
        for row in rows {
            guard let value = PendingResult.number(row.value) else { continue }
            _ = try draws.addResult(drawID: drawID, markerID: row.marker.id, value: value, unit: row.unit,
                                    labLow: PendingResult.number(row.labLow), labHigh: PendingResult.number(row.labHigh))
        }
    }
}

struct MarkerPicker: View {
    /// Measured markers, plus formula ones a lab may print itself (globulin, A/G); the rest are only ever worked out.
    static func typeable(_ marker: LabMarker) -> Bool { !marker.computed || marker.formula != nil }

    let catalogue: LabCatalogue
    let picked: (LabMarker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List((search.isEmpty ? catalogue.markers : catalogue.search(search)).filter(Self.typeable)) { marker in
                Button {
                    picked(marker)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(marker.name).foregroundColor(Theme.text)
                        Text(marker.chapter).font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Marker name")
            .navigationTitle("Pick a marker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// One draw: how it was taken and each result read against the vault.
struct DrawDetailView: View {
    @ObservedObject var model: LabsModel
    let draw: LabDraw
    @Environment(\.dismiss) private var dismiss
    @State private var results: [LabResult] = []
    @State private var pending: [PendingResult] = []
    @State private var pickingMarker = false
    @State private var confirmingDelete = false

    var body: some View {
        List {
            Section("Draw") {
                row("Date", Format.longDate(draw.draft.date))
                if let time = draw.draft.time { row("Time", time) }
                if let lab = draw.draft.lab { row("Lab", lab) }
                if let hours = draw.draft.fastedHours { row("Fasted", "\(Format.number(hours)) h") }
                prep("Hard training (72 h)", draw.draft.trainedHard72h)
                prep("Alcohol (5 days)", draw.draft.alcohol5d)
                prep("Biotin stopped", draw.draft.biotinStopped)
                prep("Iron stopped", draw.draft.ironStopped)
                prep("Ill recently", draw.draft.illRecently)
                if let note = draw.draft.note { Text(note).font(.system(size: 13)) }
            }
            Section("Results") {
                ForEach(results) { result in resultRow(result).deleteDisabled(result.isCalculated) }
                    .onDelete { offsets in
                        for index in offsets { perform { try model.draw.deleteResult(results[index].id) } }
                    }
            }
            if !pending.isEmpty {
                Section("New results") {
                    ForEach($pending) { $row in ResultFields(row: $row) }
                        .onDelete { pending.remove(atOffsets: $0) }
                    Button("Save new results", action: savePending).accessibilityIdentifier("labs-save-results")
                }
            }
            Section {
                Button("+ Add a result") { pickingMarker = true }
                Button("Delete this draw", role: .destructive) { confirmingDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(Format.longDate(draw.draft.date))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .sheet(isPresented: $pickingMarker) { MarkerPicker(catalogue: model.catalogue) { pending.append(PendingResult(marker: $0)) } }
        .confirmationDialog("Delete this draw and all its results?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                perform { try model.draw.deleteDraw(draw.id) }
                dismiss()
            }
        }
        .errorAlert($model.errorMessage)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).foregroundColor(Theme.muted) }
    }

    @ViewBuilder
    private func prep(_ title: String, _ value: Bool?) -> some View {
        if let value { row(title, value ? "Yes" : "No") }
    }

    @ViewBuilder
    private func resultRow(_ result: LabResult) -> some View {
        if let marker = model.catalogue.marker(result.markerID) {
            NavigationLink { MarkerDetailView(model: model, marker: marker) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(marker.name)
                        if result.isCalculated { Text("Calculated from this draw").font(.system(size: 11)).foregroundColor(Theme.muted) }
                        if result.labLow != nil || result.labHigh != nil {
                            Text("Lab range \(result.labLow.map { Format.number($0) } ?? "…")–\(result.labHigh.map { Format.number($0) } ?? "…")")
                                .font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                    }
                    Spacer()
                    Text("\(Format.number(result.value)) \(result.unit)").foregroundColor(Theme.muted)
                    LabStatusPill(status: LabReader.read(value: result.value, unit: result.unit, marker: marker, sex: model.sex).status)
                }
            }
        }
    }

    private func reload() {
        results = (try? model.draw.results(inDraw: draw.id)) ?? []
    }

    private func savePending() {
        do {
            try ResultFields.validate(pending)
            try ResultFields.save(pending, drawID: draw.id, draws: model.draw)
            pending = []
            reload()
            model.load()
        } catch {
            model.errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            reload()
            model.load()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

/// Applies the owner's past lab results, bundled as output/lab-history.csv. Applying again adds nothing new.
struct LabHistoryCard: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var status: String?

    static var bundledFile: URL? { Bundle.main.url(forResource: "lab-history", withExtension: "csv") }

    var body: some View {
        if let url = Self.bundledFile, let catalogue = services.labCatalogue {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Lab history")
                Text("Your past blood tests, typed in from the lab reports. Shows up in Body → Bloodwork.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Apply lab history") { apply(url, catalogue) }
                    .buttonStyle(PrimaryButtonStyle(ghost: true))
                    .accessibilityIdentifier("apply-lab-history")
                if let status { Text(status).font(.system(size: 12)).foregroundColor(Theme.green).fixedSize(horizontal: false, vertical: true) }
            }
            .card()
        }
    }

    private func apply(_ url: URL, _ catalogue: LabCatalogue) {
        do {
            let result = try LabHistoryImporter(services.db, catalogue: catalogue).apply(try String(contentsOf: url, encoding: .utf8))
            let skipped = result.skipped.isEmpty ? "" : " Skipped \(result.skipped.count) rows."
            status = "Added \(result.drawsAdded) draws and \(result.resultsAdded) results.\(skipped)"
            session.didChange()
        } catch {
            status = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }
}
