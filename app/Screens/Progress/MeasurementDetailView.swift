import FitnessCore
import SwiftUI

@MainActor
final class MeasurementDetailViewModel: ObservableObject {
    @Published private(set) var detail: MeasurementDetail?
    @Published private(set) var loadError: String?

    let site: String
    private let services: Services

    init(site: String, services: Services) {
        self.site = site
        self.services = services
    }

    var today: ISODate { services.clock.today() }

    func load() {
        do {
            detail = try services.measurements.detail(site: site)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Newest first, for the readings list.
    var readings: [MeasurementReading] { Array((detail?.history ?? []).reversed()) }

    private var spansSeveralYears: Bool { MeasurementText.spansSeveralYears((detail?.history ?? []).map(\.date)) }

    /// Year-qualified labels are longer, so each point needs more room.
    var chartColumnWidth: CGFloat { spansSeveralYears ? 92 : 56 }

    func dateText(_ date: ISODate) -> String { spansSeveralYears ? Format.longDate(date) : Format.shortDate(date) }

    var chartPoints: [ChartPoint] {
        (detail?.history ?? []).map {
            ChartPoint(label: MeasurementText.chartLabel($0.date, includeYear: spansSeveralYears), value: $0.inches, caption: Format.fixed($0.inches))
        }
    }

    func setTarget(inches: Double) throws { try services.measurements.setTarget(site: site, inches: inches) }

    func setDirection(_ direction: MeasurementDirection) throws { try services.measurements.setDirection(site: site, direction) }

    /// "Current" is whatever the newest reading says, so editing it logs a new reading.
    func logReading(inches: Double, on date: ISODate) throws { try services.measurements.logReading(site: site, inches: inches, on: date) }

    func updateReading(_ reading: MeasurementReading, inches: Double, on date: ISODate) throws {
        try services.measurements.updateReading(id: reading.id, inches: inches, on: date.string)
    }

    func deleteReading(_ reading: MeasurementReading) throws { try services.measurements.deleteReading(id: reading.id) }

    func removeSite() throws { try services.measurements.removeSite(site) }
}

struct MeasurementDetailView: View {
    let site: String

    @EnvironmentObject private var services: Services

    var body: some View {
        MeasurementDetailContent(site: site, services: services)
    }
}

private enum MeasurementSheet: Identifiable {
    case editTarget
    case editCurrent
    case logReading
    case editReading(MeasurementReading)

    var id: String {
        switch self {
        case .editTarget: return "target"
        case .editCurrent: return "current"
        case .logReading: return "log"
        case .editReading(let reading): return "reading-\(reading.id)"
        }
    }
}

private struct MeasurementDetailContent: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: MeasurementDetailViewModel
    @State private var sheet: MeasurementSheet?
    @State private var confirmingRemoval = false
    @State private var errorMessage: String?
    @State private var showsAllReadings = false

    private static let collapsedReadingCount = 8

    init(site: String, services: Services) {
        _model = StateObject(wrappedValue: MeasurementDetailViewModel(site: site, services: services))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BodyHeader(caption: "Body site", title: model.site)
                if let loadError = model.loadError {
                    Text(loadError).font(.system(size: 13)).foregroundColor(Theme.red).card()
                }
                if let detail = model.detail {
                    summaryCard(detail)
                    historyCard(detail)
                    readingsCard
                    Button("Remove this site") { confirmingRemoval = true }
                        .buttonStyle(BodyDestructiveButtonStyle())
                        .accessibilityIdentifier("remove-site-button")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task(id: session.revision) { model.load() }
        .sheet(item: $sheet, content: sheetContent)
        .confirmationDialog("Remove \(model.site)?", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("Remove site", role: .destructive, action: removeSite)
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The target goes away. Your readings are kept.")
        }
        .errorAlert($errorMessage)
    }

    private func summaryCard(_ detail: MeasurementDetail) -> some View {
        HStack(spacing: 16) {
            RingView(progress: detail.fraction, size: 104, lineWidth: 11,
                     label: MeasurementText.ringLabel(detail.status), subLabel: MeasurementText.ringCaption(detail.status),
                     color: MeasurementText.ringColor(detail.status))
            VStack(alignment: .leading, spacing: 8) {
                valueRow(label: "Current", value: MeasurementText.inches(detail.current), tint: Theme.text,
                         editIdentifier: "measurement-current-edit-button") { sheet = .editCurrent }
                valueRow(label: "Target", value: MeasurementText.inches(detail.target), tint: Theme.green,
                         editIdentifier: "measurement-target-edit-button") { sheet = .editTarget }
                if detail.target != nil { directionPicker(detail) }
            }
        }
        .card()
    }

    /// Grow sites (shoulders, arms) are fine above their target; reduce sites (waist) are not.
    private func directionPicker(_ detail: MeasurementDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Goal")
            Picker("Goal", selection: Binding(get: { detail.direction }, set: { direction in
                do {
                    try model.setDirection(direction)
                    session.didChange()
                } catch {
                    errorMessage = error.localizedDescription
                }
            })) {
                Text("Grow").tag(MeasurementDirection.grow)
                Text("Reduce").tag(MeasurementDirection.reduce)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("measurement-direction-picker")
        }
    }

    private func valueRow(label: String, value: String, tint: Color, editIdentifier: String, edit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(label)
            HStack(alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(.system(size: 24, weight: .bold)).foregroundColor(tint)
                    Text("in").font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                Spacer()
                Button("Edit", action: edit)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier(editIdentifier)
            }
        }
    }

    private func historyCard(_ detail: MeasurementDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel("History")
                Spacer()
                if let target = detail.target {
                    Text("- - target \(Format.fixed(target))").font(.system(size: 11, weight: .medium)).foregroundColor(Theme.green)
                }
            }
            if detail.history.isEmpty {
                Text("No readings yet. Log your first reading below.").font(.system(size: 13)).foregroundColor(Theme.muted)
            } else {
                BodyScrollableChart(points: model.chartPoints, columns: detail.history.count, targetLine: detail.target,
                                    minimumColumnWidth: model.chartColumnWidth)
            }
        }
        .card()
    }

    private var readingsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Readings")
                Spacer()
                Button("+ Log reading") { sheet = .logReading }
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityIdentifier("log-reading-button")
            }
            .padding(.bottom, 4)
            ForEach(showsAllReadings ? model.readings : Array(model.readings.prefix(Self.collapsedReadingCount))) { reading in
                BodyHistoryRow(date: model.dateText(reading.date), value: "\(Format.fixed(reading.inches)) in",
                               identifier: "reading-\(reading.id)") { sheet = .editReading(reading) }
            }
            if model.readings.count > Self.collapsedReadingCount {
                Button(showsAllReadings ? "Show fewer" : "Show all \(model.readings.count) readings") { showsAllReadings.toggle() }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.top, 10)
            }
        }
        .card()
    }

    @ViewBuilder
    private func sheetContent(_ sheet: MeasurementSheet) -> some View {
        let today = model.today
        switch sheet {
        case .editTarget:
            BodyValueEntrySheet(title: "Target", fieldLabel: "Target", unit: "in",
                                initialText: model.detail?.target.map { Format.fixed($0) } ?? "", today: today) { inches, _ in
                try model.setTarget(inches: inches)
                session.didChange()
            }
        case .editCurrent:
            BodyValueEntrySheet(title: "Current", fieldLabel: "Current", unit: "in",
                                initialText: model.detail?.current.map { Format.fixed($0) } ?? "", today: today) { inches, day in
                try model.logReading(inches: inches, on: day)
                session.didChange()
            }
        case .logReading:
            BodyValueEntrySheet(title: "Log reading", fieldLabel: "Reading", unit: "in",
                                initialDate: today, today: today) { inches, day in
                try model.logReading(inches: inches, on: day)
                session.didChange()
            }
        case .editReading(let reading):
            BodyValueEntrySheet(title: "Edit reading", fieldLabel: "Reading", unit: "in", initialText: Format.fixed(reading.inches),
                                initialDate: reading.date, today: today, deleteTitle: "Delete reading",
                                onDelete: {
                                    try model.deleteReading(reading)
                                    session.didChange()
                                }) { inches, day in
                try model.updateReading(reading, inches: inches, on: day)
                session.didChange()
            }
        }
    }

    private func removeSite() {
        do {
            try model.removeSite()
            session.didChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
