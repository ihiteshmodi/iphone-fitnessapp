import Foundation

/// The latest results read against the catalogue: doctor lines, out-of-band actions, disputed zones, patterns and
/// retests due. Every item's id carries the result's date, so a newer result brings a dismissed item back.
public struct LabInsightsRule: SetupRule {
    public let id = "labs"
    private let catalogue: LabCatalogue
    private let sexOverride: LabSex?
    private let drugNotesOverride: Bool?

    /// Without overrides, sex and the drug-notes switch are read from Labs settings each time, so a change applies at once.
    public init(catalogue: LabCatalogue, sex: LabSex? = nil, showDrugNotes: Bool? = nil) {
        self.catalogue = catalogue
        sexOverride = sex
        drugNotesOverride = showDrugNotes
    }

    public func evaluate(on today: ISODate, db: Database) throws -> [Insight] {
        let preferences = try LabSettings(db).load()
        return try Evaluation(catalogue: catalogue, sex: sexOverride ?? preferences.sex,
                              showDrugNotes: drugNotesOverride ?? preferences.showDrugNotes).run(on: today, db: db)
    }
}

private struct Evaluation {
    let catalogue: LabCatalogue
    let sex: LabSex
    let showDrugNotes: Bool

    func run(on today: ISODate, db: Database) throws -> [Insight] {
        let draws = LabDrawService(db, catalogue: catalogue)
        var prefs = try LabSettings(db).load()
        prefs.sex = sex
        prefs.showDrugNotes = showDrugNotes
        let geneticsSvc = GeneticsService(db, catalogue: catalogue)
        let genotypes = try geneticsSvc.entries()

        let allDraws = try draws.draws()
        var items: [Insight] = []
        for marker in catalogue.visibleMarkers(for: sex) {
            guard let result = try draws.history(of: marker.id).first else { continue }
            let drawDraft = allDraws.first { $0.id == result.drawID }?.draft
            let sameDraw = (try? draws.results(inDraw: result.drawID)) ?? []
            items += readingItems(marker, result, preferences: prefs, draw: drawDraft, sameDrawResults: sameDraw, genotypes: genotypes)
        }
        let (latestByMarker, drawsByID, newestDate) = try draws.latestResultsSnapshot()
        let newestResults = Array(latestByMarker.values)
        if !latestByMarker.isEmpty, let refDate = newestDate {
            let latestDraft = allDraws.first?.draft ?? LabDrawDraft(date: refDate)
            if let cytopenia = multilineageCytopeniaItem(latestByMarker, drawsByID: drawsByID, preferences: prefs, fallbackDate: refDate) {
                items.append(cytopenia)
            }
            for simple in LabPatternEvaluator.evaluateSimplePatterns(resultsByMarker: latestByMarker, drawsByID: drawsByID,
                                                                     catalogue: catalogue, preferences: prefs) {
                items.append(Insight(ruleID: simple.isUrgentDoctor ? "lab-doctor-pattern-\(simple.id)" : "lab-pattern-\(simple.id)",
                                     kind: .labs, severity: simple.isUrgentDoctor ? .fix : .improve, title: simple.name,
                                     detail: simple.detail, why: simple.source.map { "Vault \($0)" } ?? "Vault pattern", day: simple.newestDate))
            }
            let ctx = try? LabNonBloodContext.load(from: db, on: refDate)
            for match in LabPatternEvaluator.evaluateLatest(resultsByMarker: latestByMarker, drawsByID: drawsByID, fallbackDate: refDate,
                                                            catalogue: catalogue, preferences: prefs, context: ctx) {
                let phenoNames = match.matchedPhenotypes.map(\.name)
                let header = phenoNames.isEmpty ? match.name : "\(match.name) (\(phenoNames.joined(separator: ", ")))"
                let bullets = match.contextNotes + match.interventions.tier1Foundations.prefix(3)
                items.append(Insight(ruleID: "lab-engine-\(match.id)", kind: .labs, severity: .improve, title: header,
                                     detail: LabInsightsRule.lines("Pattern matched across latest markers (\(match.drawDate.dayMonthYear)).", Array(bullets)),
                                     why: "Clinical pattern engine", day: match.drawDate))
            }
            for disc in LabPatternEvaluator.discordances(in: newestResults, catalogue: catalogue, preferences: prefs) {
                let dDay = disc.markerIDs.compactMap { latestByMarker[$0]?.date }.max() ?? latestDraft.date
                items.append(Insight(ruleID: "lab-\(disc.id)", kind: .labs, severity: .improve, title: disc.title,
                                     detail: disc.detail, why: "Cross-marker discordance rule", day: dDay))
            }
        }
        items += genotypes.compactMap { entry in
            guard let urgency = entry.row.urgency else { return nil }
            return Insight(ruleID: "lab-gene-\(entry.gene.id)", kind: .labs, severity: .fix,
                           title: "\(urgency.title): \(entry.gene.name) \(entry.row.genotype)",
                           detail: LabInsightsRule.lines(entry.row.meaning ?? "", entry.row.actions ?? []),
                           why: entry.gene.source.map { "Vault \($0)" } ?? "Vault genetics", day: entry.enteredOn)
        }
        items += GeneticsModifierEvaluator.evaluateInsights(
            on: today, db: db, genotypes: genotypes, preferences: prefs,
            latestResults: newestResults, latestDraw: allDraws.first?.draft)
        for rev in GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: genotypes,
            preferences: prefs, latestResults: newestResults) {
            var bullets = [rev.rationale]
            if let guardrail = rev.guardrailWarning { bullets.append(guardrail) }
            if let clinical = rev.clinicalGradeWarning { bullets.append(clinical) }
            items.append(Insight(
                ruleID: "lab-gene-reverse-\(rev.geneID)", kind: .labs,
                severity: rev.isSafetyGate ? .fix : .improve,
                title: "Consider genetic test: \(rev.geneName)",
                detail: LabInsightsRule.lines(rev.triggerSummary, bullets),
                why: rev.source.map { "Vault \($0)" } ?? "Conditional genetic triage",
                day: newestDate ?? today))
        }
        items += try DrawPlanner(catalogue: catalogue, draws: draws, sex: sex, genetics: geneticsSvc, showDrugNotes: showDrugNotes).retests().compactMap { due in
            guard let from = due.from, let last = due.lastDate, today >= from else { return nil }
            return Insight(ruleID: "lab-retest-\(due.marker.id)", kind: .labs, severity: .tip, title: "Retest \(due.marker.name)",
                           detail: "Last tested \(last.dayMonthYear). \(due.rule?.text ?? "")", why: due.rule?.source.map { "Vault \($0)" } ?? "Vault retest timing",
                           day: last)
        }
        return items
    }

    private func readingItems(_ marker: LabMarker, _ result: LabResult, preferences: LabPreferences,
                              draw: LabDrawDraft?, sameDrawResults: [LabResult], genotypes: [GenotypeEntry]) -> [Insight] {
        let reading = LabReader.read(result: result, marker: marker, preferences: preferences, draw: draw, genotypes: genotypes)
        let displayVal = result.textValue ?? "\(LabInsightsRule.number(result.value)) \(result.unit)"
        let value = "\(displayVal) on \(result.date.dayMonthYear)."
        let specialistsLine = (marker.escalation?.specialists).flatMap { $0.isEmpty ? nil : "Specialists: \($0.joined(separator: ", "))" }
        var items: [Insight] = []

        if let worst = reading.doctorLines.first {
            let bullets = reading.doctorLines.map(\.text) + [specialistsLine].compactMap { $0 }
            items.append(Insight(ruleID: "lab-doctor-\(marker.id)", kind: .labs, severity: .fix, title: "\(worst.urgency.title): \(marker.name)",
                                 detail: LabInsightsRule.lines(value, bullets),
                                 why: worst.source.map { "Vault \($0)" } ?? "Vault doctor line", day: result.date))
        }
        if let worstCond = reading.conditionalDoctorLines.first {
            let condBullets = reading.conditionalDoctorLines.map { line in
                line.requires.map { "If you have \($0): \(line.text)" } ?? line.text
            } + [specialistsLine].compactMap { $0 }
            items.append(Insight(ruleID: "lab-doctor-symptom-\(marker.id)", kind: .labs, severity: .fix,
                                 title: "Check symptoms (\(worstCond.urgency.title)): \(marker.name)",
                                 detail: LabInsightsRule.lines(value, condBullets),
                                 why: worstCond.source.map { "Vault \($0)" } ?? "Symptom-paired panic rule", day: result.date))
        }

        switch reading.status {
        case .low, .high:
            let side = reading.status == .low ? "low" : "high"
            let validityBullets = draw.map {
                LabValidityGate.evaluate(result: result, marker: marker, draw: $0, sameDrawResults: sameDrawResults,
                                         catalogue: catalogue, sex: sex)
                    .map { "Pre-analytic check: \($0.title) — \($0.detail)" }
            } ?? []
            let geneticBullets = reading.geneticNotes.map { "Genetic modifier: \($0)" }
            let steppedBullets = steppedActionLines(marker: marker, side: side)
            let legacyBullets = marker.whatToDo.filter { ($0.when == nil || $0.when == side || $0.when == "any") && shows($0.tag) }.map(\.text)
            let actionBullets = steppedBullets.isEmpty ? legacyBullets : steppedBullets
            items.append(Insight(ruleID: "lab-band-\(marker.id)", kind: .labs, severity: .improve, title: "\(marker.name) \(side)",
                                 detail: LabInsightsRule.lines(value, geneticBullets + validityBullets + actionBullets),
                                 why: "Vault \(marker.lesson)", day: result.date))
        case .disputed:
            items.append(Insight(ruleID: "lab-disputed-\(marker.id)", kind: .labs, severity: .tip, title: "\(marker.name) in a disputed zone",
                                 detail: "\(value.dropLast()) is inside some of the vault's optimal bands and not others (\(reading.disputes.joined(separator: ", "))). No flag.",
                                 why: "Vault \(marker.lesson)", day: result.date))
        default:
            break
        }
        return items
    }

    private func steppedActionLines(marker: LabMarker, side: String) -> [String] {
        guard let inter = marker.interventions else { return [] }
        var lines: [String] = []
        lines += inter.tier1Foundations.prefix(3).map { "Foundations: \($0)" }
        lines += inter.tier2Nutrition.prefix(3).map { "Nutrition: \($0)" }
        let matchedSupps = inter.tier3Supplements.filter { s in
            guard let t = s.target?.lowercased() else { return true }
            return t == "general" || t == side
        }
        lines += matchedSupps.prefix(3).map { s in
            let dose = s.dose.map { " (\($0))" } ?? ""
            return "Supplement: \(s.name)\(dose)"
        }
        if showDrugNotes {
            lines += inter.tier4Peptides.prefix(2).map { "Educational (Tier 4): \($0)" }
        }
        lines += inter.whatNotToDo.map { "What NOT to do: \($0)" }
        return lines
    }

    private func multilineageCytopeniaItem(_ sameDraw: [String: LabResult], drawsByID: [Int: LabDrawDraft],
                                           preferences: LabPreferences, fallbackDate: ISODate) -> Insight? {
        guard !catalogue.patterns.contains(where: { $0.id == "pancytopenia" && $0.computable != false }) else { return nil }
        let redResult = sameDraw["hemoglobin"] ?? sameDraw["rbc"]
        guard let red = redResult, let redMarker = catalogue.marker(red.markerID),
              let wbc = sameDraw["wbc"], let wbcMarker = catalogue.marker("wbc"),
              let plt = sameDraw["platelets"], let pltMarker = catalogue.marker("platelets") else { return nil }
        let isBelowLab: (LabResult, LabMarker) -> Bool = { res, m in
            let r = LabReader.read(result: res, marker: m, preferences: preferences, draw: drawsByID[res.drawID])
            if let stdLow = r.activeStratum?.standardLow { return (res.defaultValue ?? res.value) < stdLow }
            if let labLow = m.visibleBands(for: sex).first(where: { $0.kind == "lab" })?.low { return (res.defaultValue ?? res.value) < labLow }
            return r.status == .low
        }
        guard isBelowLab(red, redMarker), isBelowLab(wbc, wbcMarker), isBelowLab(plt, pltMarker) else { return nil }
        let newest = [red.date, wbc.date, plt.date].max() ?? fallbackDate
        return Insight(
            ruleID: "lab-doctor-multilineage-cytopenia",
            kind: .labs,
            severity: .fix,
            title: "Within a few days: All three blood cell lines low",
            detail: LabInsightsRule.lines(
                "Concurrent low red cells/hemoglobin, WBC, and platelets (latest \(newest.dayMonthYear)).",
                ["Prompt physician evaluation within a few days (same-day ER if fever, bleeding, or severe fatigue).",
                 "Specialists: Hematology"]),
            why: "Global red-flag hematology threshold",
            day: newest)
    }

    private func shows(_ tag: String?) -> Bool { sex.allows(sex: nil, tag: tag, showDrugNotes: showDrugNotes) }

}

extension LabInsightsRule {
    static func number(_ value: Double) -> String {
        var text = String(format: "%.2f", value)
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) { text.removeLast() }
        return text
    }
}

extension LabInsightsRule {
    /// A heading line, then one bullet per vault line, so long advice stays readable on a card.
    static func lines(_ heading: String, _ bullets: [String]) -> String {
        ([heading] + bullets.map { "• \($0)" }).filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
