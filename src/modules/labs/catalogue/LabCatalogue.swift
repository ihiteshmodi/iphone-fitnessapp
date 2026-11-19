import Foundation

/// The bloodwork and genetics volumes as data, read from a bundled file (the vault's content, git-ignored).
/// The app is a generic engine over it: no vault number lives in code.
public struct LabCatalogue {
    public let markers: [LabMarker]
    public let panels: [LabPanel]
    public let prep: [LabPrepStep]
    public let patterns: [LabPattern]
    public let genes: [LabGene]
    /// The genetics volume's testing tiers, core rules and failures to avoid.
    public let geneticsGuide: [LabGuideItem]

    private struct File: Decodable {
        let markers: [LabMarker]?
        let panels: [LabPanel]?
        let prep: [LabPrepStep]?
        let patterns: [LabPattern]?
        let genes: [LabGene]?
        let geneticsGuide: [LabGuideItem]?
    }

    public init(data: Data) throws {
        let file: File
        do { file = try JSONDecoder().decode(File.self, from: data) } catch { throw ValidationError("The labs catalogue could not be read: \(error)") }
        self.init(markers: file.markers ?? [], panels: file.panels ?? [], prep: file.prep ?? [], patterns: file.patterns ?? [],
                  genes: file.genes ?? [], geneticsGuide: file.geneticsGuide ?? [])
    }

    public init(markers: [LabMarker] = [], panels: [LabPanel] = [], prep: [LabPrepStep] = [], patterns: [LabPattern] = [], genes: [LabGene] = [],
                geneticsGuide: [LabGuideItem] = []) {
        self.markers = markers
        self.panels = panels
        self.prep = prep
        self.patterns = patterns
        self.genes = genes
        self.geneticsGuide = geneticsGuide
    }

    public func marker(_ id: String) -> LabMarker? { markers.first { $0.id == id } }
    public func panel(_ id: String) -> LabPanel? { panels.first { $0.id == id } }
    public func prepStep(_ id: String) -> LabPrepStep? { prep.first { $0.id == id } }
    public func gene(_ id: String) -> LabGene? { genes.first { $0.id == id } }

    /// Name and aliases, ignoring case; every word typed must match.
    public func search(_ text: String) -> [LabMarker] {
        let words = text.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return markers }
        return markers.filter { marker in
            let haystack = ([marker.name] + marker.aliases).joined(separator: " ").lowercased()
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}

public enum LabSex: String, Codable, Equatable { case male, female, any }

public enum LabUrgency: String, Codable, Equatable, Comparable {
    case goNow, sameDay, urgent, fewDays, soon, routine

    /// Most urgent first.
    private var rank: Int { [.goNow: 0, .sameDay: 1, .urgent: 2, .fewDays: 3, .soon: 4, .routine: 5][self]! }
    public static func < (lhs: LabUrgency, rhs: LabUrgency) -> Bool { lhs.rank < rhs.rank }

    public var title: String {
        switch self {
        case .goNow: return "Go now"
        case .sameDay: return "Same day"
        case .urgent: return "Urgent"
        case .fewDays: return "Within a few days"
        case .soon: return "Soon"
        case .routine: return "Routine"
        }
    }
}

public enum LabOrigin: String, Codable, Equatable { case vault, research, owner }

public struct LabText: Codable, Equatable {
    public let text: String
    public let tag: String?
    public let when: String?
    public let markers: [String]?

    enum CodingKeys: String, CodingKey { case text, tag, when, markers }

    /// Written either as a plain sentence or as an object with a tag.
    public init(from decoder: Decoder) throws {
        if let plain = try? decoder.singleValueContainer().decode(String.self) {
            text = plain; tag = nil; when = nil; markers = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        tag = try c.decodeIfPresent(String.self, forKey: .tag)
        when = try c.decodeIfPresent(String.self, forKey: .when)
        markers = try c.decodeIfPresent([String].self, forKey: .markers)
    }
}

public struct LabUnit: Codable, Equatable {
    public let unit: String
    public let isDefault: Bool
    /// Multiply a value in this unit to get the default unit. Only where the vault states the factor.
    public let toDefault: Double?

