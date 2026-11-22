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
    public let globalProtocols: LabGlobalProtocols?

    private struct File: Decodable {
        let markers: [LabMarker]?
        let panels: [LabPanel]?
        let prep: [LabPrepStep]?
        let patterns: [LabPattern]?
        let genes: [LabGene]?
        let geneticsGuide: [LabGuideItem]?
        let globalProtocols: LabGlobalProtocols?
    }

    public init(data: Data) throws {
        let file: File
        do { file = try JSONDecoder().decode(File.self, from: data) } catch { throw ValidationError("The labs catalogue could not be read: \(error)") }
        self.init(markers: file.markers ?? [], panels: file.panels ?? [], prep: file.prep ?? [], patterns: file.patterns ?? [],
                  genes: file.genes ?? [], geneticsGuide: file.geneticsGuide ?? [], globalProtocols: file.globalProtocols)
    }

    public init(markers: [LabMarker] = [], panels: [LabPanel] = [], prep: [LabPrepStep] = [], patterns: [LabPattern] = [], genes: [LabGene] = [],
                geneticsGuide: [LabGuideItem] = [], globalProtocols: LabGlobalProtocols? = nil) {
        self.markers = markers
        self.panels = panels
        self.prep = prep
        self.patterns = patterns
        self.genes = genes
        self.geneticsGuide = geneticsGuide
        self.globalProtocols = globalProtocols
    }

    public func marker(_ id: String) -> LabMarker? { markers.first { $0.id == id } }
    public func markerByLessonOrID(_ key: String) -> LabMarker? {
        marker(key) ?? markers.first { $0.lessonID == key || $0.lesson == key }
    }
    public func visibleMarkers(for sex: LabSex) -> [LabMarker] {
        markers.filter { $0.applies(to: sex) }
    }
    public func panel(_ id: String) -> LabPanel? { panels.first { $0.id == id } }
    public func prepStep(_ id: String) -> LabPrepStep? { prep.first { $0.id == id } }
    public func gene(_ id: String) -> LabGene? {
        genes.first { $0.id == id } ?? genes.first { $0.legacyIDs.contains(id) || $0.entryID == id }
    }

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

public enum LabSex: String, Codable, Equatable {
    case male, female, any

