import Charts
import FitnessCore
import SwiftUI

@MainActor
final class LabsModel: ObservableObject {
    @Published private(set) var dashboard: LabDashboard?
    @Published private(set) var draws: [LabDraw] = []
    @Published private(set) var resultCounts: [Int: Int] = [:]
    @Published private(set) var doctorItems: [Insight] = []
    @Published private(set) var preferences: LabPreferences?
    @Published var errorMessage: String?

    let services: Services
    let catalogue: LabCatalogue
    let draw: LabDrawService

    init(services: Services, catalogue: LabCatalogue) {
        self.services = services
        self.catalogue = catalogue
        draw = LabDrawService(services.db, catalogue: catalogue)
    }

    var today: ISODate { services.clock.today() }
    var sex: LabSex { preferences?.sex ?? .male }
    var showDrugNotes: Bool { preferences?.showDrugNotes ?? false }

    func load() {
        do {
            preferences = try services.labSettings.load()
            dashboard = try LabDashboard.build(catalogue: catalogue, db: services.db, today: today)
            draws = try draw.draws()
            var counts: [Int: Int] = [:]
            for item in draws { counts[item.id] = try draw.results(inDraw: item.id).count }
            resultCounts = counts
            doctorItems = try services.insights.labs(on: today).filter { $0.ruleID.hasPrefix("lab-doctor-") }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismiss(_ item: Insight) {
        do {
            try services.insights.dismiss(item)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Opens Blood Labs from the Body tab; hidden when the build has no catalogue.
struct LabsEntryCard: View {
    @EnvironmentObject private var services: Services

    var body: some View {
        if let catalogue = services.labCatalogue {
            NavigationLink { LabsView(services: services, catalogue: catalogue) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Bloodwork").font(.system(size: 16, weight: .semibold)).foregroundColor(Theme.text)
                        Text("Results, biological age, what to order next, genetics")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(Theme.muted)
                }
                .card()
            }
            .accessibilityIdentifier("labs-entry")
        }
    }
}

/// Blood Labs: doctor alerts first, then the dashboard, biological age, heart, hormones and every draw.
struct LabsView: View {
    @StateObject private var model: LabsModel
    @State private var addingDraw = false
    @State private var editingSettings = false
    @State private var exportURL: URL?

    init(services: Services, catalogue: LabCatalogue) {
        _model = StateObject(wrappedValue: LabsModel(services: services, catalogue: catalogue))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(model.doctorItems) { doctorBanner($0) }
                actions
                if let dashboard = model.dashboard {
                    biologicalAgeCard(dashboard.biologicalAge, from: dashboard.biologicalAgeDraw)
                    if !dashboard.systems.isEmpty { systemsSection(dashboard.systems) }
                    heartCard(dashboard.heart)
                    hormonesSection(dashboard.hormones.filter { !$0.points.isEmpty })
                }
                drawsSection
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Bloodwork")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 14) {
                    Button(action: export) { Image(systemName: "square.and.arrow.up") }
                        .accessibilityLabel("Export labs for AI review")
                        .accessibilityIdentifier("labs-export-button")
                    Button { editingSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityIdentifier("labs-settings-button")
                }
            }
        }
        .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } })) {
            if let exportURL { ShareSheet(items: [exportURL]) }
        }
        .onAppear { model.load() }
        .sheet(isPresented: $addingDraw, onDismiss: model.load) {
            AddDrawSheet(catalogue: model.catalogue, draws: model.draw, today: model.today)
        }
        .sheet(isPresented: $editingSettings, onDismiss: model.load) {
            LabsSettingsSheet(settings: model.services.labSettings)
        }
        .errorAlert($model.errorMessage)
    }

    /// Writes every draw and open item to labs-review-<date>.md for the labs-review skill.
    private func export() {
        do {
            let text = try LabsReviewService(model.services.db, catalogue: model.catalogue)
                .markdown(on: model.today, insights: try model.services.insights.labs(on: model.today))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("labs-review-\(model.today.string).md")
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    private func doctorBanner(_ item: Insight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "cross.case.fill").foregroundColor(Theme.red)
                Text(item.title).font(.system(size: 15, weight: .semibold)).foregroundColor(Theme.red)
            }
            Text(item.detail).font(.system(size: 13)).foregroundColor(Theme.text).fixedSize(horizontal: false, vertical: true)
            Button("Dismiss") { model.dismiss(item) }
                .buttonStyle(CompactButtonStyle())
                .accessibilityIdentifier("labs-doctor-dismiss")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(highlighted: true)
        .accessibilityIdentifier("labs-doctor-banner")
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button("+ Add a draw") { addingDraw = true }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("labs-add-draw")
            HStack(spacing: 8) {
                NavigationLink("Plan draw") {
                    PlanDrawView(catalogue: model.catalogue, draws: model.draw, sex: model.sex,
                                 genetics: model.services.genetics, today: model.today)
                }
                .accessibilityIdentifier("labs-plan-draw")
                NavigationLink("Markers") { MarkerLibraryView(model: model) }
                    .accessibilityIdentifier("labs-marker-library")
                NavigationLink("Genetics") { GeneticsView(catalogue: model.catalogue, services: model.services) }
                    .accessibilityIdentifier("labs-genetics")
            }
            .buttonStyle(PrimaryButtonStyle(ghost: true))
            .font(.system(size: 13))
        }
    }

    @ViewBuilder
    private func biologicalAgeCard(_ outcome: PhenoAgeOutcome?, from draw: ISODate?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Biological age (PhenoAge)")
            switch outcome {
            case .calculated(let result):
                let gap = result.phenoAge - result.ageYears
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.number(result.phenoAge, maxDecimals: 1)).font(.system(size: 34, weight: .bold)).foregroundColor(Theme.text)
                    Text("years").foregroundColor(Theme.muted)
                    Spacer()
                    Pill(text: "\(gap <= 0 ? "" : "+")\(Format.number(gap, maxDecimals: 1)) y", tone: gap <= 0 ? .green : .amber)
                }
                Text("Calendar age at the \(draw.map(Format.longDate) ?? "") draw: \(Format.number(result.ageYears, maxDecimals: 1))")
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
                if result.isEstimate {
                    Text("hs-CRP was below the detection limit, so it was estimated (limit ÷ √2).")
                        .font(.system(size: 12)).foregroundColor(Theme.amber)
                }
            case .missing(let inputs):
                Text("Needs one draw with all ten inputs. Your closest draw (\(draw.map(Format.longDate) ?? "none yet")) is missing:")
                    .font(.system(size: 13)).foregroundColor(Theme.text)
                Text(inputs.map(inputName).joined(separator: ", ")).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amber)
            case nil:
                Text("Set your date of birth in settings (gear, top right) to work out biological age.")
                    .font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            Text("Research (owner-approved): Levine et al. 2018. The vault names the inputs but gives no formula.")
                .font(.system(size: 11)).foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-biological-age")
    }

    private func inputName(_ input: PhenoAgeInput) -> String {
        guard let id = input.marker?.id else { return "Age" }
        return model.catalogue.marker(id)?.name ?? id
    }

    private func systemsSection(_ tiles: [SystemTile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("By system")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(tiles, id: \.chapter) { tile in
                    NavigationLink { MarkerLibraryView(model: model, chapter: tile.chapter) } label: { systemTile(tile) }
                }
            }
        }
    }

    private func systemTile(_ tile: SystemTile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.chapter).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                .lineLimit(2).multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            HStack(spacing: 4) {
                countBadge(tile.optimal, Theme.green)
                countBadge(tile.disputed, Theme.amber)
                countBadge(tile.outside, Theme.gold)
                countBadge(tile.doctor, Theme.red)
            }
            if tile.trend.count > 1 { Sparkline(points: tile.trend).frame(height: 28) }
            Text("\(tile.tested) tested\(tile.lastTested.map { " · \(Format.longDate($0))" } ?? "")")
                .font(.system(size: 11)).foregroundColor(Theme.muted)
            if tile.retestsDue > 0 {
                Text("\(tile.retestsDue) retest\(tile.retestsDue == 1 ? "" : "s") due").font(.system(size: 11)).foregroundColor(Theme.amber)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
    }

    @ViewBuilder
    private func countBadge(_ count: Int, _ color: Color) -> some View {
        if count > 0 {
            Text("\(count)").font(.system(size: 11, weight: .bold)).foregroundColor(color)
                .padding(.horizontal, 6).padding(.vertical, 2).background(color.opacity(0.15)).clipShape(Capsule())
        }
    }

    private func heartCard(_ items: [HeartItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Heart risk")
            ForEach(items, id: \.marker.id) { item in
                NavigationLink { MarkerDetailView(model: model, marker: item.marker) } label: {
                    HStack {
                        Text(item.marker.name).font(.system(size: 14)).foregroundColor(Theme.text)
                        Spacer()
                        if let latest = item.latest {
                            Text("\(Format.number(latest.value)) \(latest.unit)").font(.system(size: 13)).foregroundColor(Theme.muted)
                            if let reading = item.reading { LabStatusPill(status: reading.status) }
                        } else {
                            Pill(text: "Not tested", tone: .grey)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func hormonesSection(_ series: [MarkerSeries]) -> some View {
        if !series.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Hormones over time")
                ForEach(series, id: \.marker.id) { line in
                    NavigationLink { MarkerDetailView(model: model, marker: line.marker) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(line.marker.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                                Spacer()
                                if let last = line.points.last {
                                    Text("\(Format.number(last.value)) \(line.marker.defaultUnit ?? "")")
                                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                                    if line.points.count == 1 { Text(Format.longDate(last.date)).font(.system(size: 11)).foregroundColor(Theme.muted) }
                                }
                            }
                            if line.points.count > 1 { LabTrendChart(points: line.points).frame(height: 90) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private var drawsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Draws")
            if model.draws.isEmpty {
                Text("No draws yet. Add one, or apply your lab history from More.").font(.system(size: 13)).foregroundColor(Theme.muted)
            }
            ForEach(model.draws) { draw in
                NavigationLink { DrawDetailView(model: model, draw: draw) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Format.longDate(draw.draft.date)).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                            if let lab = draw.draft.lab { Text(lab).font(.system(size: 12)).foregroundColor(Theme.muted) }
                        }
                        Spacer()
                        Text("\(model.resultCounts[draw.id] ?? 0) results").font(.system(size: 12)).foregroundColor(Theme.muted)
                        Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }
                .accessibilityIdentifier("labs-draw-row")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct LabStatusPill: View {
    let status: LabStatus

    var body: some View {
        switch status {
        case .optimal: Pill(text: "Optimal", tone: .green)
        case .disputed: Pill(text: "Disputed zone", tone: .amber)
        case .low: Pill(text: "Low", tone: .gold)
        case .high: Pill(text: "High", tone: .gold)
        case .noOptimalBand: Pill(text: "No optimal band", tone: .grey)
        case .notComparable: Pill(text: "Unit not comparable", tone: .grey)
        }
    }
}

struct Sparkline: View {
    let points: [TrendPoint]

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { index, point in
            LineMark(x: .value("Draw", index), y: .value("Value", point.value)).foregroundStyle(Theme.green)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
    }
}

struct LabTrendChart: View {
    let points: [TrendPoint]

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            LineMark(x: .value("Date", point.date.string), y: .value("Value", point.value)).foregroundStyle(Theme.green)
            PointMark(x: .value("Date", point.date.string), y: .value("Value", point.value)).foregroundStyle(Theme.green)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let text = value.as(String.self), let day = ISODate(text) { Text(Format.monthYear(day)).font(.system(size: 9)) }
                }
            }
        }
    }
}

enum LabCopy {
    static func origin(_ origin: LabOrigin?) -> String? {
        switch origin {
        case .research: return "Research (owner-approved)"
        case .owner: return "Owner decision"
        case .vault, nil: return nil
        }
    }

    static func range(_ band: LabBand) -> String {
        if let values = band.values, !values.isEmpty { return values.joined(separator: ", ") }
        let unit = band.unit.map { " \($0)" } ?? ""
        switch (band.low, band.high) {
        case let (low?, high?): return "\(Format.number(low))–\(Format.number(high))\(unit)"
        case let (low?, nil): return "\(band.lowInclusive == false ? ">" : "≥") \(Format.number(low))\(unit)"
        case let (nil, high?): return "\(band.highInclusive == false ? "<" : "≤") \(Format.number(high))\(unit)"
        case (nil, nil): return "—"
        }
    }

    static func tagNote(_ tag: String?) -> String? {
        switch tag {
        case "female": return "Women only"
        case "drug": return "Drug / TRT note"
        default: return nil
        }
    }
}

struct LabsSettingsSheet: View {
    let settings: LabSettings
    @Environment(\.dismiss) private var dismiss
    @State private var sex = LabSex.male
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var showDrugNotes = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Sex (picks the bands)", selection: $sex) {
                    Text("Male").tag(LabSex.male)
                    Text("Female").tag(LabSex.female)
                }
                Toggle("Date of birth set", isOn: $hasBirthDate)
                if hasBirthDate { DatePicker("Date of birth", selection: $birthDate, displayedComponents: .date) }
                Toggle("Show drug and TRT notes", isOn: $showDrugNotes)
                    .accessibilityIdentifier("labs-drug-notes-toggle")
            }
            .navigationTitle("Labs settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: load)
            .errorAlert($errorMessage)
        }
    }

    private func load() {
        guard let prefs = try? settings.load() else { return }
        sex = prefs.sex == .female ? .female : .male
        hasBirthDate = prefs.birthDate != nil
        birthDate = prefs.birthDate.map(BodyDates.date(from:)) ?? birthDate
        showDrugNotes = prefs.showDrugNotes
    }

    private func save() {
        do {
            try settings.setSex(sex)
            try settings.setBirthDate(hasBirthDate ? BodyDates.day(from: birthDate) : nil)
            try settings.setShowDrugNotes(showDrugNotes)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
