import Foundation

public enum LabBadgeTone: String, Equatable {
    case green, amber, red, grey
}

public struct GeneRowViewModel: Equatable, Identifiable {
    public let id: String
    public let gene: LabGene
    public let subtitle: String?
    public let pickedGenotype: String?
    public let pickedTone: LabBadgeTone
    public let changeNothingBadge: String?
    public var triageBadge: String? = nil
    public var directPhenotypeNote: String? = nil
    public var requiresClinicalGradeAssay: Bool = false
}

public enum GeneticsQuickFilter: String, CaseIterable, Equatable, Identifiable {
    case all = "All"
    case worthKnowing = "Worth knowing"
    case conditionalTriggered = "Conditional · Triggered"
    case conditionalAll = "Conditional"
    case logged = "Logged"
    case notTested = "Not tested"
    case skipDoNotBuy = "Skip / Do Not Buy"

    public var id: String { rawValue }
}

public struct GeneSectionViewModel: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let genes: [GeneRowViewModel]
}

public struct GeneticsScreenViewModel: Equatable {
    public let needsContextPrompt: Bool
    public let contextSummary: String
    public let preferences: LabPreferences
    public let activeFindings: [Insight]
    public let reverseRecommendations: [LabReverseGeneticRecommendation]
    public let sections: [GeneSectionViewModel]
    public var quickCounts: [GeneticsQuickFilter: Int] = [:]
    public var totalMatched: Int = 0
}

public struct VerifierRowViewModel: Equatable, Identifiable {
    public var id: String { "\(markerID ?? markerName)-\(badge)" }
    public let markerID: String?
    public let markerName: String
    public let badge: String
    public let badgeTone: LabBadgeTone
    public let rule: String
}

public struct GeneDetailViewModel: Equatable {
    public let gene: LabGene
    public let selectedRow: LabGenotype?
    public let riskBadge: String?
    public let riskLevelTone: LabBadgeTone
    public let showChangeNothingBanner: Bool
    public let substitutions: [LabFormSubstitution]
    public let verifiers: [VerifierRowViewModel]
    public let shiftLines: [String]
    public let epistaticCells: [LabEpistaticCell]
    public let contraindications: [LabHardContraindication]
    public let whatNotToDo: [String]
    public let caveatLines: [String]
    public let requiresClinicalGradeAssay: Bool
    public let clinicalGradeWarning: String?
}

/// Pure view-model builder for Genetics screens so grouping, context summaries, and badges are unit-tested without SwiftUI.
public enum GeneticsPresenter {
    private static let categoryOrder: [(id: String, title: String, subtitle: String)] = [
        ("hard_contraindication", "Hard safety rules & doctor referrals",
         "Red-line medication, hormone, and supplement rules that require a clinician."),
        ("nutrient_swap", "Changes the form you take",
         "Swaps synthetic or poorly converted forms when bloodwork or diet shows a bottleneck."),
        ("marker_shift", "Changes how a blood marker is read",
         "Standard lab markers that lose their vote or need a specialty confirmer."),
        ("priority_shift", "Tightens targets & screening timing",
         "Tighter ApoB, caffeine, alcohol, or post-meal glucose rules."),
        ("change_nothing", "Skip / Do Not Buy — Test Phenotype Directly",
         "Genotype alone never justifies supplements or training changes; order the direct blood or clinical test instead.")
    ]

    private static let legacyBuckets: [(id: String, title: String)] = [
        ("doctor", "Take to a doctor"),
        ("take", "Changes the form you take"),
        ("read", "Changes how a result is read"),
        ("priority", "Changes what to check first"),
        ("nothing", "Changes nothing"),
        ("ignore", "Changes nothing")
    ]

    public static func screen(catalogue: LabCatalogue, db: Database, today: ISODate,
                              search: String = "", quickFilter: GeneticsQuickFilter = .all) throws -> GeneticsScreenViewModel {
        let prefs = try LabSettings(db).load()
        let genotypes = try GeneticsService(db, catalogue: catalogue).entries()
        let entryByID = Dictionary(uniqueKeysWithValues: genotypes.map { ($0.gene.id, $0) })

        let draws = LabDrawService(db, catalogue: catalogue)
        let allDraws = try draws.draws()
        let (latestByMarker, _, _) = try draws.latestResultsSnapshot()
        let latestResults = Array(latestByMarker.values)
        let findings = GeneticsModifierEvaluator.evaluateInsights(
            on: today, db: db, genotypes: genotypes, preferences: prefs,
            latestResults: latestResults, latestDraw: allDraws.first?.draft)
        let reverseRecs = GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: genotypes,
            preferences: prefs, latestResults: latestResults)
        let triggeredIDs = Set(reverseRecs.map(\.geneID))

