import Foundation

/// One test to ask for. markerID is nil for tests the vault names without a lesson (they are still ordered by name).
public struct OrderTest: Equatable {
    public let name: String
    public let markerID: String?
    public let drawNote: String?

    public init(name: String, markerID: String?, drawNote: String? = nil) {
        self.name = name
        self.markerID = markerID
        self.drawNote = drawNote
    }
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
    private let genetics: GeneticsService?
    private let showDrugNotes: Bool

    public init(catalogue: LabCatalogue, draws: LabDrawService, sex: LabSex, genetics: GeneticsService? = nil, showDrugNotes: Bool = false) {
        self.catalogue = catalogue
        self.draws = draws
        self.sex = sex
        self.genetics = genetics
        self.showDrugNotes = showDrugNotes
    }

    /// Every test named, panel by panel, so nothing hides inside a bundle name (uric acid on a CMP, for instance).
    public func order() throws -> [OrderItem] {
        var items: [OrderItem] = []
        for panel in catalogue.panels where sex.allows(sex: nil, tag: panel.tag, showDrugNotes: showDrugNotes) {
            let tests = resolve(panel.markers, notes: panel.drawNotes, seen: [panel.id])
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
        if let reflex = try reflexCoTestsItem() { items.append(reflex) }
        if let genetics, let fromGenes = try genetics.orderItem(draws: draws) { items.append(fromGenes) }
        return items
    }

    /// Optional Tier 2/3 conditional upgrade tests filtered strictly to the active sex.
    public func upgrades() -> [OrderTest] {
        var out: [OrderTest] = []
        for panel in catalogue.panels where panel.when == "upgrade" && sex.allows(sex: nil, tag: panel.tag, showDrugNotes: showDrugNotes) {
            for test in resolve(panel.markers, notes: panel.drawNotes, seen: [panel.id]) {
                if let mid = test.markerID, let marker = catalogue.marker(mid), !marker.applies(to: sex) { continue }
                if sex == .male, let note = test.drawNote?.lowercased(), note.contains("menstrual") || note.contains("ovarian") { continue }
                if !out.contains(where: { ($0.markerID ?? $0.name) == (test.markerID ?? test.name) }) { out.append(test) }
            }
        }
        return out
    }

    /// The global draw-day checklist, stripping opposite-sex lines so Male sees only Male/All-Adult guidance.
    public func checklist() -> LabDrawChecklist? {
        guard let raw = catalogue.globalProtocols?.checklist else { return nil }
        let keep = { (line: String) -> Bool in
            guard sex == .male else { return true }
            let low = line.lowercased()
            return !low.contains("menstrual") && !low.contains("premenopausal") && !low.contains("for females")
        }
        return LabDrawChecklist(nightBefore: raw.nightBefore.filter(keep),
                                morningOf: raw.morningOf.filter(keep),
                                postDraw: raw.postDraw.filter(keep),
                                loggingProtocol: raw.loggingProtocol.filter(keep))
    }

    private func reflexCoTestsItem() throws -> OrderItem? {
        var added: [OrderTest] = []
        var triggers: [String] = []
        for marker in catalogue.visibleMarkers(for: sex) where !marker.coTests.isEmpty {
            guard try isOff(marker.id), let latest = try draws.history(of: marker.id).first else { continue }
            let inSameDraw = Set(try draws.results(inDraw: latest.drawID).map(\.markerID))
            var triggeredAny = false
            for coID in marker.coTests where !inSameDraw.contains(coID) {
                guard let coMarker = catalogue.marker(coID), coMarker.applies(to: sex), !coMarker.computed || coMarker.formula == nil else { continue }
                if !added.contains(where: { $0.markerID == coMarker.id }) {
                    added.append(OrderTest(name: coMarker.name, markerID: coMarker.id))
                }
                triggeredAny = true
            }
            if triggeredAny { triggers.append(marker.name) }
        }
        guard !added.isEmpty else { return nil }
        let reason = "\(triggers.joined(separator: ", ")) outside optimal: add untested companion co-tests"
        let panel = LabPanel(id: "reflex-co-tests", name: "Follow-up co-tests", markers: added.compactMap(\.markerID),
                             when: "conditional", trigger: reason)
        return OrderItem(panel: panel, tests: added, reason: reason)
    }

    /// A panel name expands into its tests; an alias finds its marker; anything else is still named.
    private func resolve(_ ids: [String], notes: [String: String]? = nil, seen: Set<String>) -> [OrderTest] {
        var tests: [OrderTest] = []
        for id in ids {
            let found: [OrderTest]
            if let marker = catalogue.marker(id) {
                found = [OrderTest(name: marker.name, markerID: marker.id, drawNote: notes?[marker.id] ?? notes?[id])]
            } else if let panel = catalogue.panel(id), !seen.contains(id) {
                found = resolve(panel.markers, notes: panel.drawNotes ?? notes, seen: seen.union([id]))
            } else if let marker = catalogue.markers.first(where: { ([$0.name] + $0.aliases).contains { $0.caseInsensitiveCompare(id) == .orderedSame } }) {
                found = [OrderTest(name: marker.name, markerID: marker.id, drawNote: notes?[marker.id] ?? notes?[id])]
            } else {
                let words = id.replacingOccurrences(of: "-", with: " ")
                found = [OrderTest(name: words.prefix(1).uppercased() + words.dropFirst(), markerID: nil, drawNote: notes?[id])]
            }
            for test in found where !tests.contains(where: { ($0.markerID ?? $0.name) == (test.markerID ?? test.name) }) { tests.append(test) }
        }
        return tests
    }

    /// Prep steps for the ordered tests (steps with no marker list apply to every draw), earliest first.
    public func prepTimeline(drawDate: ISODate, drawHour: Int, ordered: [String]) -> [TimedPrepStep] {
        let wanted = Set(ordered)
        return catalogue.prep
            .filter { step in
                step.hoursBefore != nil
                    && sex.allows(sex: nil, tag: step.tag, showDrugNotes: showDrugNotes)
                    && (step.markers.map { !wanted.isDisjoint(with: $0) } ?? true)
            }
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
