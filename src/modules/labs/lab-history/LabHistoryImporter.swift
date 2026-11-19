import Foundation

/// Loads past lab results from a private CSV (kind,date,time,lab,marker_id,value,unit,lab_low,lab_high,note).
/// One draw per date and lab; applying the same file again adds nothing.
public final class LabHistoryImporter {
    public struct Result: Equatable {
        public let drawsAdded: Int
        public let resultsAdded: Int
        public let skipped: [String]
    }

    private let db: Database
    private let draws: LabDrawService

    public init(_ db: Database, catalogue: LabCatalogue) {
        self.db = db
        draws = LabDrawService(db, catalogue: catalogue)
    }

    @discardableResult
    public func apply(_ csv: String) throws -> Result {
        let lines = csv.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let header = lines.first?.split(separator: ",", omittingEmptySubsequences: false).map(String.init) else {
            return Result(drawsAdded: 0, resultsAdded: 0, skipped: [])
        }
        let column = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1, $0) })
        var drawsAdded = 0, resultsAdded = 0
        var skipped: [String] = []
        try db.transaction {
            for (number, line) in lines.dropFirst().enumerated() {
                let cells = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
                func cell(_ name: String) -> String? {
                    guard let i = column[name], i < cells.count else { return nil }
                    let text = cells[i].trimmingCharacters(in: .whitespaces)
                    return text.isEmpty ? nil : text
                }
                if cell("kind") == "setting" {
                    if cell("marker_id") == "labs_birth_date", let day = cell("value").flatMap(ISODate.init) { try LabSettings(db).setBirthDate(day) }
                    continue
                }
                guard let day = cell("date").flatMap(ISODate.init), let marker = cell("marker_id"),
                      let value = cell("value").flatMap(Double.init), let unit = cell("unit") else {
                    skipped.append("Line \(number + 2): incomplete row")
                    continue
                }
                let lab = cell("lab")
                let drawID: Int
                if let existing = try draws.draws().first(where: { $0.draft.date == day && $0.draft.lab == lab }) {
                    drawID = existing.id
                } else {
                    drawID = try draws.addDraw(LabDrawDraft(date: day, time: cell("time"), lab: lab, note: "Loaded from past reports"))
                    drawsAdded += 1
                }
                if try draws.results(inDraw: drawID).contains(where: { $0.markerID == marker && $0.value == value && $0.unit == unit }) { continue }
                do {
                    try draws.addResult(drawID: drawID, markerID: marker, value: value, unit: unit,
                                        labLow: cell("lab_low").flatMap(Double.init), labHigh: cell("lab_high").flatMap(Double.init))
                    resultsAdded += 1
                } catch {
                    skipped.append("Line \(number + 2) \(marker): \((error as? ValidationError)?.message ?? "\(error)")")
                }
            }
        }
        return Result(drawsAdded: drawsAdded, resultsAdded: resultsAdded, skipped: skipped)
    }
}