        var rawSections: [GeneSectionViewModel] = []
        let categorizedGenes = catalogue.genes.filter { $0.actionCategory != nil }
        if !categorizedGenes.isEmpty {
            for cat in categoryOrder {
                let matching = catalogue.genes.filter { $0.actionCategory?.rawValue == cat.id }
                guard !matching.isEmpty else { continue }
                rawSections.append(GeneSectionViewModel(
                    id: cat.id, title: cat.title, subtitle: cat.subtitle,
                    genes: matching.map { rowVM($0, entry: entryByID[$0.id]) }))
            }
        }
        let uncategorized = catalogue.genes.filter { $0.actionCategory == nil }
        if !uncategorized.isEmpty {
            for b in legacyBuckets {
                let matching = uncategorized.filter { $0.bucket == b.id }
                guard !matching.isEmpty else { continue }
                rawSections.append(GeneSectionViewModel(
                    id: b.id, title: b.title, subtitle: nil,
                    genes: matching.map { rowVM($0, entry: entryByID[$0.id]) }))
            }
        }

        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let searchMatchedSections: [GeneSectionViewModel] = rawSections.map { sec in
            let rows = sec.genes.filter { matchesSearch($0, query: trimmedSearch) }
            return GeneSectionViewModel(id: sec.id, title: sec.title, subtitle: sec.subtitle, genes: rows)
        }
        let allSearchMatchedRows = searchMatchedSections.flatMap(\.genes)

        var quickCounts: [GeneticsQuickFilter: Int] = [:]
        for q in GeneticsQuickFilter.allCases {
            quickCounts[q] = allSearchMatchedRows.filter { matchesQuickFilter($0, filter: q, triggeredIDs: triggeredIDs) }.count
        }

        let filteredSections: [GeneSectionViewModel] = searchMatchedSections.compactMap { sec in
            let rows = sec.genes.filter { matchesQuickFilter($0, filter: quickFilter, triggeredIDs: triggeredIDs) }
            guard !rows.isEmpty else { return nil }
            return GeneSectionViewModel(id: sec.id, title: sec.title, subtitle: sec.subtitle, genes: rows)
        }
        let totalMatched = filteredSections.reduce(0) { $0 + $1.genes.count }

