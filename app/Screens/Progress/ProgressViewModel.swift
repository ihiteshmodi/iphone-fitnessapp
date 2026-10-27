import FitnessCore
import SwiftUI

/// How a measurement status is worded and coloured, shared by the ring grid and the detail screen.
enum MeasurementText {
    static func statusLine(_ status: MeasurementStatus) -> String {
        switch status {
        case .noReading: return "No reading yet"
        case .noTarget: return "No target"
        case .atTarget: return "At target"
        case .toGain(let inches): return "\(Format.fixed(inches)) to gain"
        case .toLose(let inches): return "\(Format.fixed(inches)) to lose"
        case .ahead(let inches): return "\(Format.fixed(inches)) ahead of target"
        }
    }

    /// Green when on track (including ahead of a growth target), amber when worth watching, red when far off.
    static func color(_ attention: MeasurementAttention?) -> Color {
        switch attention {
        case .onTrack: return Theme.green
        case .watch: return Theme.amber
        case .off: return Theme.red
        case nil: return Theme.muted
        }
    }

    static func ringColor(_ attention: MeasurementAttention?) -> Color {
        attention == nil ? Theme.green : color(attention)
    }

    /// "+7.9%" above the target, "−8.6%" below it.
    static func percentText(_ percent: Double?) -> String? {
        guard let percent else { return nil }
        if percent == 0 { return "0%" }
        return "\(percent > 0 ? "+" : "−")\(Format.number(abs(percent), maxDecimals: 1))%"
    }

    static func ringLabel(_ status: MeasurementStatus) -> String {
        switch status {
        case .toGain(let inches), .toLose(let inches), .ahead(let inches): return Format.fixed(inches)
        case .atTarget: return "0.00"
        case .noReading, .noTarget: return "–"
        }
    }

    static func ringCaption(_ status: MeasurementStatus) -> String {
        switch status {
        case .toGain: return "in to gain"
        case .toLose: return "in to lose"
        case .ahead: return "in ahead"
        case .atTarget: return "at target"
        case .noReading: return "no reading"
        case .noTarget: return "no target"
        }
    }

    static func inches(_ value: Double?) -> String { value.map { Format.fixed($0) } ?? "–" }

    /// Dates repeat across years, so charts that span more than one year show the year too.
    static func chartLabel(_ date: ISODate, includeYear: Bool) -> String {
        includeYear ? Format.longDate(date) : Format.shortDate(date)
    }

    static func spansSeveralYears(_ dates: [ISODate]) -> Bool {
        Set(dates.map { $0.string.prefix(4) }).count > 1
    }
}

@MainActor
final class ProgressViewModel: ObservableObject {
    @Published private(set) var rings: [MeasurementProgress] = []
    @Published private(set) var muscles: [String] = []
    @Published private(set) var selectedMuscle: String?
    @Published private(set) var volumeSeries: [ExerciseVolumeSeries] = []
    @Published private(set) var loadError: String?

    @Published private(set) var tolerancePercent = 3.0

    private let services: Services
    private static let palette = [Theme.green, Theme.greenSoft, Theme.greenDeep]

    init(services: Services) { self.services = services }

    var today: ISODate { services.clock.today() }

    func load() {
        do {
            rings = try services.measurements.progress()
            tolerancePercent = try services.settings.load().measurementTolerancePercent
            muscles = try services.volume.muscles()
            if let selected = selectedMuscle, muscles.contains(selected) {
                selectedMuscle = selected
            } else {
                selectedMuscle = muscles.first
            }
            volumeSeries = try selectedMuscle.map { try services.volume.series(muscle: $0) } ?? []
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func select(muscle: String) {
        selectedMuscle = muscle
        do {
            volumeSeries = try services.volume.series(muscle: muscle)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func setTolerance(_ percent: Double) throws {
        try services.settings.setMeasurementTolerancePercent(percent)
    }

    var toleranceCaption: String {
        "Within ±\(Format.number(tolerancePercent, maxDecimals: 1))% of a target counts as on track. Amber beyond that, red beyond \(Format.number(max(MeasurementGoal.offTargetPercent, tolerancePercent), maxDecimals: 1))%."
    }

    func addSite(nameText: String, firstReadingText: String, targetText: String) throws {
        guard let first = Format.decimal(firstReadingText) else { throw ValidationError("Enter the first reading as a number") }
        guard let target = Format.decimal(targetText) else { throw ValidationError("Enter the target as a number") }
        try services.measurements.addSite(name: nameText, firstReading: first, target: target)
    }

    // MARK: Volume chart

    var seriesColors: [String: Color] {
        Dictionary(volumeSeries.enumerated().map { ($0.element.exerciseName, Self.palette[$0.offset % Self.palette.count]) },
                   uniquingKeysWith: { first, _ in first })
    }

    var legend: [(name: String, color: Color)] {
        volumeSeries.enumerated().map { ($0.element.exerciseName, Self.palette[$0.offset % Self.palette.count]) }
    }

    private var volumeDates: [ISODate] { Array(Set(volumeSeries.flatMap { $0.points.map(\.date) })).sorted() }

    var volumeColumns: Int { volumeDates.count }

    /// Sorted by date across all exercises so the chart's x axis runs oldest to newest.
    var volumePoints: [ChartPoint] {
        let includeYear = MeasurementText.spansSeveralYears(volumeDates)
        let rows = volumeSeries.flatMap { series in series.points.map { (name: series.exerciseName, point: $0) } }
            .sorted { ($0.point.date, $0.name) < ($1.point.date, $1.name) }
        return rows.map {
            ChartPoint(label: MeasurementText.chartLabel($0.point.date, includeYear: includeYear), value: $0.point.volume, series: $0.name)
        }
    }
}
