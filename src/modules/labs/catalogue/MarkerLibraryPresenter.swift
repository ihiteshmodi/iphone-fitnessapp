import Foundation

public enum MarkerQuickFilter: String, CaseIterable, Equatable, Identifiable {
    case all = "All"
    case core = "★ Core"
    case coreNotDone = "★ Core · Not done"
    case coreDone = "★ Core · Done"
    case nonCoreDone = "Non-Core · Done"
    case nonCoreNotDone = "Non-Core · Not done"
    case optimal = "Optimal"
    case high = "High"
    case low = "Low"

    public var id: String { rawValue }
}

public struct MarkerCustomFilter: Equatable {
    public enum Tier: String, CaseIterable, Equatable {
        case any = "Any"
        case core = "★ Core"
        case nonCore = "Non-Core"
    }

    public enum Completion: String, CaseIterable, Equatable {
        case any = "Any"
        case done = "Done"
        case notDone = "Not done"
        case retestDue = "Retest due"
    }

    public enum Status: String, CaseIterable, Equatable {
        case any = "Any"
        case optimal = "Optimal"
        case high = "High"
        case low = "Low"
        case disputed = "Disputed"
        case outOfOptimal = "High or Low"
    }

    public var tier: Tier
    public var completion: Completion
    public var status: Status
    public var chapters: Set<String>

    public init(tier: Tier = .any, completion: Completion = .any, status: Status = .any, chapters: Set<String> = []) {
        self.tier = tier
        self.completion = completion
        self.status = status
        self.chapters = chapters
    }

    public var isActive: Bool {
        tier != .any || completion != .any || status != .any || !chapters.isEmpty
    }

    public var summaryText: String {
        var parts: [String] = []
        if tier != .any { parts.append(tier.rawValue) }
        if completion != .any { parts.append(completion.rawValue) }
        if status != .any { parts.append(status.rawValue) }
        if !chapters.isEmpty {
            parts.append(chapters.count == 1 ? chapters.first! : "\(chapters.count) systems")
        }
        return parts.joined(separator: " · ")
    }

    public static func fromQuick(_ quick: MarkerQuickFilter) -> MarkerCustomFilter {
        switch quick {
        case .all: return MarkerCustomFilter()
        case .core: return MarkerCustomFilter(tier: .core)
        case .coreNotDone: return MarkerCustomFilter(tier: .core, completion: .notDone)
        case .coreDone: return MarkerCustomFilter(tier: .core, completion: .done)
        case .nonCoreDone: return MarkerCustomFilter(tier: .nonCore, completion: .done)
        case .nonCoreNotDone: return MarkerCustomFilter(tier: .nonCore, completion: .notDone)
        case .optimal: return MarkerCustomFilter(completion: .done, status: .optimal)
        case .high: return MarkerCustomFilter(completion: .done, status: .high)
        case .low: return MarkerCustomFilter(completion: .done, status: .low)
        }
    }
}

public struct MarkerLibraryRowViewModel: Equatable, Identifiable {
    public var id: String { marker.id }
    public let marker: LabMarker
    public let isCore: Bool
    public let latest: LabResult?
    public let reading: LabReading?
    public let isRetestDue: Bool
}

public struct MarkerLibrarySectionViewModel: Equatable, Identifiable {
    public var id: String { chapter }
    public let chapter: String
    public let rows: [MarkerLibraryRowViewModel]
}

public struct MarkerLibraryViewModel: Equatable {
    public let allChapters: [String]
    public let quickCounts: [MarkerQuickFilter: Int]
    public let sections: [MarkerLibrarySectionViewModel]
    public var totalMatched: Int { sections.reduce(0) { $0 + $1.rows.count } }

    public static let empty = MarkerLibraryViewModel(allChapters: [], quickCounts: [:], sections: [])
}