    public func allows(sex itemSex: LabSex?, tag: String? = nil, showDrugNotes: Bool = true) -> Bool {
        if tag == "drug" && !showDrugNotes { return false }
        if tag == "female" && self == .male { return false }
        if tag == "male" && self == .female { return false }
        guard let itemSex, itemSex != .any, self != .any else { return true }
        return itemSex == self
    }
}

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
    /// Optional linear offset added after multiplying by `toDefault` (for affine scales such as IFCC mmol/mol -> NGSP %).
    public let toDefaultOffset: Double?

    enum CodingKeys: String, CodingKey { case unit, isDefault = "default", toDefault, toDefaultOffset }

    public init(unit: String, isDefault: Bool = false, toDefault: Double? = nil, toDefaultOffset: Double? = nil) {
        self.unit = unit
        self.isDefault = isDefault
        self.toDefault = toDefault
        self.toDefaultOffset = toDefaultOffset
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        unit = try c.decode(String.self, forKey: .unit)
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        toDefault = try c.decodeIfPresent(Double.self, forKey: .toDefault)
        toDefaultOffset = try c.decodeIfPresent(Double.self, forKey: .toDefaultOffset)
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
    public let lessonID: String?
    public let isOverview: Bool
    public let coTests: [String]
    public let discordance: [String]
    public let strata: [LabStratum]
    public let preAnalytic: LabPreAnalytic?
    public let specimens: [LabSpecimenAssay]
    public let interventions: LabInterventions?
    public let escalation: LabEscalation?

    enum CodingKeys: String, CodingKey {
        case id, name, aliases, chapter, lesson, units, sample, needsLabRange, computed, what, howTested, pushesUp, pushesDown
        case nextTo, whatToDo, other, bands, doctor, retest, prep, disputes, links, formula
        case lessonID, isOverview, coTests, discordance, strata, preAnalytic, specimens, interventions, escalation
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
        lessonID = try c.decodeIfPresent(String.self, forKey: .lessonID)
        isOverview = try c.decodeIfPresent(Bool.self, forKey: .isOverview) ?? false
        coTests = try c.decodeIfPresent([String].self, forKey: .coTests) ?? []
        discordance = try c.decodeIfPresent([String].self, forKey: .discordance) ?? []
        strata = try c.decodeIfPresent([LabStratum].self, forKey: .strata) ?? []
        preAnalytic = try c.decodeIfPresent(LabPreAnalytic.self, forKey: .preAnalytic)
        specimens = try c.decodeIfPresent([LabSpecimenAssay].self, forKey: .specimens) ?? []
        interventions = try c.decodeIfPresent(LabInterventions.self, forKey: .interventions)
        escalation = try c.decodeIfPresent(LabEscalation.self, forKey: .escalation)
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
        guard let spec = units.first(where: { $0.unit == unit }), let factor = spec.toDefault else { return nil }
        return value * factor + (spec.toDefaultOffset ?? 0)
    }

    public func fromDefault(_ defaultValue: Double, to unit: String) -> Double? {
        if unit == defaultUnit || (isUnitlessRatio && (unit.isEmpty || unit == "ratio")) { return defaultValue }
        guard let spec = units.first(where: { $0.unit == unit }), let factor = spec.toDefault, factor != 0 else { return nil }
        return (defaultValue - (spec.toDefaultOffset ?? 0)) / factor
    }

    public func applies(to sex: LabSex) -> Bool {
        guard !isOverview else { return false }
        guard sex != .any else { return true }
        let declaredSexes = strata.map(\.sex) + bands.compactMap(\.sex)
        guard !declaredSexes.isEmpty else { return true }
        return declaredSexes.contains { $0 == .any || $0 == sex }
    }

    public func visibleBands(for sex: LabSex) -> [LabBand] {
        bands.filter { sex.allows(sex: $0.sex, tag: $0.tag) }
    }

    public func visibleText(_ items: [LabText], sex: LabSex, showDrugNotes: Bool) -> [LabText] {
        items.filter { sex.allows(sex: nil, tag: $0.tag, showDrugNotes: showDrugNotes) }
    }

    public func visibleDoctorLines(sex: LabSex, showDrugNotes: Bool) -> [LabDoctorLine] {
        doctor.filter { sex.allows(sex: $0.sex, tag: $0.tag, showDrugNotes: showDrugNotes) }
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
    public let drawNotes: [String: String]?

    public init(id: String, name: String, markers: [String], askFor: String? = nil, when: String? = nil, trigger: String? = nil,
                triggerMarkers: [String]? = nil, source: String? = nil, tag: String? = nil, drawNotes: [String: String]? = nil) {
        self.id = id
        self.name = name
        self.markers = markers
        self.askFor = askFor
        self.when = when
        self.trigger = trigger
        self.triggerMarkers = triggerMarkers
        self.source = source
        self.tag = tag
        self.drawNotes = drawNotes
    }
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
    public let engine: LabPatternEngine?

    enum CodingKeys: String, CodingKey {
        case id, name, markers, conditions, needed, repeatText = "repeat", meaning, whatToDo, retest, doctor, computable, source, engine
    }
}

public struct LabStratumBand: Codable, Equatable {
    public let tier: String
    public let min: Double?
    public let max: Double?
    public let meaning: String?
}

public struct LabStratum: Codable, Equatable {
    public let population: String
    public let sex: LabSex
    public let unit: String?
    public let standardLow: Double?
    public let standardHigh: Double?
    public let optimalLow: Double?
    public let optimalHigh: Double?
    public let sweetSpot: String?
    public let bands: [LabStratumBand]
    public let ageMin: Int?
    public let ageMax: Int?
    public let cyclePhase: String?
    public let pregnancy: String?
    public let modifier: String?
    public let assay: String?
    public let requiresHRT: Bool?
}

public struct LabWashout: Codable, Equatable {
    public let item: String
    public let window: String
    public let effect: String
}

public struct LabPreAnalytic: Codable, Equatable {
    public let fastingRequired: Bool
    public let fastingHours: String?
    public let timingWindow: String?
    public let washouts: [LabWashout]
    public let sampleHandling: String?
    public let redrawTriggers: [String]
}

public struct LabSpecimenAssay: Codable, Equatable {
    public let matrix: String
    public let preferredAssay: String
    public let targetPopulation: String
    public let assayPitfall: String
}

public struct LabSupplementIntervention: Codable, Equatable {
    public let name: String
    public let dose: String?
    public let target: String?
    public let notes: String?
}

public struct LabInterventions: Codable, Equatable {
    public let tier1Foundations: [String]
    public let tier2Nutrition: [String]
    public let tier3Supplements: [LabSupplementIntervention]
    public let tier4Peptides: [String]
    public let whatNotToDo: [String]
}

public struct LabEscalation: Codable, Equatable {
    public let urgentSameDay: [String]
    public let routineSoon: [String]
    public let specialists: [String]
}

public struct LabRatioThreshold: Codable, Equatable {
    public let band: String
    public let condition: String
    public let min: Double?
    public let max: Double?
    public let meaning: String
}

public struct LabPatternRatio: Codable, Equatable {
    public let ratioID: String
    public let markerID: String?
    public let name: String
    public let formula: String
    public let scaleFactor: Double
    public let thresholds: [LabRatioThreshold]
}

public struct LabSignatureCondition: Codable, Equatable {
    public let target: String?
    public let rawTarget: String?
    public let state: String
    public let scaleFactor: Double
}

public struct LabPrimarySignature: Codable, Equatable {
    public let `operator`: String
    public let minMatches: Int?
    public let conditions: [LabSignatureCondition]
}

public struct LabPhenotypeRule: Codable, Equatable {
    public let target: String?
    public let condition: String
    public let scaleFactor: Double
}

public struct LabPhenotype: Codable, Equatable {
    public let name: String
    public let rules: [LabPhenotypeRule]
    public let interpretation: String
}

public struct LabProgressionStage: Codable, Equatable {
    public let stage: String
    public let criteria: String
    public let timeline: String?
}

public struct LabLookAlike: Codable, Equatable {
    public let condition: String
    public let howToRuleOut: String
}

public struct LabUpstreamCause: Codable, Equatable {
    public let driver: String
    public let mechanism: String
}

public struct LabConfoundingMedication: Codable, Equatable {
    public let medication: String
    public let effect: String
}

public struct LabPatternEngine: Codable, Equatable {
    public let patternID: String
    public let slug: String
    public let section: String
    public let markersRequired: [String]
    public let cofactorMarkers: [String]
    public let nonBloodInputs: [String]
    public let calculatedRatios: [LabPatternRatio]
    public let primarySignature: LabPrimarySignature
    public let phenotypes: [LabPhenotype]
    public let progressionStaging: [LabProgressionStage]
    public let differentialLookAlikes: [LabLookAlike]
    public let upstreamCauses: [LabUpstreamCause]
    public let confoundingMedications: [LabConfoundingMedication]
    public let interventions: LabInterventions
    public let escalation: LabEscalation
}

public struct LabDrawChecklist: Codable, Equatable {
    public let nightBefore: [String]
    public let morningOf: [String]
    public let postDraw: [String]
    public let loggingProtocol: [String]
}

public struct LabGlobalProtocols: Codable, Equatable {
    public let fastingHours: String?
    public let fastingAllowedIntake: String?
    public let fastingExemptMarkers: [String]
    public let recommendedDrawWindow: String?
    public let checklist: LabDrawChecklist
    public let emergencySymptoms: [String]
}

public enum LabGeneActionCategory: String, Codable, Equatable {
    case foundational
    case nutrientSwap = "nutrient_swap"
    case markerShift = "marker_shift"
    case priorityShift = "priority_shift"
    case changeNothing = "change_nothing"
    case hardContraindication = "hard_contraindication"
}

public enum LabVerifierKind: String, Codable, Equatable {
    case marker
    case pattern
    case externalLab = "external_lab"
    case nonLab = "non_lab"
}

public struct LabPhenotypicVerifier: Codable, Equatable {
    public let kind: LabVerifierKind
    public let markerID: String?
    public let patternID: String?
    public let markerName: String
    public let role: String
    public let rule: String
}

public struct LabEpistaticCell: Codable, Equatable {
    public let condition: String
    public let interpretation: String
    public let action: String
}

public struct LabThresholdShifts: Codable, Equatable {
    public let advanceScreeningYears: Int?
    public let tightenedTargets: [String]
    public let behavioralStrictness: [String]
}

public struct LabFormSubstitution: Codable, Equatable {
    public let replaceOrAvoid: String
    public let useInstead: String
    public let targetGenotypes: [String]
    public let crossVolumeRef: String?
}

public struct LabHardContraindication: Codable, Equatable {
    public let triggerGenotype: String
    public let forbiddenItems: [String]
    public let mandatoryReferral: String?
    public let coachStopLine: String
}

public struct LabGeneticsCaveats: Codable, Equatable {
    public let dtcBlindSpots: [String]
    public let ancestryDiscrepancies: [String]
    public let timingOrAssayTraps: [String]
}

public struct LabGenotype: Codable, Equatable {
    public let genotype: String
    public let meaning: String?
    public let actions: [String]?
    public let addsMarkers: [String]?
    public let urgency: LabUrgency?
    public let riskLevel: String?
    public let clinicalRule: String?

    public init(genotype: String, meaning: String? = nil, actions: [String]? = nil, addsMarkers: [String]? = nil,
                urgency: LabUrgency? = nil, riskLevel: String? = nil, clinicalRule: String? = nil) {
        self.genotype = genotype
        self.meaning = meaning
        self.actions = actions
        self.addsMarkers = addsMarkers
        self.urgency = urgency
        self.riskLevel = riskLevel
        self.clinicalRule = clinicalRule
    }

    public var isBaseline: Bool { riskLevel == "baseline" }
}

public struct LabGene: Codable, Equatable, Identifiable {
    public let id: String
    public let entryID: String?
    public let name: String
    public let title: String?
    public let symbols: [String]
    public let legacyIDs: [String]
    public let legacyGenotypes: [String]
    public let variant: String?
    public let bucket: String
    public let actionCategory: LabGeneActionCategory?
    public let coreThesis: String?
    public let mechanismSummary: String?
    public let genotypes: [LabGenotype]?
    public let confirmWith: [String]?
    public let phenotypicVerifiers: [LabPhenotypicVerifier]
    public let epistaticGrid: [LabEpistaticCell]
    public let thresholdShifts: LabThresholdShifts?
    public let changeNothingMandate: Bool
    public let formSubstitutions: [LabFormSubstitution]
    public let hardContraindications: [LabHardContraindication]
    public let whatNotToDo: [String]
    public let caveats: LabGeneticsCaveats?
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case id, entryID, name, title, symbols, legacyIDs, legacyGenotypes, variant, bucket, actionCategory
        case coreThesis, mechanismSummary, genotypes, confirmWith, phenotypicVerifiers, epistaticGrid
        case thresholdShifts, changeNothingMandate, formSubstitutions, hardContraindications, whatNotToDo, caveats, source
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        entryID = try c.decodeIfPresent(String.self, forKey: .entryID)
        name = try c.decode(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        symbols = try c.decodeIfPresent([String].self, forKey: .symbols) ?? []
        legacyIDs = try c.decodeIfPresent([String].self, forKey: .legacyIDs) ?? []
        legacyGenotypes = try c.decodeIfPresent([String].self, forKey: .legacyGenotypes) ?? []
        variant = try c.decodeIfPresent(String.self, forKey: .variant)
        bucket = try c.decode(String.self, forKey: .bucket)
        actionCategory = try c.decodeIfPresent(LabGeneActionCategory.self, forKey: .actionCategory)
        coreThesis = try c.decodeIfPresent(String.self, forKey: .coreThesis)
        mechanismSummary = try c.decodeIfPresent(String.self, forKey: .mechanismSummary)
        genotypes = try c.decodeIfPresent([LabGenotype].self, forKey: .genotypes)
        confirmWith = try c.decodeIfPresent([String].self, forKey: .confirmWith)
        phenotypicVerifiers = try c.decodeIfPresent([LabPhenotypicVerifier].self, forKey: .phenotypicVerifiers) ?? []
        epistaticGrid = try c.decodeIfPresent([LabEpistaticCell].self, forKey: .epistaticGrid) ?? []
        thresholdShifts = try c.decodeIfPresent(LabThresholdShifts.self, forKey: .thresholdShifts)
        changeNothingMandate = try c.decodeIfPresent(Bool.self, forKey: .changeNothingMandate) ?? false
        formSubstitutions = try c.decodeIfPresent([LabFormSubstitution].self, forKey: .formSubstitutions) ?? []
        hardContraindications = try c.decodeIfPresent([LabHardContraindication].self, forKey: .hardContraindications) ?? []
        whatNotToDo = try c.decodeIfPresent([String].self, forKey: .whatNotToDo) ?? []
        caveats = try c.decodeIfPresent(LabGeneticsCaveats.self, forKey: .caveats)
        source = try c.decodeIfPresent(String.self, forKey: .source)
    }
}

public struct LabGuideItem: Codable, Equatable {
    public let text: String
    public let source: String?
    public let kind: String?
}
