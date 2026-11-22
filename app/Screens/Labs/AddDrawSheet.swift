import FitnessCore
import SwiftUI

/// One result being typed: the unit comes from the catalogue, and the lab's own range is asked for where the vault needs it (D8).
struct PendingResult: Identifiable {
    let id = UUID()
    let marker: LabMarker
    var value = ""
    var secondaryValue = ""
    var textValue = ""
    var isBelowLimit = false
    var unit: String
    var useCustomUnit = false
    var customUnit = ""
    var customMultiplier = ""
    var assay = ""
    var labLow = ""
    var labHigh = ""

    init(marker: LabMarker) {
        self.marker = marker
        unit = marker.defaultUnit ?? ""
    }

    var isBloodPressure: Bool { marker.id == "blood-pressure" }
    var isQualitative: Bool { marker.units.isEmpty && marker.bands.contains { ($0.values?.isEmpty == false) } }
    var isTiter: Bool { marker.defaultUnit?.lowercased().contains("titer") == true }

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
    let sex: LabSex
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
    @State private var poorSleep = Answer.unknown
    @State private var acuteStress = Answer.unknown
    @State private var recentVaccine = Answer.unknown
    @State private var cycleDay = ""
    @State private var medsNoted = ""
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
                    answer("Poor sleep night before", $poorSleep)
                    answer("Acute stress before draw", $acuteStress)
                    answer("Recent vaccine / surgery", $recentVaccine)
                    if sex == .female {
                        TextField("Menstrual cycle day (optional)", text: $cycleDay).keyboardType(.numberPad)
                            .accessibilityIdentifier("labs-cycle-day")
                    }
                    TextField("Medications / supplements taken", text: $medsNoted)
                    TextField("Note", text: $note)
                }
                Section("Results") {
                    ForEach($results) { $row in ResultFields(row: $row, sex: sex) }
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
                MarkerPicker(catalogue: catalogue, sex: sex) { results.append(PendingResult(marker: $0)) }
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
        let parsedCycle = sex == .female ? Int(cycleDay.trimmingCharacters(in: .whitespaces)) : nil
        let draft = LabDrawDraft(date: BodyDates.day(from: date), time: blank(time), lab: blank(lab),
                                 fastedHours: PendingResult.number(fastedHours), trainedHard72h: trained.value,
                                 alcohol5d: alcohol.value, biotinStopped: biotin.value, ironStopped: iron.value,
                                 illRecently: ill.value, cycleDay: parsedCycle, poorSleep: poorSleep.value,
                                 acuteStress: acuteStress.value, recentVaccineOrSurgery: recentVaccine.value,
                                 medsNoted: blank(medsNoted), note: blank(note))
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
    let sex: LabSex
    @State private var showRange = false
    @State private var showAssay = false

    private var scaleSuggestion: LabScaleSuggestion? {
        guard !row.useCustomUnit, !row.isQualitative, !row.isTiter, let num = PendingResult.number(row.value) else { return nil }
        return LabUnitScaler.checkScaleMismatch(value: num, unit: row.unit, marker: row.marker, sex: sex)
    }

    private var qualitativeOptions: [String] {
        let fromBands = row.marker.visibleBands(for: sex).flatMap { $0.values ?? [] }
        return fromBands.isEmpty ? ["Negative", "Trace", "1+", "2+", "3+"] : Array(Set(fromBands)).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.marker.name).font(.system(size: 14, weight: .semibold))
            if let hint = LabUnitScaler.expectedHint(for: row.marker, sex: sex) {
                Text(hint.summary).font(.system(size: 11)).foregroundColor(Theme.muted)
            }
            if row.isQualitative || row.isTiter {
                qualitativeEditor
            } else if row.isBloodPressure {
                HStack {
                    TextField("Systolic", text: $row.value).keyboardType(.decimalPad).accessibilityIdentifier("labs-result-value")
                    Text("/").foregroundColor(Theme.muted)
                    TextField("Diastolic", text: $row.secondaryValue).keyboardType(.decimalPad).accessibilityIdentifier("labs-bp-diastolic")
                    Text("mmHg").foregroundColor(Theme.muted)
                }
            } else {
                numericEditor
            }
            if let suggestion = scaleSuggestion {
                scaleWarningCard(suggestion)
            }
            if !row.isQualitative {
                extraOptionsRow
            }
            if row.marker.needsLabRange || showRange {
                if row.marker.needsLabRange {
                    Text("The vault reads this against your lab's own range.").font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                HStack {
                    TextField("Lab low", text: $row.labLow).keyboardType(.decimalPad)
                    TextField("Lab high", text: $row.labHigh).keyboardType(.decimalPad)
                }
            }
        }
    }

    private var qualitativeEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(row.isTiter ? "Result (e.g. Negative or 1:80)" : "Result (e.g. Negative, Trace, 1+)", text: $row.textValue)
                .accessibilityIdentifier("labs-result-value")
            if !row.isTiter {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(qualitativeOptions, id: \.self) { opt in
                            Button(opt) { row.textValue = opt }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(row.textValue == opt ? Theme.green.opacity(0.2) : Theme.card2)
                                .foregroundColor(row.textValue == opt ? Theme.green : Theme.muted)
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var numericEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(row.isBelowLimit ? "< LOD" : "=") { row.isBelowLimit.toggle() }
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(row.isBelowLimit ? Theme.amber.opacity(0.2) : Theme.card2)
                    .foregroundColor(row.isBelowLimit ? Theme.amber : Theme.muted)
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("labs-below-limit-toggle")
                TextField("Value", text: $row.value).keyboardType(.decimalPad).accessibilityIdentifier("labs-result-value")
                if row.useCustomUnit {
                    TextField("Unit", text: $row.customUnit).frame(width: 80).accessibilityIdentifier("labs-custom-unit")
                } else if row.marker.units.count > 1 {
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
            if row.useCustomUnit {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Multiplier to \(row.marker.defaultUnit ?? "default") (e.g. 10 or 0.1)", text: $row.customMultiplier)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 12))
                        .accessibilityIdentifier("labs-custom-multiplier")
                    HStack(spacing: 6) {
                        ForEach([("×10", "10"), ("×100", "100"), ("×1000", "1000"), ("÷10", "0.1"), ("÷100", "0.01"), ("÷1000", "0.001")], id: \.0) { label, val in
                            Button(label) { row.customMultiplier = val }
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Theme.card2).foregroundColor(Theme.green).clipShape(Capsule())
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func scaleWarningCard(_ suggestion: LabScaleSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(suggestion.message).font(.system(size: 11)).foregroundColor(Theme.amber)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let targetUnit = suggestion.suggestedUnit {
                    Button("Switch unit to \(targetUnit)") { row.unit = targetUnit }
                        .font(.system(size: 11, weight: .bold)).foregroundColor(Theme.green)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("labs-switch-suggested-unit")
                }
                Button("Custom unit scale") {
                    row.useCustomUnit = true
                    row.customUnit = row.unit
                    row.customMultiplier = Format.number(suggestion.suggestedFactor, maxDecimals: 4)
                }
                .font(.system(size: 11)).foregroundColor(Theme.muted)
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(Theme.amber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var extraOptionsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if !row.marker.needsLabRange && !showRange {
                    Button("Add lab's range") { showRange = true }.font(.system(size: 11)).buttonStyle(.plain)
                }
                Button(row.useCustomUnit ? "Use listed unit" : "Other lab unit") {
                    row.useCustomUnit.toggle()
                }
                .font(.system(size: 11)).foregroundColor(Theme.muted).buttonStyle(.plain)
                .accessibilityIdentifier("labs-other-unit-toggle")
                if !row.marker.specimens.isEmpty {
                    Button(showAssay ? "Hide assay" : "Assay method") { showAssay.toggle() }
                        .font(.system(size: 11)).foregroundColor(Theme.muted).buttonStyle(.plain)
                }
            }
            if showAssay {
                Picker("Assay", selection: $row.assay) {
                    Text("Unspecified").tag("")
                    Text("LC-MS/MS").tag("lc-ms-ms")
                    Text("Equilibrium dialysis").tag("equilibrium-dialysis")
                    Text("Standard immunoassay").tag("immunoassay")
                }
                .font(.system(size: 12))
            }
        }
    }

    static func validate(_ rows: [PendingResult]) throws {
        for row in rows {
            if row.isQualitative || row.isTiter {
                if row.textValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    throw ValidationError("Enter a result for \(row.marker.name), or swipe the row away")
                }
                continue
            }
            guard PendingResult.number(row.value) != nil else {
                throw ValidationError("Type a number for \(row.marker.name), or swipe the row away")
            }
            if row.isBloodPressure, !row.secondaryValue.trimmingCharacters(in: .whitespaces).isEmpty,
               PendingResult.number(row.secondaryValue) == nil {
                throw ValidationError("Type a number for diastolic blood pressure")
            }
            if row.useCustomUnit {
                guard !row.customUnit.trimmingCharacters(in: .whitespaces).isEmpty,
                      let mult = PendingResult.number(row.customMultiplier), mult > 0 else {
                    throw ValidationError("Enter both the custom unit name and a positive multiplier for \(row.marker.name)")
                }
            }
        }
    }

    static func save(_ rows: [PendingResult], drawID: Int, draws: LabDrawService) throws {
        for row in rows {
            if row.isQualitative || row.isTiter {
                let text = row.textValue.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                _ = try draws.addQualitativeResult(drawID: drawID, markerID: row.marker.id, textValue: text, unit: row.unit)
                continue
            }
            guard let value = PendingResult.number(row.value) else { continue }
            let chosenUnit = row.useCustomUnit ? row.customUnit.trimmingCharacters(in: .whitespaces) : row.unit
            let customMult = row.useCustomUnit ? PendingResult.number(row.customMultiplier) : nil
            let op: LabValueOperator? = row.isBelowLimit ? .belowLimit : nil
            let secVal = row.isBloodPressure ? PendingResult.number(row.secondaryValue) : nil
            let assayVal = row.assay.isEmpty ? nil : row.assay
            _ = try draws.addResult(drawID: drawID, markerID: row.marker.id, value: value, unit: chosenUnit,
                                    labLow: PendingResult.number(row.labLow), labHigh: PendingResult.number(row.labHigh),
                                    valueOperator: op, secondaryValue: secVal, customToDefault: customMult, assay: assayVal)
        }
    }
}

struct MarkerPicker: View {
    /// Measured markers, plus formula ones a lab may print itself (globulin, A/G); overviews and pure derived markers are excluded.
    static func typeable(_ marker: LabMarker) -> Bool { !marker.isOverview && (!marker.computed || marker.formula != nil) }

    let catalogue: LabCatalogue
    let sex: LabSex
    let picked: (LabMarker) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        let pool = search.isEmpty ? catalogue.visibleMarkers(for: sex) : catalogue.search(search).filter { $0.applies(to: sex) }
        NavigationStack {
            List(pool.filter(Self.typeable)) { marker in
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
                prep("Poor sleep", draw.draft.poorSleep)
                prep("Acute stress", draw.draft.acuteStress)
                prep("Recent vaccine / surgery", draw.draft.recentVaccineOrSurgery)
                if model.sex == .female, let cd = draw.draft.cycleDay { row("Cycle day", "Day \(cd)") }
                if let meds = draw.draft.medsNoted { row("Medications", meds) }
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
                    ForEach($pending) { $row in ResultFields(row: $row, sex: model.sex) }
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
        .sheet(isPresented: $pickingMarker) { MarkerPicker(catalogue: model.catalogue, sex: model.sex) { pending.append(PendingResult(marker: $0)) } }
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
            let prefs = model.preferences ?? LabPreferences(sex: model.sex)
            let reading = LabReader.read(result: result, marker: marker, preferences: prefs, draw: draw.draft)
            let warnings = LabValidityGate.evaluate(result: result, marker: marker, draw: draw.draft,
                                                    sameDrawResults: results, catalogue: model.catalogue, sex: model.sex)
            NavigationLink { MarkerDetailView(model: model, marker: marker) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(marker.name)
                        if result.isCalculated { Text("Calculated from this draw").font(.system(size: 11)).foregroundColor(Theme.muted) }
                        if result.labLow != nil || result.labHigh != nil {
                            Text("Lab range \(result.labLow.map { Format.number($0) } ?? "…")–\(result.labHigh.map { Format.number($0) } ?? "…")")
                                .font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                        if let firstWarn = warnings.first {
                            Text(firstWarn.title).font(.system(size: 11)).foregroundColor(Theme.amber)
                        }
                    }
                    Spacer()
                    Text(formattedResultText(result)).foregroundColor(Theme.muted)
                    LabStatusPill(status: reading.status)
                }
            }
        }
    }

    private func formattedResultText(_ result: LabResult) -> String {
        if let text = result.textValue { return text }
        if let sec = result.secondaryValue { return "\(Format.number(result.value))/\(Format.number(sec)) \(result.unit)" }
        let prefix = result.valueOperator == .belowLimit ? "< " : ""
        return "\(prefix)\(Format.number(result.value)) \(result.unit)"
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