    enum CodingKeys: String, CodingKey { case unit, isDefault = "default", toDefault }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unit = try c.decode(String.self, forKey: .unit)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        toDefault = try c.decodeIfPresent(Double.self, forKey: .toDefault)
    }
}

public struct LabBand: Codable, Equatable {
    public let label: String
    public let kind: String
    public let low: Double?
    public let high: Double?
    public let unit: String?
    public let sex: LabSex?
    public let source: String?
    public let lowInclusive: Bool?
    public let highInclusive: Bool?
    public let meaning: String?
    public let condition: String?
    public let dispute: String?
    public let tag: String?
    public let origin: LabOrigin?
    /// Result words for qualitative tests (urine dipstick: "Negative", "Trace"...).
    public let values: [String]?
}

/// A doctor trigger. op and value are nil when the trigger is signs only or relative to the lab's range; those are
/// shown as text and never raised automatically.
public struct LabDoctorLine: Codable, Equatable {
    public let op: String?
    public let value: Double?
    public let unit: String?
    public let sex: LabSex?
    public let urgency: LabUrgency
    public let text: String
    public let source: String?
    public let requires: String?
    public let tag: String?
    public let origin: LabOrigin?
}

public struct LabRetest: Codable, Equatable {
    public let text: String
    public let minWeeks: Double?
    public let maxWeeks: Double?
    public let minMonths: Double?
    public let maxMonths: Double?
    public let after: String?
    public let source: String?
}

public struct LabDispute: Codable, Equatable {
    public let id: String
    public let topic: String?
    public let a: String?
    public let b: String?
    public let resolution: String?
    public let confidence: String?
}

public struct LabLinks: Codable, Equatable {
    public let supplements: [String]?
    public let markers: [String]?
    public let genes: [String]?
}

public struct LabMarker: Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let aliases: [String]
    public let chapter: String
    public let lesson: String
    public let units: [LabUnit]
    public let sample: String?
    public let needsLabRange: Bool
    public let computed: Bool
    public let what: String?
    public let howTested: [String]
    public let pushesUp: [LabText]
    public let pushesDown: [LabText]
    public let nextTo: [LabText]
    public let whatToDo: [LabText]
    public let other: [LabText]
    public let bands: [LabBand]
    public let doctor: [LabDoctorLine]
    public let retest: [LabRetest]
    public let prep: [String]
    public let disputes: [LabDispute]
    public let links: LabLinks?
    public let formula: LabFormula?

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, chapter, lesson, units, sample, needsLabRange, computed, what, howTested, pushesUp, pushesDown
        case nextTo, whatToDo, other, bands, doctor, retest, prep, disputes, links, formula
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        chapter = try c.decodeIfPresent(String.self, forKey: .chapter) ?? ""
        lesson = try c.decodeIfPresent(String.self, forKey: .lesson) ?? ""
        units = try c.decodeIfPresent([LabUnit].self, forKey: .units) ?? []
        sample = try c.decodeIfPresent(String.self, forKey: .sample)
        needsLabRange = try c.decodeIfPresent(Bool.self, forKey: .needsLabRange) ?? false
        computed = try c.decodeIfPresent(Bool.self, forKey: .computed) ?? false
        what = try c.decodeIfPresent(String.self, forKey: .what)
        howTested = try Self.texts(c, .howTested)
        pushesUp = try c.decodeIfPresent([LabText].self, forKey: .pushesUp) ?? []
        pushesDown = try c.decodeIfPresent([LabText].self, forKey: .pushesDown) ?? []
        nextTo = try c.decodeIfPresent([LabText].self, forKey: .nextTo) ?? []
        whatToDo = try c.decodeIfPresent([LabText].self, forKey: .whatToDo) ?? []
        other = try c.decodeIfPresent([LabText].self, forKey: .other) ?? []
        bands = try c.decodeIfPresent([LabBand].self, forKey: .bands) ?? []
        doctor = try c.decodeIfPresent([LabDoctorLine].self, forKey: .doctor) ?? []
        retest = try c.decodeIfPresent([LabRetest].self, forKey: .retest) ?? []
        prep = try c.decodeIfPresent([String].self, forKey: .prep) ?? []
        disputes = try c.decodeIfPresent([LabDispute].self, forKey: .disputes) ?? []
        links = try c.decodeIfPresent(LabLinks.self, forKey: .links)
        formula = try c.decodeIfPresent(LabFormula.self, forKey: .formula)
    }

    /// howTested may be written as one sentence or a list.
    private static func texts(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [String] {
        if let list = try? c.decodeIfPresent([String].self, forKey: key) { return list }
        return (try c.decodeIfPresent(String.self, forKey: key)).map { [$0] } ?? []
    }

    public var defaultUnit: String? { units.first { $0.isDefault }?.unit ?? units.first?.unit }

    /// A calculated ratio has no unit, so its unit-less bands and values compare as they are.
    public var isUnitlessRatio: Bool { computed && (defaultUnit == nil || defaultUnit == "ratio") }

    /// The value in the default unit, or nil when the unit is unknown or has no stated factor.
    public func toDefault(_ value: Double, unit: String) -> Double? {
        if unit == defaultUnit || (isUnitlessRatio && (unit.isEmpty || unit == "ratio")) { return value }
        return units.first { $0.unit == unit }?.toDefault.map { value * $0 }
    }
}

