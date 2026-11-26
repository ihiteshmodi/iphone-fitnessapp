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

    init(existing: LabResult, marker: LabMarker) {
        self.marker = marker
        value = Format.number(existing.value, maxDecimals: 4)
        secondaryValue = existing.secondaryValue.map { Format.number($0, maxDecimals: 4) } ?? ""
        textValue = existing.textValue ?? ""
        isBelowLimit = existing.valueOperator == .belowLimit
        if let customMult = existing.customToDefault {
            unit = marker.defaultUnit ?? existing.unit
            useCustomUnit = true
            customUnit = existing.unit
            customMultiplier = Format.number(customMult, maxDecimals: 4)
        } else {
            unit = existing.unit
        }
        assay = existing.assay ?? ""
        labLow = existing.labLow.map { Format.number($0, maxDecimals: 4) } ?? ""
        labHigh = existing.labHigh.map { Format.number($0, maxDecimals: 4) } ?? ""
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
    init(_ flag: Bool?) {
        switch flag {
        case true: self = .yes
        case false: self = .no
        case nil: self = .unknown
        }
    }
}

struct AddDrawSheet: View {
    let catalogue: LabCatalogue
    let draws: LabDrawService
    let sex: LabSex
    let today: ISODate
    var existing: LabDraw?
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var time = ""
    @State private var lab = ""
    @State private var savedLabs: [String] = []
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
    @State private var loadedInitial = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Draw") {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Time (e.g. 08:15)", text: $time).keyboardType(.numbersAndPunctuation)
                    TextField("Lab", text: $lab)
                        .accessibilityIdentifier("labs-draw-lab-field")
                    if !savedLabs.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Saved labs (tap to fill)").font(.system(size: 11)).foregroundColor(Theme.muted)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(savedLabs, id: \.self) { name in
                                        let active = lab.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
                                        Button(name) { lab = name }
                                            .font(.system(size: 11, weight: .semibold))
                                            .padding(.horizontal, 10).padding(.vertical, 5)
                                            .background(active ? Theme.green.opacity(0.22) : Theme.card2)
                                            .foregroundColor(active ? Theme.green : Theme.text)
                                            .clipShape(Capsule())
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier("labs-saved-lab-\(name)")
                                    }
                                }
                            }
                        }
                    }
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
                if existing == nil {
                    Section("Results") {
                        ForEach($results) { $row in ResultFields(row: $row, sex: sex) }
                            .onDelete { results.remove(atOffsets: $0) }
                        Button("+ Add a result") { pickingMarker = true }
                            .accessibilityIdentifier("labs-add-result")
                    }
                }
            }
            .navigationTitle(existing == nil ? "New draw" : "Edit draw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).accessibilityIdentifier("labs-save-draw") }
            }
            .sheet(isPresented: $pickingMarker) {
                MarkerPicker(catalogue: catalogue, sex: sex) { results.append(PendingResult(marker: $0)) }
            }
            .errorAlert($errorMessage)
            .onAppear(perform: populateInitial)
        }
    }

    private func populateInitial() {
        savedLabs = (try? draws.savedLabNames()) ?? []
        guard !loadedInitial else { return }
        loadedInitial = true
        guard let existing else {
            date = BodyDates.date(from: today)
            return
        }
        let d = existing.draft
        date = BodyDates.date(from: d.date)
        time = d.time ?? ""
        lab = d.lab ?? ""
        fastedHours = d.fastedHours.map { Format.number($0, maxDecimals: 2) } ?? ""
        trained = Answer(d.trainedHard72h)
        alcohol = Answer(d.alcohol5d)
        biotin = Answer(d.biotinStopped)
        iron = Answer(d.ironStopped)
        ill = Answer(d.illRecently)
        poorSleep = Answer(d.poorSleep)
        acuteStress = Answer(d.acuteStress)
        recentVaccine = Answer(d.recentVaccineOrSurgery)
        cycleDay = d.cycleDay.map(String.init) ?? ""
        medsNoted = d.medsNoted ?? ""
        note = d.note ?? ""
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
                                 illRecently: ill.value, cycleDay: parsedCycle, cyclePhase: existing?.draft.cyclePhase,
                                 poorSleep: poorSleep.value, acuteStress: acuteStress.value,
                                 recentVaccineOrSurgery: recentVaccine.value, medsNoted: blank(medsNoted), note: blank(note))
        do {
            if let existing {
                try draws.updateDraw(existing.id, draft)
            } else {
                try ResultFields.validate(results)
                let drawID = try draws.addDraw(draft)
                try ResultFields.save(results, drawID: drawID, draws: draws)
            }
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
            if row.marker.needsLabRange || showRange || !row.labLow.isEmpty || !row.labHigh.isEmpty {
                if row.marker.needsLabRange {
                    Text("The vault reads this against your lab's own range.").font(.system(size: 11)).foregroundColor(Theme.muted)
                }
                HStack {
                    TextField("Lab low", text: $row.labLow).keyboardType(.decimalPad)
                        .accessibilityIdentifier("labs-result-lab-low")
                    TextField("Lab high", text: $row.labHigh).keyboardType(.decimalPad)
                        .accessibilityIdentifier("labs-result-lab-high")
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

    static func update(_ row: PendingResult, resultID: Int, specimen: String?, draws: LabDrawService) throws {
        try validate([row])
        if row.isQualitative || row.isTiter {
            let text = row.textValue.trimmingCharacters(in: .whitespaces)
            try draws.updateQualitativeResult(resultID, textValue: text, unit: row.unit, specimen: specimen)
            return
        }
        guard let value = PendingResult.number(row.value) else { return }
        let chosenUnit = row.useCustomUnit ? row.customUnit.trimmingCharacters(in: .whitespaces) : row.unit
        let customMult = row.useCustomUnit ? PendingResult.number(row.customMultiplier) : nil
        let op: LabValueOperator? = row.isBelowLimit ? .belowLimit : nil
        let secVal = row.isBloodPressure ? PendingResult.number(row.secondaryValue) : nil
        let assayVal = row.assay.isEmpty ? nil : row.assay
        try draws.updateResult(resultID, value: value, unit: chosenUnit,
                               labLow: PendingResult.number(row.labLow), labHigh: PendingResult.number(row.labHigh),
                               valueOperator: op, secondaryValue: secVal, customToDefault: customMult,
                               specimen: specimen, assay: assayVal)
    }
}

struct EditResultSheet: View {
    let existing: LabResult
    let marker: LabMarker
    let draws: LabDrawService
    let sex: LabSex
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var row: PendingResult
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    init(existing: LabResult, marker: LabMarker, draws: LabDrawService, sex: LabSex, onSaved: @escaping () -> Void) {
        self.existing = existing
        self.marker = marker
        self.draws = draws
        self.sex = sex
        self.onSaved = onSaved
        _row = State(initialValue: PendingResult(existing: existing, marker: marker))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Edit result (\(Format.longDate(existing.date)))") {
                    ResultFields(row: $row, sex: sex)
                }
                Section {
                    Button("Delete this result", role: .destructive) { confirmingDelete = true }
                        .accessibilityIdentifier("labs-delete-result")
                }
            }
            .navigationTitle("Edit \(marker.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).accessibilityIdentifier("labs-save-edit-result")
                }
            }
            .confirmationDialog("Delete \(marker.name) from this draw?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    do {
                        try draws.deleteResult(existing.id)
                        onSaved()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func save() {
        do {
            try ResultFields.update(row, resultID: existing.id, specimen: existing.specimen, draws: draws)
            onSaved()
            dismiss()
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
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
    @State private var currentDraw: LabDraw
    @State private var results: [LabResult] = []
    @State private var pending: [PendingResult] = []
    @State private var pickingMarker = false
    @State private var editingDraw = false
    @State private var editingResult: LabResult?
    @State private var confirmingDelete = false

    init(model: LabsModel, draw: LabDraw) {
        self.model = model
        self.draw = draw
        _currentDraw = State(initialValue: draw)
    }

    var body: some View {
        List {
            Section("Draw") {
                row("Date", Format.longDate(currentDraw.draft.date))
                if let time = currentDraw.draft.time { row("Time", time) }
                if let lab = currentDraw.draft.lab { row("Lab", lab) }
                if let hours = currentDraw.draft.fastedHours { row("Fasted", "\(Format.number(hours)) h") }
                prep("Hard training (72 h)", currentDraw.draft.trainedHard72h)
                prep("Alcohol (5 days)", currentDraw.draft.alcohol5d)
                prep("Biotin stopped", currentDraw.draft.biotinStopped)
                prep("Iron stopped", currentDraw.draft.ironStopped)
                prep("Ill recently", currentDraw.draft.illRecently)
                prep("Poor sleep", currentDraw.draft.poorSleep)
                prep("Acute stress", currentDraw.draft.acuteStress)
                prep("Recent vaccine / surgery", currentDraw.draft.recentVaccineOrSurgery)
                if model.sex == .female, let cd = currentDraw.draft.cycleDay { row("Cycle day", "Day \(cd)") }
                if let meds = currentDraw.draft.medsNoted { row("Medications", meds) }
                if let note = currentDraw.draft.note { Text(note).font(.system(size: 13)) }
            }
            Section("Results") {
                ForEach(results) { result in
                    resultRow(result)
                        .deleteDisabled(result.isCalculated)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !result.isCalculated {
                                Button("Edit") { editingResult = result }
                                    .tint(Theme.green)
                            }
                        }
                }
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
                Button("Edit draw details") { editingDraw = true }
                    .accessibilityIdentifier("labs-edit-draw-row")
                Button("+ Add a result") { pickingMarker = true }
                Button("Delete this draw", role: .destructive) { confirmingDelete = true }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(Format.longDate(currentDraw.draft.date))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") { editingDraw = true }
                    .accessibilityIdentifier("labs-edit-draw")
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $pickingMarker) { MarkerPicker(catalogue: model.catalogue, sex: model.sex) { pending.append(PendingResult(marker: $0)) } }
        .sheet(isPresented: $editingDraw, onDismiss: {
            reload()
            model.load()
        }) {
            AddDrawSheet(catalogue: model.catalogue, draws: model.draw, sex: model.sex, today: model.today, existing: currentDraw)
        }
        .sheet(item: $editingResult) { target in
            if let marker = model.catalogue.marker(target.markerID) {
                EditResultSheet(existing: target, marker: marker, draws: model.draw, sex: model.sex) {
                    reload()
                    model.load()
                }
            }
        }
        .confirmationDialog("Delete this draw and all its results?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                perform { try model.draw.deleteDraw(currentDraw.id) }
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
            let reading = LabReader.read(result: result, marker: marker, preferences: prefs, draw: currentDraw.draft, genotypes: model.genotypes)
            let warnings = LabValidityGate.evaluate(result: result, marker: marker, draw: currentDraw.draft,
                                                    sameDrawResults: results, catalogue: model.catalogue, sex: model.sex)
            let bar = LabRangeBarModel.build(marker: marker, sex: model.sex, reading: reading, latestResult: result,
                                             genotypes: model.genotypes, preferences: prefs)
            HStack(spacing: 8) {
                NavigationLink { MarkerDetailView(model: model, marker: marker) } label: {
                    VStack(alignment: .leading, spacing: 5) {
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
                                if let firstGene = reading.geneticNotes.first {
                                    Text(firstGene).font(.system(size: 11)).foregroundColor(Theme.green).lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(formattedResultText(result)).foregroundColor(Theme.muted)
                            LabStatusPill(status: reading.status)
                        }
                        if let bar {
                            MarkerMiniRangeBar(bar: bar, status: reading.status)
                        }
                    }
                }
                if !result.isCalculated {
                    Button { editingResult = result } label: {
                        Image(systemName: "pencil.circle")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.green)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Edit \(marker.name)")
                    .accessibilityIdentifier("labs-edit-result-\(result.markerID)")
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
        if let fresh = (try? model.draw.draws())?.first(where: { $0.id == draw.id }) {
            currentDraw = fresh
        }
        results = (try? model.draw.results(inDraw: draw.id)) ?? []
    }

    private func savePending() {
        do {
            try ResultFields.validate(pending)
            try ResultFields.save(pending, drawID: currentDraw.id, draws: model.draw)
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
