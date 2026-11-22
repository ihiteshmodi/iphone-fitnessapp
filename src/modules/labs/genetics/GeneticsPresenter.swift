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
    public let sections: [GeneSectionViewModel]
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
        ("change_nothing", "Changes nothing — bloodwork wins",
         "Genotype alone never justifies supplements or training changes.")
    ]

    private static let legacyBuckets: [(id: String, title: String)] = [
        ("doctor", "Take to a doctor"),
        ("take", "Changes the form you take"),
        ("read", "Changes how a result is read"),
        ("priority", "Changes what to check first"),
        ("nothing", "Changes nothing"),
        ("ignore", "Changes nothing")
    ]

    public static func screen(catalogue: LabCatalogue, db: Database, today: ISODate) throws -> GeneticsScreenViewModel {
        let prefs = try LabSettings(db).load()
        let genotypes = try GeneticsService(db, catalogue: catalogue).entries()
        let entryByID = Dictionary(uniqueKeysWithValues: genotypes.map { ($0.gene.id, $0) })

        let draws = LabDrawService(db, catalogue: catalogue)
        let allDraws = try draws.draws()
        let latestResults = try allDraws.first.map { try draws.results(inDraw: $0.id) } ?? []
        let findings = GeneticsModifierEvaluator.evaluateInsights(
            on: today, db: db, genotypes: genotypes, preferences: prefs,
            latestResults: latestResults, latestDraw: allDraws.first?.draft)

        var sections: [GeneSectionViewModel] = []
        let categorizedGenes = catalogue.genes.filter { $0.actionCategory != nil }
        if !categorizedGenes.isEmpty {
            for cat in categoryOrder {
                let matching = catalogue.genes.filter { $0.actionCategory?.rawValue == cat.id }
                guard !matching.isEmpty else { continue }
                sections.append(GeneSectionViewModel(
                    id: cat.id, title: cat.title, subtitle: cat.subtitle,
                    genes: matching.map { rowVM($0, entry: entryByID[$0.id]) }))
            }
        }
        let uncategorized = catalogue.genes.filter { $0.actionCategory == nil }
        if !uncategorized.isEmpty {
            for b in legacyBuckets {
                let matching = uncategorized.filter { $0.bucket == b.id }
                guard !matching.isEmpty else { continue }
                sections.append(GeneSectionViewModel(
                    id: b.id, title: b.title, subtitle: nil,
                    genes: matching.map { rowVM($0, entry: entryByID[$0.id]) }))
            }
        }

        return GeneticsScreenViewModel(
            needsContextPrompt: !prefs.isContextConfirmed,
            contextSummary: formatContextSummary(prefs),
            preferences: prefs,
            activeFindings: findings,
            sections: sections)
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
            caveatLines: caveats)
    }

    private static func rowVM(_ gene: LabGene, entry: GenotypeEntry?) -> GeneRowViewModel {
        let subtitle = gene.variant ?? (gene.symbols.isEmpty ? nil : gene.symbols.joined(separator: " · "))
        let (_, tone) = riskPresentation(entry?.row.riskLevel, urgency: entry?.row.urgency)
        return GeneRowViewModel(
            id: gene.id,
            gene: gene,
            subtitle: subtitle,
            pickedGenotype: entry?.row.genotype,
            pickedTone: entry == nil ? .grey : tone,
            changeNothingBadge: (gene.changeNothingMandate || gene.actionCategory == .changeNothing) ? "Bloodwork wins" : nil)
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
