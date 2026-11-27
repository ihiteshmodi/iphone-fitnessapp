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

public enum LabRangeClassification: String, Equatable {
    case optimal
    case withinLabBelowOptimal
    case withinLabAboveOptimal
    case belowLabRange
    case aboveLabRange
    case low
    case high
    case disputed
    case withinLabNoOptimal
    case recorded

    public var title: String {
        switch self {
        case .optimal: return "Optimal"
        case .withinLabBelowOptimal: return "In lab range · below optimal"
        case .withinLabAboveOptimal: return "In lab range · above optimal"
        case .belowLabRange: return "Low · below lab range"
        case .aboveLabRange: return "High · above lab range"
        case .low: return "Low"
        case .high: return "High"
        case .disputed: return "Disputed zone"
        case .withinLabNoOptimal: return "Within lab range"
        case .recorded: return "Recorded"
        }
    }
}

public struct LabSimplePatternMatch: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let markerIDs: [String]
    public let contributingSummary: String
    public let detail: String
    public let isUrgentDoctor: Bool
    public let newestDate: ISODate
    public let source: String?

    public init(id: String, name: String, markerIDs: [String], contributingSummary: String, detail: String,
                isUrgentDoctor: Bool, newestDate: ISODate, source: String? = nil) {
        self.id = id
        self.name = name
        self.markerIDs = markerIDs
        self.contributingSummary = contributingSummary
        self.detail = detail
        self.isUrgentDoctor = isUrgentDoctor
        self.newestDate = newestDate
        self.source = source
    }
}

public struct LabCompanionCheckSummary: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let markerIDs: [String]
    public let summary: String
}

public struct LabTestedMarkerRow: Equatable, Identifiable {
    public var id: String { marker.id }
    public let marker: LabMarker
    public let result: LabResult
    public let labName: String?
    public let isCore: Bool
    public let reading: LabReading
    public let rangeClassification: LabRangeClassification
    public let interpretations: [String]

    public var isOptimalOrWithinLab: Bool {
        rangeClassification == .optimal || rangeClassification == .withinLabNoOptimal
    }

    public var isInLabSuboptimal: Bool {
        [.withinLabBelowOptimal, .withinLabAboveOptimal, .disputed].contains(rangeClassification)
    }

    public var isOutOfRange: Bool {
        [.belowLabRange, .aboveLabRange, .low, .high].contains(rangeClassification)
    }

    public var needsAttention: Bool {
        isOutOfRange || isInLabSuboptimal
    }
}

public struct LabDashboardChapterSummary: Equatable, Identifiable {
    public var id: String { chapter }
    public let chapter: String
    public let rows: [LabTestedMarkerRow]
    public let coreCount: Int
    public let optimalCount: Int
    public let inLabSuboptimalCount: Int
    public let outOfRangeCount: Int
    public let latestDate: ISODate?

    public var attentionCount: Int { outOfRangeCount + inLabSuboptimalCount }
}

public struct LabDashboardHubSummary: Equatable {
    public let totalTested: Int
    public let coreTestedCount: Int
    public let optimalCount: Int
    public let inLabSuboptimalCount: Int
    public let outOfRangeCount: Int
    public let activeInterpretationCount: Int
    public let cleanCheckCount: Int
    public let attentionRows: [LabTestedMarkerRow]
    public let chapterSummaries: [LabDashboardChapterSummary]

    public static func build(from snapshot: LabLatestSnapshot) -> LabDashboardHubSummary {
        let rows = snapshot.testedRows
        let activeEpistatic = snapshot.epistaticMatches.filter { !$0.id.hasSuffix("-silent") && !$0.id.hasSuffix("-unexpressed") }.count
        let activeCount = snapshot.activePatterns.count + snapshot.discordances.count + snapshot.simplePatterns.count + activeEpistatic

        var orderedChapters: [String] = []
        for row in rows where !orderedChapters.contains(row.marker.chapter) {
            orderedChapters.append(row.marker.chapter)
        }

        let summaries = orderedChapters.map { chapter -> LabDashboardChapterSummary in
            let chRows = rows.filter { $0.marker.chapter == chapter }
            return LabDashboardChapterSummary(
                chapter: chapter,
                rows: chRows,
                coreCount: chRows.filter(\.isCore).count,
                optimalCount: chRows.filter(\.isOptimalOrWithinLab).count,
                inLabSuboptimalCount: chRows.filter(\.isInLabSuboptimal).count,
                outOfRangeCount: chRows.filter(\.isOutOfRange).count,
                latestDate: chRows.map(\.result.date).max())
        }.sorted { lhs, rhs in
            if lhs.outOfRangeCount != rhs.outOfRangeCount { return lhs.outOfRangeCount > rhs.outOfRangeCount }
            if lhs.attentionCount != rhs.attentionCount { return lhs.attentionCount > rhs.attentionCount }
            return false
        }

        let attentionRows = rows.filter(\.needsAttention).sorted { lhs, rhs in
            if lhs.isOutOfRange != rhs.isOutOfRange { return lhs.isOutOfRange && !rhs.isOutOfRange }
            return lhs.isCore && !rhs.isCore
        }

        return LabDashboardHubSummary(
            totalTested: rows.count,
            coreTestedCount: rows.filter(\.isCore).count,
            optimalCount: rows.filter(\.isOptimalOrWithinLab).count,
            inLabSuboptimalCount: rows.filter(\.isInLabSuboptimal).count,
            outOfRangeCount: rows.filter(\.isOutOfRange).count,
            activeInterpretationCount: activeCount,
            cleanCheckCount: snapshot.cleanCompanionChecks.count,
            attentionRows: attentionRows,
            chapterSummaries: summaries)
    }
}

