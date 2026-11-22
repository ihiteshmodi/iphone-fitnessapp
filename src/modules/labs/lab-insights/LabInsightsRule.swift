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
        var latest: [String: LabResult] = [:]
        var items: [Insight] = []
        for marker in catalogue.markers {
            guard let result = try draws.history(of: marker.id).first else { continue }
            latest[marker.id] = result
            items += readingItems(marker, result)
        }
        items += patternItems(latest)
        items += try GeneticsService(db, catalogue: catalogue).entries().compactMap { entry in
            guard let urgency = entry.row.urgency else { return nil }
            return Insight(ruleID: "lab-gene-\(entry.gene.id)", kind: .labs, severity: .fix,
                           title: "\(urgency.title): \(entry.gene.name) \(entry.row.genotype)",
                           detail: LabInsightsRule.lines(entry.row.meaning ?? "", entry.row.actions ?? []),
                           why: entry.gene.source.map { "Vault \($0)" } ?? "Vault genetics", day: entry.enteredOn)
        }
        items += try DrawPlanner(catalogue: catalogue, draws: draws, sex: sex, showDrugNotes: showDrugNotes).retests().compactMap { due in
            guard let from = due.from, let last = due.lastDate, today >= from else { return nil }
            return Insight(ruleID: "lab-retest-\(due.marker.id)", kind: .labs, severity: .tip, title: "Retest \(due.marker.name)",
                           detail: "Last tested \(last.dayMonthYear). \(due.rule?.text ?? "")", why: due.rule?.source.map { "Vault \($0)" } ?? "Vault retest timing",
                           day: last)
        }
        return items
    }

    private func readingItems(_ marker: LabMarker, _ result: LabResult) -> [Insight] {
        let reading = LabReader.read(value: result.value, unit: result.unit, marker: marker, sex: sex)
        let value = "\(LabInsightsRule.number(result.value)) \(result.unit) on \(result.date.dayMonthYear)."
        var items: [Insight] = []
        if let worst = reading.doctorLines.first {
            items.append(Insight(ruleID: "lab-doctor-\(marker.id)", kind: .labs, severity: .fix, title: "\(worst.urgency.title): \(marker.name)",
                                 detail: LabInsightsRule.lines(value, reading.doctorLines.map(\.text)),
                                 why: worst.source.map { "Vault \($0)" } ?? "Vault doctor line", day: result.date))
        }
        switch reading.status {
        case .low, .high:
            let side = reading.status == .low ? "low" : "high"
            let actions = marker.whatToDo.filter { ($0.when == nil || $0.when == side || $0.when == "any") && shows($0.tag) }.map(\.text)
            items.append(Insight(ruleID: "lab-band-\(marker.id)", kind: .labs, severity: .improve, title: "\(marker.name) \(side)",
                                 detail: LabInsightsRule.lines(value, actions), why: "Vault \(marker.lesson)", day: result.date))
        case .disputed:
            items.append(Insight(ruleID: "lab-disputed-\(marker.id)", kind: .labs, severity: .tip, title: "\(marker.name) in a disputed zone",
                                 detail: "\(value.dropLast()) is inside some of the vault's optimal bands and not others (\(reading.disputes.joined(separator: ", "))). No flag.",
                                 why: "Vault \(marker.lesson)", day: result.date))
        default:
            break
        }
        return items
    }

    private func patternItems(_ latest: [String: LabResult]) -> [Insight] {
        catalogue.patterns.filter { $0.computable != false }.compactMap { pattern in
            guard let conditions = pattern.conditions, !conditions.isEmpty else { return nil }
            let applicable = conditions.filter { $0.sex == nil || $0.sex == .any || $0.sex == sex }
            let held = applicable.filter { holds($0, latest) }
            let needed: Int
            switch pattern.needed ?? .all {
            case .all: needed = applicable.count
            case .any: needed = 1
            case .count(let n): needed = n
            }
            guard !applicable.isEmpty, held.count >= needed else { return nil }
            let newest = applicable.compactMap { latest[$0.marker]?.date }.max()
            let detail = ([pattern.meaning] + (pattern.whatToDo ?? []) + [pattern.repeatText]).compactMap { $0 }.joined(separator: " ")
            return Insight(ruleID: "lab-pattern-\(pattern.id)", kind: .labs, severity: .improve, title: pattern.name, detail: detail,
                           why: pattern.source.map { "Vault \($0)" } ?? "Vault pattern", day: newest)
        }
    }

    private func holds(_ condition: LabCondition, _ latest: [String: LabResult]) -> Bool {
        guard let result = latest[condition.marker], let marker = catalogue.marker(condition.marker),
              let value = marker.toDefault(result.value, unit: result.unit),
              let unit = condition.unit, let raw = condition.value, let limit = marker.toDefault(raw, unit: unit) else { return false }
        switch condition.op {
        case ">": return value > limit
        case ">=": return value >= limit
        case "<": return value < limit
        case "<=": return value <= limit
        default: return false
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