        return GeneticsScreenViewModel(
            needsContextPrompt: !prefs.isContextConfirmed,
            contextSummary: formatContextSummary(prefs),
            preferences: prefs,
            activeFindings: findings,
            reverseRecommendations: reverseRecs,
            sections: filteredSections,
            quickCounts: quickCounts,
            totalMatched: totalMatched)
    }

    private static func matchesSearch(_ row: GeneRowViewModel, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        if row.gene.name.localizedCaseInsensitiveContains(query) { return true }
        if row.gene.id.localizedCaseInsensitiveContains(query) { return true }
        if let v = row.gene.variant, v.localizedCaseInsensitiveContains(query) { return true }
        if row.gene.symbols.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        return false
    }

    private static func matchesQuickFilter(_ row: GeneRowViewModel, filter: GeneticsQuickFilter, triggeredIDs: Set<String>) -> Bool {
        let isSkip = row.gene.changeNothingMandate || row.gene.actionCategory == .changeNothing
        let isConditional = row.triageBadge == "Conditional — Test If Triggered" || triggeredIDs.contains(row.id)
        let isWorth = row.triageBadge == "Worth Knowing Once" && !isSkip
        switch filter {
        case .all:
            return true
        case .worthKnowing:
            return isWorth
        case .conditionalTriggered:
            return triggeredIDs.contains(row.id)
        case .conditionalAll:
            return isConditional && !isSkip
        case .logged:
            return row.pickedGenotype != nil
        case .notTested:
            return row.pickedGenotype == nil
        case .skipDoNotBuy:
            return isSkip
        }
    }

    public static func formatContextSummary(_ prefs: LabPreferences) -> String {
        var parts: [String] = ["TRT/HRT: \(prefs.onTRTOrHRT ? "On" : "Off")"]
        if prefs.activeMedications.isEmpty {
            parts.append("Rx: None")
        } else {
            let names = prefs.activeMedications.map(\.title).sorted()
            parts.append("Rx: \(names.joined(separator: ", "))")
        }
        parts.append("Regular alcohol: \(prefs.drinksAlcoholRegularly ? "Yes" : "No")")
        parts.append("Reverse DNA suggestions: \(prefs.reverseGeneticsEnabled ? "On" : "Off")")
        return parts.joined(separator: " · ")
    }

    public static func detail(gene: LabGene, pickedGenotype: String?) -> GeneDetailViewModel {
        let row = gene.genotypes?.first { $0.genotype == pickedGenotype }
        let (badge, tone) = riskPresentation(row?.riskLevel, urgency: row?.urgency)

        let verifiers: [VerifierRowViewModel] = gene.phenotypicVerifiers
            .filter { $0.kind != .nonLab }
            .map { v in
                let (vBadge, vTone): (String, LabBadgeTone) = {
                    if v.kind == .externalLab { return ("External lab test", .amber) }
                    if v.kind == .pattern { return ("Multi-marker pattern", .green) }
                    switch v.role {
                    case "outranks_genotype": return ("Outranks genotype", .green)
                    case "safety_gate": return ("Safety gate", .red)
                    case "mandatory_confirmer": return ("Mandatory confirmer", .amber)
                    default: return ("Bloodwork check", .grey)
                    }
                }()
                return VerifierRowViewModel(markerID: v.markerID, markerName: v.markerName, badge: vBadge, badgeTone: vTone, rule: v.rule)
            }

        var shifts: [String] = []
        if let ts = gene.thresholdShifts {
            if let yrs = ts.advanceScreeningYears, yrs > 0 {
                shifts.append("Start screening \(yrs) years earlier than standard population guidelines.")
            }
            shifts += ts.tightenedTargets
            shifts += ts.behavioralStrictness
        }

        var caveats: [String] = []
        if let c = gene.caveats {
            caveats += c.dtcBlindSpots.map { "Consumer chip limit: \($0)" }
            caveats += c.ancestryDiscrepancies.map { "Ancestry note: \($0)" }
            caveats += c.timingOrAssayTraps.map { "Timing / assay trap: \($0)" }
        }

        let requiresClinical = GeneticsModifierEvaluator.requiresClinicalGradeAssay(geneID: gene.id)
        let clinicalWarn = GeneticsModifierEvaluator.clinicalGradeWarning(for: gene.id)

        return GeneDetailViewModel(
            gene: gene,
            selectedRow: row,
            riskBadge: badge,
            riskLevelTone: tone,
            showChangeNothingBanner: gene.changeNothingMandate || gene.actionCategory == .changeNothing,
            substitutions: gene.formSubstitutions,
            verifiers: verifiers,
            shiftLines: shifts,
            epistaticCells: gene.epistaticGrid,
            contraindications: gene.hardContraindications,
            whatNotToDo: gene.whatNotToDo,
            caveatLines: caveats,
            requiresClinicalGradeAssay: requiresClinical,
            clinicalGradeWarning: clinicalWarn)
    }

    public static func directPhenotypeLabel(for gene: LabGene) -> String? {
        guard gene.changeNothingMandate || gene.actionCategory == .changeNothing else { return nil }
        let names = gene.phenotypicVerifiers.map(\.markerName).filter { !$0.isEmpty }
        if !names.isEmpty {
            return "Test phenotype directly: \(names.prefix(3).joined(separator: ", "))"
        }
        switch gene.id {
        case "vdr": return "Test phenotype directly: 25(OH)D, PTH, Calcium"
        case "lpa-gene": return "Test phenotype directly: Serum Lp(a) particle count (nmol/L)"
        case "gstm1-gstt1": return "Test phenotype directly: GGT, ALT, AST, Bilirubin"
        case "salt-sensitivity": return "Test phenotype directly: 2-week home blood pressure cuff"
        case "actn3-ace": return "Test phenotype directly: Training block progression"
        case "sod2": return "Test phenotype directly: Routine inflammation & mineral markers"
        default: return "Test phenotype directly instead of genotype"
        }
    }

    private static func rowVM(_ gene: LabGene, entry: GenotypeEntry?) -> GeneRowViewModel {
        let subtitle = gene.variant ?? (gene.symbols.isEmpty ? nil : gene.symbols.joined(separator: " · "))
        let (_, tone) = riskPresentation(entry?.row.riskLevel, urgency: entry?.row.urgency)
        let isChangeNothing = gene.changeNothingMandate || gene.actionCategory == .changeNothing
        let isConditionalOnly = gene.actionCategory == .hardContraindication || gene.id == "hla-dq2-dq8" || gene.id == "lct-mcm6"
        let triage: String = {
            if isChangeNothing { return "Skip / Do Not Buy — Test Phenotype Directly" }
            if isConditionalOnly { return "Conditional — Test If Triggered" }
            return "Worth Knowing Once"
        }()
        return GeneRowViewModel(
            id: gene.id,
            gene: gene,
            subtitle: subtitle,
            pickedGenotype: entry?.row.genotype,
            pickedTone: entry == nil ? .grey : tone,
            changeNothingBadge: isChangeNothing ? "Bloodwork wins" : nil,
            triageBadge: triage,
            directPhenotypeNote: directPhenotypeLabel(for: gene),
            requiresClinicalGradeAssay: GeneticsModifierEvaluator.requiresClinicalGradeAssay(geneID: gene.id))
    }

    public static func riskPresentation(_ riskLevel: String?, urgency: LabUrgency?) -> (String?, LabBadgeTone) {
        if urgency == .sameDay { return ("Same-day safety rule", .red) }
        switch riskLevel {
        case "contraindicated": return ("Contraindication", .red)
        case "high_impact": return ("High impact", .amber)
        case "moderate_modifier": return ("Moderate modifier", .green)
        case "mild_modifier": return ("Mild modifier", .green)
        case "informational_only": return ("Informational only", .grey)
        case "baseline": return ("Baseline / typical", .grey)
        default:
            if urgency == .soon { return ("Doctor review", .amber) }
            return (nil, .green)
        }
    }
}
