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
        var newestResults: [LabResult] = []
        if let newestDraw = allDraws.first {
            let sameDrawResults = try draws.results(inDraw: newestDraw.id)
            newestResults = sameDrawResults
            let sameDrawMap = Dictionary(uniqueKeysWithValues: sameDrawResults.map { ($0.markerID, $0) })
            if let cytopenia = multilineageCytopeniaItem(sameDrawMap, preferences: prefs, draw: newestDraw.draft) {
                items.append(cytopenia)
            }
            items += patternItems(sameDrawMap, preferences: prefs, draw: newestDraw.draft)
            let ctx = try? LabNonBloodContext.load(from: db, on: newestDraw.draft.date)
            for match in try LabPatternEvaluator.evaluate(drawID: newestDraw.id, draws: draws, catalogue: catalogue, preferences: prefs, context: ctx) {
                let phenoNames = match.matchedPhenotypes.map(\.name)
                let header = phenoNames.isEmpty ? match.name : "\(match.name) (\(phenoNames.joined(separator: ", ")))"
                let bullets = match.contextNotes + match.interventions.tier1Foundations.prefix(3)
                items.append(Insight(ruleID: "lab-engine-\(match.id)", kind: .labs, severity: .improve, title: header,
                                     detail: LabInsightsRule.lines("Pattern matched on \(match.drawDate.dayMonthYear).", Array(bullets)),
                                     why: "Clinical pattern engine", day: match.drawDate))
            }
            for disc in LabPatternEvaluator.discordances(in: sameDrawResults, catalogue: catalogue, preferences: prefs) {
                items.append(Insight(ruleID: "lab-\(disc.id)", kind: .labs, severity: .improve, title: disc.title,
                                     detail: disc.detail, why: "Cross-marker discordance rule", day: newestDraw.draft.date))
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

    private func multilineageCytopeniaItem(_ sameDraw: [String: LabResult], preferences: LabPreferences, draw: LabDrawDraft) -> Insight? {
        guard !catalogue.patterns.contains(where: { $0.id == "pancytopenia" && $0.computable != false }) else { return nil }
        let redResult = sameDraw["hemoglobin"] ?? sameDraw["rbc"]
        guard let red = redResult, let redMarker = catalogue.marker(red.markerID),
              let wbc = sameDraw["wbc"], let wbcMarker = catalogue.marker("wbc"),
              let plt = sameDraw["platelets"], let pltMarker = catalogue.marker("platelets") else { return nil }
        let isBelowLab: (LabResult, LabMarker) -> Bool = { res, m in
            let r = LabReader.read(result: res, marker: m, preferences: preferences, draw: draw)
            if let stdLow = r.activeStratum?.standardLow { return (res.defaultValue ?? res.value) < stdLow }
            if let labLow = m.visibleBands(for: sex).first(where: { $0.kind == "lab" })?.low { return (res.defaultValue ?? res.value) < labLow }
            return r.status == .low
        }
        guard isBelowLab(red, redMarker), isBelowLab(wbc, wbcMarker), isBelowLab(plt, pltMarker) else { return nil }
        return Insight(
            ruleID: "lab-doctor-multilineage-cytopenia",
            kind: .labs,
            severity: .fix,
            title: "Within a few days: All three blood cell lines low",
            detail: LabInsightsRule.lines(
                "Concurrent low red cells/hemoglobin, WBC, and platelets on \(draw.date.dayMonthYear).",
                ["Prompt physician evaluation within a few days (same-day ER if fever, bleeding, or severe fatigue).",
                 "Specialists: Hematology"]),
            why: "Global red-flag hematology threshold",
            day: draw.date)
    }

    private func patternItems(_ sameDraw: [String: LabResult], preferences: LabPreferences, draw: LabDrawDraft) -> [Insight] {
        catalogue.patterns.filter { $0.computable != false && $0.engine == nil }.compactMap { pattern in
            guard let conditions = pattern.conditions, !conditions.isEmpty else { return nil }
            let applicable = conditions.filter { sex.allows(sex: $0.sex) }
            let held = applicable.filter { holds($0, sameDraw, preferences: preferences, draw: draw) }
            let needed: Int
            switch pattern.needed ?? .all {
            case .all: needed = applicable.count
            case .any: needed = 1
            case .count(let n): needed = n
            }
            guard !applicable.isEmpty, held.count >= needed else { return nil }
            let newest = applicable.compactMap { sameDraw[$0.marker]?.date }.max()
            let detail = ([pattern.meaning] + (pattern.whatToDo ?? []) + [pattern.repeatText]).compactMap { $0 }.joined(separator: " ")
            let isUrgentDoctor = pattern.doctor != nil && (pattern.id == "pancytopenia" || pattern.id == "ketoacidosis-signal")
            return Insight(ruleID: isUrgentDoctor ? "lab-doctor-pattern-\(pattern.id)" : "lab-pattern-\(pattern.id)",
                           kind: .labs, severity: isUrgentDoctor ? .fix : .improve, title: pattern.name,
                           detail: pattern.doctor.map { "\(detail) \($0)" } ?? detail,
                           why: pattern.source.map { "Vault \($0)" } ?? "Vault pattern", day: newest)
        }
    }

    private func holds(_ condition: LabCondition, _ sameDraw: [String: LabResult], preferences: LabPreferences, draw: LabDrawDraft) -> Bool {
        guard let result = sameDraw[condition.marker], let marker = catalogue.marker(condition.marker) else { return false }
        if let raw = condition.value {
            guard let value = result.defaultValue ?? (marker.isUnitlessRatio ? result.value : nil) else { return false }
            let limit: Double
            if let unit = condition.unit {
                guard let conv = marker.toDefault(raw, unit: unit) else { return false }
                limit = conv
            } else {
                limit = raw
            }
            switch condition.op {
            case ">": return value > limit
            case ">=": return value >= limit
            case "<": return value < limit
            case "<=": return value <= limit
            default: return false
            }
        }
        let reading = LabReader.read(result: result, marker: marker, preferences: preferences, draw: draw)
        switch condition.op {
        case "high", "positive":
            return reading.status == .high
        case "low", "suppressed":
            return reading.status == .low
        case "veryLow":
            return reading.status == .low && (reading.tier == .criticalLow || reading.tier == .suboptimalLow)
        case "normal", "optimal":
            return reading.status == .optimal || reading.status == .disputed
        case "lowNormal", "lowOrLowNormal", "lowerThird":
            return reading.status == .low || reading.tier == .watchLow
        case "abnormal":
            return reading.status == .low || reading.status == .high
        default:
            return false
        }
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
