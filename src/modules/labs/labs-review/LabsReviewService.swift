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
        var lines = ["# Labs review export, \(today.dayMonthYear)", "",
                     "Sex for bands: \(preferences.sex.rawValue). Date of birth: \(preferences.birthDate.map { $0.string } ?? "not set").", ""]

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

        let due = try DrawPlanner(catalogue: catalogue, draws: draws, sex: preferences.sex).retests().filter { $0.from.map { today >= $0 } ?? false }
        lines.append("# Retests due")
        lines += due.isEmpty ? ["None."] : due.map { "- \($0.marker.name)\($0.lastDate.map { ", last \($0.dayMonthYear)" } ?? "")" }
        lines.append("")

        let genotypes = try GeneticsService(db, catalogue: catalogue).entries()
        if !genotypes.isEmpty {
            lines.append("# Genotypes")
            lines += genotypes.map { "- \($0.gene.name): \($0.row.genotype)" }
            lines.append("")
        }

        lines.append("# Draws (newest first)")
        for draw in try draws.draws() {
            lines.append("")
            lines.append("## \(draw.draft.date.dayMonthYear)")
            let state = Self.state(draw.draft)
            if !state.isEmpty { lines.append(state) }
            for result in try draws.results(inDraw: draw.id) {
                guard let marker = catalogue.marker(result.markerID) else { continue }
                lines.append("- " + line(result, marker, sex: preferences.sex))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func line(_ result: LabResult, _ marker: LabMarker, sex: LabSex) -> String {
        let reading = LabReader.read(value: result.value, unit: result.unit, marker: marker, sex: sex)
        var text = "\(marker.name): \(LabInsightsRule.number(result.value)) \(result.unit)"
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
