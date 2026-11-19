import Foundation

/// One test to ask for. markerID is nil for tests the vault names without a lesson (they are still ordered by name).
public struct OrderTest: Equatable {
    public let name: String
    public let markerID: String?
}

public struct OrderItem: Equatable {
    public let panel: LabPanel
    public let tests: [OrderTest]
    /// Why a conditional panel was added (the vault's trigger text).
    public let reason: String?
}

public struct TimedPrepStep: Equatable {
    public let step: LabPrepStep
    public let date: ISODate
    /// Hour of the day the step starts (0-23).
    public let hour: Int
}

public struct RetestDue: Equatable {
    public let marker: LabMarker
    public let lastDate: ISODate?
    public let rule: LabRetest?
    public let from: ISODate?
    public let until: ISODate?
    public let note: String?
}

/// The vault's what-to-order, draw prep and retest timing, worked out from the catalogue and the owner's results.
public struct DrawPlanner {
    private let catalogue: LabCatalogue
    private let draws: LabDrawService
    private let sex: LabSex

    public init(catalogue: LabCatalogue, draws: LabDrawService, sex: LabSex) {
        self.catalogue = catalogue
        self.draws = draws
        self.sex = sex
    }

    /// Every test named, panel by panel, so nothing hides inside a bundle name (uric acid on a CMP, for instance).
    public func order() throws -> [OrderItem] {
        var items: [OrderItem] = []
        for panel in catalogue.panels where panel.tag != "female" || sex == .female {
            let tests = resolve(panel.markers, seen: [panel.id])
            switch panel.when {
            case "first", "routine", nil:
                if panel.when == "routine", items.contains(where: { $0.panel.when == "first" && Set($0.panel.markers) == Set(panel.markers) }) { continue }
                items.append(OrderItem(panel: panel, tests: tests, reason: nil))
            case "conditional":
                guard let triggers = panel.triggerMarkers, !triggers.isEmpty, try triggers.contains(where: isOff) else { continue }
                items.append(OrderItem(panel: panel, tests: tests, reason: panel.trigger))
            default:
                continue
            }
        }
        return items
    }

    /// A panel name expands into its tests; an alias finds its marker; anything else is still named.
    private func resolve(_ ids: [String], seen: Set<String>) -> [OrderTest] {
        var tests: [OrderTest] = []
        for id in ids {
            let found: [OrderTest]
            if let marker = catalogue.marker(id) {
                found = [OrderTest(name: marker.name, markerID: marker.id)]
            } else if let panel = catalogue.panel(id), !seen.contains(id) {
                found = resolve(panel.markers, seen: seen.union([id]))
            } else if let marker = catalogue.markers.first(where: { ([$0.name] + $0.aliases).contains { $0.caseInsensitiveCompare(id) == .orderedSame } }) {
                found = [OrderTest(name: marker.name, markerID: marker.id)]
            } else {
                let words = id.replacingOccurrences(of: "-", with: " ")
                found = [OrderTest(name: words.prefix(1).uppercased() + words.dropFirst(), markerID: nil)]
            }
            for test in found where !tests.contains(test) { tests.append(test) }
        }
        return tests
    }

    /// Prep steps for the ordered tests (steps with no marker list apply to every draw), earliest first.
    public func prepTimeline(drawDate: ISODate, drawHour: Int, ordered: [String]) -> [TimedPrepStep] {
        let wanted = Set(ordered)
        return catalogue.prep
            .filter { step in step.hoursBefore != nil && (step.markers.map { !wanted.isDisjoint(with: $0) } ?? true) }
            .sorted { ($0.hoursBefore ?? 0) > ($1.hoursBefore ?? 0) }
            .map { step in
                let hoursFromMidnight = drawHour - Int((step.hoursBefore ?? 0).rounded())
                let dayShift = Int((Double(hoursFromMidnight) / 24).rounded(.down))
                let hour = hoursFromMidnight - dayShift * 24
                return TimedPrepStep(step: step, date: drawDate.adding(days: dayShift), hour: hour)
            }
    }

    /// Markers in the first panels plus any marker with a result, with the vault's retest window from the last result.
    public func retests() throws -> [RetestDue] {
        let firstPanelMarkers = catalogue.panels.filter { $0.when == "first" }.flatMap(\.markers)
        var ids: [String] = []
        for id in firstPanelMarkers where !ids.contains(id) { ids.append(id) }
        for marker in catalogue.markers where try !draws.history(of: marker.id).isEmpty && !ids.contains(marker.id) { ids.append(marker.id) }
        return try ids.compactMap(catalogue.marker).map { marker in
            guard let last = try draws.history(of: marker.id).first else {
                return RetestDue(marker: marker, lastDate: nil, rule: nil, from: nil, until: nil, note: "Baseline: not tested yet")
            }
            let off = try isOff(marker.id)
            let rule = marker.retest.first { $0.after == (off ? "abnormal" : "routine") }
                ?? marker.retest.first { $0.after == (off ? "change" : "routine") }
                ?? marker.retest.first
            let from = rule.flatMap { Self.shift(last.date, weeks: $0.minWeeks, months: $0.minMonths) }
            let until = rule.flatMap { Self.shift(last.date, weeks: $0.maxWeeks, months: $0.maxMonths) }
            return RetestDue(marker: marker, lastDate: last.date, rule: rule, from: from, until: until, note: nil)
        }
    }

    private static func shift(_ day: ISODate, weeks: Double?, months: Double?) -> ISODate? {
        if let weeks { return day.adding(days: Int((weeks * 7).rounded())) }
        if let months { return day.adding(months: Int(months.rounded())) }
        return nil
    }

    /// The latest result sits outside the optimal bands, in a disputed zone, or crosses a doctor line.
    private func isOff(_ markerID: String) throws -> Bool {
        guard let marker = catalogue.marker(markerID), let last = try draws.history(of: markerID).first else { return false }
        let reading = LabReader.read(value: last.value, unit: last.unit, marker: marker, sex: sex)
        return [.low, .high, .disputed].contains(reading.status) || !reading.doctorLines.isEmpty
    }
}
