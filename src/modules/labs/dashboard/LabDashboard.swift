import Foundation

public struct TrendPoint: Equatable {
    public let date: ISODate
    public let value: Double

    public init(date: ISODate, value: Double) {
        self.date = date
        self.value = value
    }
}

public struct SystemTile: Equatable {
    public let chapter: String
    public let tested: Int
    public let optimal: Int
    public let disputed: Int
    public let outside: Int
    public let doctor: Int
    public let keyMarker: LabMarker?
    /// The key marker in its default unit, oldest first.
    public let trend: [TrendPoint]
    public let lastTested: ISODate?
    public let retestsDue: Int
}

public struct HeartItem: Equatable {
    public let marker: LabMarker
    public let latest: LabResult?
    public let reading: LabReading?
}

public struct MarkerSeries: Equatable {
    public let marker: LabMarker
    public let points: [TrendPoint]
}

/// The bloodwork dashboard: one tile per chapter, the heart-risk markers, hormones over time and biological age.
public struct LabDashboard {
    public static let heartMarkers = ["apob", "lpa", "hs-crp", "blood-pressure", "cac-score"]
    public static let hormoneMarkers = ["total-testosterone", "free-testosterone", "shbg", "estradiol", "lh", "fsh", "prolactin"]

    public let systems: [SystemTile]
    public let heart: [HeartItem]
    public let hormones: [MarkerSeries]
    public let biologicalAge: PhenoAgeOutcome?
    /// The draw biological age was worked out from, or the one closest to complete.
    public let biologicalAgeDraw: ISODate?

    public static func build(catalogue: LabCatalogue, db: Database, today: ISODate) throws -> LabDashboard {
        let preferences = try LabSettings(db).load()
        let draws = LabDrawService(db, catalogue: catalogue)
        var history: [String: [LabResult]] = [:]
        for marker in catalogue.markers {
            let results = try draws.history(of: marker.id)
            if !results.isEmpty { history[marker.id] = results }
        }
        let due = try DrawPlanner(catalogue: catalogue, draws: draws, sex: preferences.sex).retests()
            .filter { $0.from.map { today >= $0 } ?? false }.map(\.marker.id)

        var chapters: [String] = []
        for marker in catalogue.markers where history[marker.id] != nil && !chapters.contains(marker.chapter) { chapters.append(marker.chapter) }
        let systems = chapters.map { chapter -> SystemTile in
            let markers = catalogue.markers.filter { $0.chapter == chapter && history[$0.id] != nil }
            var counts = (optimal: 0, disputed: 0, outside: 0, doctor: 0)
            for marker in markers {
                let latest = history[marker.id]![0]
                let reading = LabReader.read(result: latest, marker: marker, preferences: preferences)
                if !reading.doctorLines.isEmpty { counts.doctor += 1 }
                switch reading.status {
                case .optimal: counts.optimal += 1
                case .disputed: counts.disputed += 1
                case .low, .high: counts.outside += 1
                default: break
                }
            }
            let key = markers.first { (history[$0.id]?.count ?? 0) >= 2 } ?? markers.first
            return SystemTile(chapter: chapter, tested: markers.count, optimal: counts.optimal, disputed: counts.disputed,
                              outside: counts.outside, doctor: counts.doctor, keyMarker: key,
                              trend: key.map { series($0, history) } ?? [],
                              lastTested: markers.compactMap { history[$0.id]?.first?.date }.max(),
                              retestsDue: markers.filter { due.contains($0.id) }.count)
        }
        let heart = heartMarkers.compactMap(catalogue.marker).map { marker -> HeartItem in
            let latest = history[marker.id]?.first
            return HeartItem(marker: marker, latest: latest,
                             reading: latest.map { LabReader.read(result: $0, marker: marker, preferences: preferences) })
        }
        let hormones = hormoneMarkers.compactMap(catalogue.marker).filter { history[$0.id] != nil }
            .map { MarkerSeries(marker: $0, points: series($0, history)) }
        let age = try biologicalAge(draws: draws, birthDate: preferences.birthDate)
        return LabDashboard(systems: systems, heart: heart, hormones: hormones, biologicalAge: age?.outcome, biologicalAgeDraw: age?.date)
    }

    private static func series(_ marker: LabMarker, _ history: [String: [LabResult]]) -> [TrendPoint] {
        (history[marker.id] ?? []).reversed().compactMap { result in result.defaultValue.map { TrendPoint(date: result.date, value: $0) } }
    }

    /// The newest draw that has all ten inputs, else the draw missing the fewest (the newest of those).
    private static func biologicalAge(draws: LabDrawService, birthDate: ISODate?) throws -> (outcome: PhenoAgeOutcome, date: ISODate)? {
        guard let birthDate else { return nil }
        var closest: (outcome: PhenoAgeOutcome, date: ISODate, missing: Int)?
        for draw in try draws.draws() {
            let outcome = try PhenoAge.forDraw(draw.id, draws: draws, birthDate: birthDate)
            guard case .missing(let inputs) = outcome else { return (outcome, draw.draft.date) }
            if inputs.count < (closest?.missing ?? .max) { closest = (outcome, draw.draft.date, inputs.count) }
        }
        return closest.map { ($0.outcome, $0.date) }
    }
}
