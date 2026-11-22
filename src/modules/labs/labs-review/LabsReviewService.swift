import Foundation

/// Everything the owner's bloodwork says, as one markdown file for an agent that knows the vault (the labs-review skill).
public struct LabsReviewService {
    private let db: Database
    private let catalogue: LabCatalogue

    public init(_ db: Database, catalogue: LabCatalogue) {
        self.db = db
        self.catalogue = catalogue
    }

    public func markdown(on today: ISODate, insights: [Insight]) throws -> String {
        let preferences = try LabSettings(db).load()
        let draws = LabDrawService(db, catalogue: catalogue)
        let geneticsSvc = GeneticsService(db, catalogue: catalogue)
        let genotypes = try geneticsSvc.entries()
        var headerLine = "Sex for bands: \(preferences.sex.rawValue). Date of birth: \(preferences.birthDate.map { $0.string } ?? "not set")."
        if preferences.isContextConfirmed || preferences.onTRTOrHRT || !preferences.activeMedications.isEmpty || preferences.drinksAlcoholRegularly {
            let meds = preferences.activeMedications.map(\.rawValue).sorted().joined(separator: ", ")
            headerLine += " TRT/HRT: \(preferences.onTRTOrHRT ? "yes" : "no")."
            if !meds.isEmpty { headerLine += " Active Rx classes: \(meds)." }
            if preferences.drinksAlcoholRegularly { headerLine += " Regular alcohol: yes." }
        }
        var lines = ["# Labs review export, \(today.dayMonthYear)", "", headerLine, ""]

        let board = try LabDashboard.build(catalogue: catalogue, db: db, today: today)
        switch board.biologicalAge {
        case .calculated(let result):
            lines.append("PhenoAge: \(LabInsightsRule.number(result.phenoAge)) years at calendar age \(LabInsightsRule.number(result.ageYears))"
                         + " (\(board.biologicalAgeDraw?.dayMonthYear ?? "")\(result.isEstimate ? ", hs-CRP estimated" : "")).")
        case .missing(let inputs):
            let names = inputs.map { input in input.marker.map { catalogue.marker($0.id)?.name ?? $0.id } ?? "age" }
            lines.append("PhenoAge: missing \(names.joined(separator: ", ")) (closest draw \(board.biologicalAgeDraw?.dayMonthYear ?? "none")).")
        case nil:
            lines.append("PhenoAge: date of birth not set.")
        }
        lines.append("")

        lines.append("# Open lab items")
        lines += insights.isEmpty ? ["None."] : insights.map { "- \($0.title)" }
        lines.append("")

        let planner = DrawPlanner(catalogue: catalogue, draws: draws, sex: preferences.sex, genetics: geneticsSvc, showDrugNotes: preferences.showDrugNotes)
        let due = try planner.retests().filter { $0.from.map { today >= $0 } ?? false }
        lines.append("# Retests due")
        lines += due.isEmpty ? ["None."] : due.map { "- \($0.marker.name)\($0.lastDate.map { ", last \($0.dayMonthYear)" } ?? "")" }
        lines.append("")

        let orderItems = (try? planner.order()) ?? []
        let reflexTests = orderItems.first { $0.panel.id == "reflex-co-tests" }?.tests ?? []
        if !reflexTests.isEmpty {
            lines.append("# Follow-up co-tests recommended")
            lines += reflexTests.map { "- \($0.name)" }
            lines.append("")
        }

        let geneticTests = orderItems.first { $0.panel.id == "from-genetics" }?.tests ?? []
        if !geneticTests.isEmpty {
            lines.append("# Genetic verifier tests recommended")
            lines += geneticTests.map { "- \($0.name)\($0.markerID == nil ? " (external specialty test)" : "")" }
            lines.append("")
        }

        let allDraws = try draws.draws()
        var newestResults: [LabResult] = []
        if let newest = allDraws.first {
            newestResults = try draws.results(inDraw: newest.id)
            let ctx = try? LabNonBloodContext.load(from: db, on: newest.draft.date)
            let patterns = try LabPatternEvaluator.evaluate(drawID: newest.id, draws: draws, catalogue: catalogue, preferences: preferences, context: ctx)
            if !patterns.isEmpty {
                lines.append("# Active multi-marker patterns")
                for pat in patterns {
                    let phenos = pat.matchedPhenotypes.map(\.name).joined(separator: ", ")
                    lines.append("- \(pat.name)\(phenos.isEmpty ? "" : " (\(phenos))")")
                    for guardLine in pat.interventions.whatNotToDo.prefix(2) { lines.append("  - Guardrail: \(guardLine)") }
                }
                lines.append("")
            }
            let discordances = LabPatternEvaluator.discordances(in: newestResults, catalogue: catalogue, preferences: preferences)
            if !discordances.isEmpty {
                lines.append("# Cross-marker discordances")
                for d in discordances { lines.append("- \(d.title): \(d.detail)") }
                lines.append("")
            }
        }

        if !genotypes.isEmpty {
            lines.append("# Genotypes")
            lines += genotypes.map { "- \($0.gene.name): \($0.row.genotype)" }
            lines.append("")

            lines.append("# Active genetic modifiers")
            for entry in genotypes {
                let catTag = entry.gene.actionCategory?.rawValue ?? entry.gene.bucket
                let mandate = entry.gene.changeNothingMandate ? " — Change-nothing mandate (phenotype outranks genotype)" : ""
                lines.append("- \(entry.gene.name) (\(entry.row.genotype)) [\(catTag)]\(mandate)")
                for sub in entry.gene.formSubstitutions where !entry.row.isBaseline {
                    lines.append("  - Form swap: replace \(sub.replaceOrAvoid) → \(sub.useInstead)")
                }
                for contra in entry.gene.hardContraindications where !entry.row.isBaseline {
                    if let ref = contra.mandatoryReferral { lines.append("  - Referral: \(ref)") }
                    if !contra.forbiddenItems.isEmpty { lines.append("  - Contraindicated: \(contra.forbiddenItems.joined(separator: ", "))") }
                }
            }
            for ep in GeneticsModifierEvaluator.evaluateEpistaticGrid(results: newestResults, genotypes: genotypes, preferences: preferences) {
                lines.append("- Epistatic (\(ep.geneName)): \(ep.condition) → \(ep.interpretation) \(ep.action)")
            }
            lines.append("")
        }

        lines.append("# Draws (newest first)")
        for draw in allDraws {
            lines.append("")
            lines.append("## \(draw.draft.date.dayMonthYear)")
            let state = Self.state(draw.draft)
            if !state.isEmpty { lines.append(state) }
            let drawResults = try draws.results(inDraw: draw.id)
            for result in drawResults {
                guard let marker = catalogue.marker(result.markerID) else { continue }
                lines.append("- " + line(result, marker, preferences: preferences, draw: draw.draft, sameDrawResults: drawResults, genotypes: genotypes))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func line(_ result: LabResult, _ marker: LabMarker, preferences: LabPreferences,
                      draw: LabDrawDraft, sameDrawResults: [LabResult], genotypes: [GenotypeEntry]) -> String {
        let reading = LabReader.read(result: result, marker: marker, preferences: preferences, draw: draw, genotypes: genotypes)
        let valuePart = result.textValue ?? "\(LabInsightsRule.number(result.value))\(result.unit.isEmpty ? "" : " \(result.unit)")"
        var text = "\(marker.name): \(valuePart)"
        switch reading.status {
        case .optimal: text += ", optimal"
        case .low: text += ", low"
        case .high: text += ", high"
        case .disputed: text += ", disputed zone"
        case .noOptimalBand, .notComparable: break
        }
        if result.labLow != nil || result.labHigh != nil {
            text += " (lab range \(result.labLow.map(LabInsightsRule.number) ?? "")–\(result.labHigh.map(LabInsightsRule.number) ?? ""))"
        }
        if result.isCalculated { text += " (calculated)" }
        if let worst = reading.doctorLines.first { text += " DOCTOR: \(worst.urgency.title)" }
        if let condWorst = reading.conditionalDoctorLines.first { text += " CHECK SYMPTOMS: \(condWorst.urgency.title)" }
        let validity = LabValidityGate.evaluate(result: result, marker: marker, draw: draw, sameDrawResults: sameDrawResults,
                                                catalogue: catalogue, sex: preferences.sex)
        if !validity.isEmpty {
            text += " [Validity: \(validity.map(\.title).joined(separator: "; "))]"
        }
        if !reading.geneticNotes.isEmpty {
            text += " [Genetics: \(reading.geneticNotes.joined(separator: "; "))]"
        }
        return text
    }

    private static func state(_ draft: LabDrawDraft) -> String {
        var parts: [String] = []
        if let lab = draft.lab { parts.append(lab) }
        if let time = draft.time { parts.append(time) }
        if let hours = draft.fastedHours { parts.append("fasted \(LabInsightsRule.number(hours)) h") }
        let flags: [(String, Bool?)] = [("hard training 72 h", draft.trainedHard72h), ("alcohol 5 days", draft.alcohol5d),
                                        ("biotin stopped", draft.biotinStopped), ("iron stopped", draft.ironStopped), ("ill recently", draft.illRecently)]
        for (name, value) in flags { if let value { parts.append("\(name): \(value ? "yes" : "no")") } }
        if let note = draft.note { parts.append(note) }
        return parts.joined(separator: " · ")
    }
}