public enum MarkerLibraryPresenter {
    public static func build(catalogue: LabCatalogue, draws: LabDrawService, preferences: LabPreferences,
                             genotypes: [GenotypeEntry], today: ISODate, fixedChapter: String? = nil,
                             search: String = "", quickFilter: MarkerQuickFilter = .all,
                             customFilter: MarkerCustomFilter? = nil) throws -> MarkerLibraryViewModel {
        let sex = preferences.sex
        let visible = catalogue.visibleMarkers(for: sex).filter { fixedChapter == nil || $0.chapter == fixedChapter }
        var allChapters: [String] = []
        for marker in visible where !allChapters.contains(marker.chapter) { allChapters.append(marker.chapter) }

        let (latestByMarker, drawsByID, _) = try draws.latestResultsSnapshot()
        let dueIDs = Set((try? DrawPlanner(catalogue: catalogue, draws: draws, sex: sex, showDrugNotes: preferences.showDrugNotes).retests())?
            .filter { $0.from.map { today >= $0 } ?? false }
            .map(\.marker.id) ?? [])

        let searchTrimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchedIDs: Set<String>? = searchTrimmed.isEmpty ? nil : Set(catalogue.search(searchTrimmed).map(\.id))

        let candidateRows: [MarkerLibraryRowViewModel] = visible.compactMap { marker in
            if let searchedIDs, !searchedIDs.contains(marker.id) { return nil }
            let isCore = CoreBloodworkGuide.isCoreMarker(marker.id, catalogue: catalogue, sex: sex)
            let latest = latestByMarker[marker.id]
            let reading = latest.map {
                LabReader.read(result: $0, marker: marker, preferences: preferences, draw: drawsByID[$0.drawID], genotypes: genotypes)
            }
            return MarkerLibraryRowViewModel(
                marker: marker, isCore: isCore, latest: latest,
                reading: reading, isRetestDue: dueIDs.contains(marker.id))
        }

        var quickCounts: [MarkerQuickFilter: Int] = [:]
        for q in MarkerQuickFilter.allCases {
            let f = MarkerCustomFilter.fromQuick(q)
            quickCounts[q] = candidateRows.filter { matches($0, filter: f) }.count
        }

        let activeFilter: MarkerCustomFilter = {
            if let customFilter, customFilter.isActive { return customFilter }
            return MarkerCustomFilter.fromQuick(quickFilter)
        }()

        let matched = candidateRows.filter { matches($0, filter: activeFilter) }
        var chaptersOrder: [String] = []
        for row in matched where !chaptersOrder.contains(row.marker.chapter) { chaptersOrder.append(row.marker.chapter) }
        let sections = chaptersOrder.map { ch in
            MarkerLibrarySectionViewModel(chapter: ch, rows: matched.filter { $0.marker.chapter == ch })
        }

        return MarkerLibraryViewModel(allChapters: allChapters, quickCounts: quickCounts, sections: sections)
    }

    public static func isTestable(_ marker: LabMarker) -> Bool {
        if marker.isOverview { return false }
        return !marker.units.isEmpty || !marker.bands.isEmpty || !marker.strata.isEmpty || marker.computed || marker.formula != nil
    }

    private static func matches(_ row: MarkerLibraryRowViewModel, filter: MarkerCustomFilter) -> Bool {
        if !filter.chapters.isEmpty && !filter.chapters.contains(row.marker.chapter) { return false }

        // Overview / non-testable guide lessons have no measurable blood value, so exclude them from active filters.
        if !isTestable(row.marker) && filter.isActive { return false }

        switch filter.tier {
        case .any: break
        case .core: if !row.isCore { return false }
        case .nonCore: if row.isCore { return false }
        }

        switch filter.completion {
        case .any: break
        case .done: if row.latest == nil { return false }
        case .notDone: if row.latest != nil { return false }
        case .retestDue: if !row.isRetestDue { return false }
        }

        switch filter.status {
        case .any: break
        case .optimal: if row.reading?.status != .optimal { return false }
        case .high: if row.reading?.status != .high { return false }
        case .low: if row.reading?.status != .low { return false }
        case .disputed: if row.reading?.status != .disputed { return false }
        case .outOfOptimal:
            guard let st = row.reading?.status, st == .high || st == .low else { return false }
        }

        return true
    }
}