public struct LabLatestSnapshot: Equatable {
    public let testedRows: [LabTestedMarkerRow]
    public let activePatterns: [LabPatternMatch]
    public let simplePatterns: [LabSimplePatternMatch]
    public let discordances: [LabDiscordanceAlert]
    public let epistaticMatches: [LabGeneticEpistaticMatch]
    public let cleanCompanionChecks: [LabCompanionCheckSummary]

    public static let empty = LabLatestSnapshot(testedRows: [], activePatterns: [], simplePatterns: [],
                                                discordances: [], epistaticMatches: [], cleanCompanionChecks: [])

    private static let companionGroups: [(id: String, title: String, markers: [String])] = [
        ("mpv-platelets", "MPV + Platelets check", ["mpv", "platelets"]),
        ("sex-hormones-shbg", "Total T + Free T + SHBG check", ["total-testosterone", "free-testosterone", "shbg"]),
        ("iron-storage-sat", "Ferritin + Iron + TSAT check", ["ferritin", "tsat"]),
        ("thyroid-axis", "TSH + Free T4 + Free T3 check", ["tsh", "free-t4", "free-t3"]),
        ("lipids-apob", "LDL-C + ApoB particle check", ["ldl-c", "apob"]),
        ("kidney-filtration", "Creatinine + eGFR / Cystatin C check", ["creatinine", "egfr"]),
        ("glycemic-pair", "Fasting Glucose + HbA1c check", ["glucose", "hba1c"]),
        ("liver-transaminases", "AST + ALT transaminase check", ["ast", "alt"]),
        ("vitamin-d-calcium", "25-OH Vitamin D + Calcium check", ["vitamin-d", "calcium"]),
        ("b12-methylation", "B12 + Homocysteine / MMA check", ["b12", "homocysteine"]),
    ]

    public static func build(catalogue: LabCatalogue, db: Database, draws: LabDrawService,
                             preferences: LabPreferences, genotypes: [GenotypeEntry]) throws -> LabLatestSnapshot {
        let (byMarker, drawsByID, newestDate) = try draws.latestResultsSnapshot()
        guard !byMarker.isEmpty else { return .empty }

        let latestValues = Array(byMarker.values)
        let ctx = newestDate.flatMap { try? LabNonBloodContext.load(from: db, on: $0) }
        let activePatterns = LabPatternEvaluator.evaluateLatest(
            resultsByMarker: byMarker, drawsByID: drawsByID, fallbackDate: newestDate,
            catalogue: catalogue, preferences: preferences, context: ctx)
        let simplePatterns = LabPatternEvaluator.evaluateSimplePatterns(
            resultsByMarker: byMarker, drawsByID: drawsByID, catalogue: catalogue, preferences: preferences)
        let discordances = LabPatternEvaluator.discordances(in: latestValues, catalogue: catalogue, preferences: preferences)
        let epistatic = GeneticsModifierEvaluator.evaluateEpistaticGrid(results: latestValues, genotypes: genotypes, preferences: preferences)

        var flaggedMarkerIDs: Set<String> = []
        for s in simplePatterns { flaggedMarkerIDs.formUnion(s.markerIDs) }
        for d in discordances { flaggedMarkerIDs.formUnion(d.markerIDs) }
        for pat in activePatterns {
            if let req = catalogue.patterns.first(where: { $0.engine?.slug == pat.id })?.engine?.markersRequired {
                flaggedMarkerIDs.formUnion(req)
            }
        }

        var cleanChecks: [LabCompanionCheckSummary] = []
        for group in companionGroups {
            let present = group.markers.filter { byMarker[$0] != nil }
            guard present.count == group.markers.count else { continue }
            guard flaggedMarkerIDs.isDisjoint(with: present) else { continue }
            let parts = present.compactMap { mid -> String? in
                guard let res = byMarker[mid] else { return nil }
                let mName = catalogue.marker(mid)?.name ?? mid
                let valText = res.textValue ?? "\(LabInsightsRule.number(res.value))\(res.unit.isEmpty ? "" : " \(res.unit)")"
                return "\(mName) \(valText) (\(res.date.dayMonthYear))"
            }
            cleanChecks.append(LabCompanionCheckSummary(
                id: group.id,
                title: "\(group.title): Clear",
                markerIDs: present,
                summary: "Checked \(parts.joined(separator: " + ")): no cross-marker discordance or red-flag pattern triggered."))
        }

        let visibleMarkers = catalogue.visibleMarkers(for: preferences.sex)
        let rows: [LabTestedMarkerRow] = visibleMarkers.compactMap { marker in
            guard let res = byMarker[marker.id] else { return nil }
            let draft = drawsByID[res.drawID]
            let reading = LabReader.read(result: res, marker: marker, preferences: preferences, draw: draft, genotypes: genotypes)
            let classification = classify(result: res, marker: marker, reading: reading, sex: preferences.sex)
            let isCore = CoreBloodworkGuide.isCoreMarker(marker.id, catalogue: catalogue, sex: preferences.sex)

            var notes: [String] = []
            notes += reading.doctorLines.map { "\($0.urgency.title): \($0.text)" }
            notes += reading.geneticNotes
            for d in discordances where d.markerIDs.contains(marker.id) {
                notes.append("\(d.title): \(d.detail)")
            }
            for s in simplePatterns where s.markerIDs.contains(marker.id) {
                notes.append("\(s.name): \(s.detail)")
            }
            for pat in activePatterns {
                let req = catalogue.patterns.first(where: { $0.engine?.slug == pat.id })?.engine?.markersRequired ?? []
                if req.contains(marker.id) {
                    let phenos = pat.matchedPhenotypes.map(\.name).joined(separator: ", ")
                    notes.append("Pattern: \(pat.name)\(phenos.isEmpty ? "" : " (\(phenos))")")
                }
            }
            if notes.isEmpty {
                for clean in cleanChecks where clean.markerIDs.contains(marker.id) {
                    notes.append(clean.title)
                }
            }
            return LabTestedMarkerRow(marker: marker, result: res, labName: draft?.lab, isCore: isCore,
                                      reading: reading, rangeClassification: classification, interpretations: notes)
        }

        return LabLatestSnapshot(testedRows: rows, activePatterns: activePatterns, simplePatterns: simplePatterns,
                                 discordances: discordances, epistaticMatches: epistatic, cleanCompanionChecks: cleanChecks)
    }