/// A formula the vault quotes, written with {marker-id} inputs, each read in the stated unit, from one draw.
public struct LabFormula: Codable, Equatable {
    public let expr: String
    public let inputs: [String: String]
    /// Only worked out when this holds (for example the vault's "apply when glucose is above 100").
    public let onlyIf: String?
    public let source: String?
}

public struct LabPanel: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let markers: [String]
    public let askFor: String?
    public let when: String?
    public let trigger: String?
    public let triggerMarkers: [String]?
    public let source: String?
    public let tag: String?
}

public struct LabPrepStep: Codable, Equatable, Identifiable {
    public let id: String
    public let text: String
    public let hoursBefore: Double?
    public let markers: [String]?
    public let source: String?
    public let tag: String?
}

/// op may also be "high", "low" or "normal" against the lab's range, with no value.
public struct LabCondition: Codable, Equatable {
    public let marker: String
    public let op: String
    public let value: Double?
    public let unit: String?
    public let sex: LabSex?
}

public enum LabNeeded: Codable, Equatable {
    case all, any, count(Int)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) { self = .count(n); return }
        self = (try c.decode(String.self)) == "any" ? .any : .all
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .all: try c.encode("all")
        case .any: try c.encode("any")
        case .count(let n): try c.encode(n)
        }
    }
}

public struct LabPattern: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let markers: [String]?
    public let conditions: [LabCondition]?
    public let needed: LabNeeded?
    public let repeatText: String?
    public let meaning: String?
    public let whatToDo: [String]?
    public let retest: String?
    public let doctor: String?
    public let computable: Bool?
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case id, name, markers, conditions, needed, repeatText = "repeat", meaning, whatToDo, retest, doctor, computable, source
    }
}

public struct LabGenotype: Codable, Equatable {
    public let genotype: String
    public let meaning: String?
    public let actions: [String]?
    public let addsMarkers: [String]?
    public let urgency: LabUrgency?
}

public struct LabGene: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let variant: String?
    public let bucket: String
    public let genotypes: [LabGenotype]?
    public let confirmWith: [String]?
    public let source: String?
}

public struct LabGuideItem: Codable, Equatable {
    public let text: String
    public let source: String?
    public let kind: String?
}
