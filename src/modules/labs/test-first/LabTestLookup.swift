import Foundation

/// Matches the free-text test names the supplement library asks for ("B12 (check first)", "CBC (MCV)") to catalogue
/// markers, and says what the owner's latest result was.
public struct LabTestLookup {
    private let catalogue: LabCatalogue
    private let draws: LabDrawService
    private let sex: LabSex

    public init(catalogue: LabCatalogue, draws: LabDrawService, sex: LabSex) {
        self.catalogue = catalogue
        self.draws = draws
        self.sex = sex
    }

    public func marker(forTest test: String) -> LabMarker? { matches(test).first?.marker }

    public func markers(forTest test: String) -> [LabMarker] { matches(test).map(\.marker) }

    /// "Ferritin 40 ng/mL on 3 May 2026 (low)", "MMA not tested yet", or the name as written when no marker matches.
    /// A name holding several tests gets one part per test, joined by "; ".
    public func summary(of test: String) throws -> String {
        let found = matches(test)
        guard !found.isEmpty else { return test }
        return try found.map { part, marker in
            guard let latest = try draws.history(of: marker.id).first else { return "\(part) not tested yet" }
            return "\(marker.name) \(LabInsightsRule.number(latest.value)) \(latest.unit) on \(latest.date.dayMonthYear)\(status(latest, marker))"
        }.joined(separator: "; ")
    }

    /// The whole name first; failing that, each part split at "/", "," or " and ", so "ferritin / iron" finds both.
    private func matches(_ test: String) -> [(part: String, marker: LabMarker)] {
        let trimmed = test.trimmingCharacters(in: .whitespaces)
        if let whole = match(trimmed) { return [(trimmed, whole)] }
        let parts = trimmed.replacingOccurrences(of: " and ", with: ",").replacingOccurrences(of: "/", with: ",")
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var found: [(part: String, marker: LabMarker)] = []
        for part in parts where !part.isEmpty {
            if let marker = match(part), !found.contains(where: { $0.marker.id == marker.id }) { found.append((part, marker)) }
        }
        return found
    }

    /// The name, without its bracket, or what is in the bracket; each also without a sample word in front ("serum zinc").
    private func match(_ name: String) -> LabMarker? {
        var candidates = [name]
        if let open = name.firstIndex(of: "("), let close = name[open...].firstIndex(of: ")") {
            candidates.append(String(name[..<open]).trimmingCharacters(in: .whitespaces))
            candidates.append(String(name[name.index(after: open)..<close]).trimmingCharacters(in: .whitespaces))
        }
        candidates += candidates.compactMap { candidate in
            Self.sampleWords.first { candidate.lowercased().hasPrefix($0) }.map { String(candidate.dropFirst($0.count)) }
        }
        for candidate in candidates where !candidate.isEmpty {
            if let found = catalogue.markers.first(where: { marker in
                ([marker.id, marker.name] + marker.aliases).contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            }) { return found }
        }
        return nil
    }

    private static let sampleWords = ["blood ", "serum ", "plasma ", "whole-blood "]

    private func status(_ result: LabResult, _ marker: LabMarker) -> String {
        switch LabReader.read(value: result.value, unit: result.unit, marker: marker, sex: sex).status {
        case .optimal: return " (optimal)"
        case .low: return " (low)"
        case .high: return " (high)"
        case .disputed: return " (disputed zone)"
        case .noOptimalBand, .notComparable: return ""
        }
    }
}

extension ISODate {
    private static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// "3 May 2026", for text the labs features write.
    var dayMonthYear: String {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]) else { return string }
        return "\(parts[2]) \(Self.monthNames[parts[1] - 1]) \(parts[0])"
    }
}