    private static func classify(result: LabResult, marker: LabMarker, reading: LabReading, sex: LabSex) -> LabRangeClassification {
        let val = reading.value ?? result.defaultValue
        let labBands = marker.visibleBands(for: sex).filter { $0.kind == "lab" && $0.condition == nil }
        let toDef = { (bound: Double?, unit: String?) -> Double? in
            guard let bound else { return nil }
            if let unit { return marker.toDefault(bound, unit: unit) }
            return marker.isUnitlessRatio ? bound : nil
        }
        let stdLow: Double? = reading.activeStratum?.standardLow
            ?? labBands.compactMap { toDef($0.low, $0.unit) }.min()
            ?? result.labLow.flatMap { marker.toDefault($0, unit: result.unit) ?? $0 }
        let stdHigh: Double? = reading.activeStratum?.standardHigh
            ?? labBands.compactMap { toDef($0.high, $0.unit) }.max()
            ?? result.labHigh.flatMap { marker.toDefault($0, unit: result.unit) ?? $0 }

        switch reading.status {
        case .optimal:
            return .optimal
        case .disputed:
            return .disputed
        case .low:
            if let val, let stdLow {
                return val >= stdLow ? .withinLabBelowOptimal : .belowLabRange
            }
            return .low
        case .high:
            if let val, let stdHigh {
                return val <= stdHigh ? .withinLabAboveOptimal : .aboveLabRange
            }
            return .high
        case .noOptimalBand:
            if let val {
                if let stdLow, val < stdLow { return .belowLabRange }
                if let stdHigh, val > stdHigh { return .aboveLabRange }
                if stdLow != nil || stdHigh != nil { return .withinLabNoOptimal }
            }
            return .recorded
        case .notComparable:
            return .recorded
        }
    }
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
    public let snapshot: LabLatestSnapshot

    public static func build(catalogue: LabCatalogue, db: Database, today: ISODate) throws -> LabDashboard {
        let preferences = try LabSettings(db).load()
        let genotypes = (try? GeneticsService(db, catalogue: catalogue).entries()) ?? []
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
                let reading = LabReader.read(result: latest, marker: marker, preferences: preferences, genotypes: genotypes)
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
                             reading: latest.map { LabReader.read(result: $0, marker: marker, preferences: preferences, genotypes: genotypes) })
        }
        let hormones = hormoneMarkers.compactMap(catalogue.marker).filter { history[$0.id] != nil }
            .map { MarkerSeries(marker: $0, points: series($0, history)) }
        let age = try biologicalAge(draws: draws, birthDate: preferences.birthDate)
        let snapshot = try LabLatestSnapshot.build(catalogue: catalogue, db: db, draws: draws,
                                                   preferences: preferences, genotypes: genotypes)
        return LabDashboard(systems: systems, heart: heart, hormones: hormones, biologicalAge: age?.outcome,
                            biologicalAgeDraw: age?.date, snapshot: snapshot)
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
