import FitnessCore
import Foundation

/// Loads one exercise's detail and performs its writes (log set, delete set, edit how-to).
@MainActor
final class ExerciseDetailViewModel: ObservableObject {
    @Published private(set) var detail: ExerciseDetail?
    @Published var errorMessage: String?

    private let services: Services
    let exerciseId: Int
    let dayId: Int

    init(services: Services, exerciseId: Int, dayId: Int) {
        self.services = services
        self.exerciseId = exerciseId
        self.dayId = dayId
    }

    func load() {
        do {
            detail = try services.detail.detail(exerciseId: exerciseId, dayId: dayId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Writes. Each returns true when the screen should call `session.didChange()`.

    func logSet(weightText: String, repsText: String) -> Bool {
        guard let weight = Format.decimal(weightText) else {
            errorMessage = "Enter the weight in kg (0 for bodyweight)"
            return false
        }
        guard let reps = Int(repsText.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Enter the number of reps"
            return false
        }
        do {
            try services.logSets.logSet(.existing(id: exerciseId), weightKg: weight, reps: reps, on: services.clock.today())
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteSet(id: Int) -> Bool {
        do {
            try services.logSets.deleteSet(id: id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func saveInstructions(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try services.detail.updateInstructions(exerciseId: exerciseId, instructions: trimmed.isEmpty ? nil : trimmed)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: Header

    var name: String { detail?.exercise.name ?? "" }

    var caption: String {
        guard let detail else { return "" }
        let reps = "\(Format.number(detail.target.minReps))–\(detail.target.maxReps) reps"
        let parts = [detail.exercise.muscle, "\(detail.target.sets) sets", reps].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    struct TrendBadge {
        enum Tone { case green, amber, red, grey }
        let text: String
        let tone: Tone
    }

    var trendBadge: TrendBadge {
        guard let trend = detail?.trend else { return TrendBadge(text: "Not enough data", tone: .grey) }
        switch trend.status {
        case .improving: return TrendBadge(text: "▲ \(trend.label)", tone: .green)
        case .flat: return TrendBadge(text: "● \(trend.label)", tone: .amber)
        case .declining: return TrendBadge(text: "▼ \(trend.label)", tone: .red)
        case .notEnoughData: return TrendBadge(text: trend.label, tone: .grey)
        }
    }

    // MARK: Do today

    var workingWeightText: String? { detail?.target.workingWeight.map { Format.number($0) } }

    var warmupsText: String? {
        guard let target = detail?.target, let w75 = target.warmup75, let w90 = target.warmup90 else { return nil }
        return "\(Format.number(w75)) · \(Format.number(w90)) kg"
    }

    // MARK: Last session, aim, how to

    var lastSessionTitle: String {
        guard let session = detail?.lastSession else { return "Last session" }
        return "Last session · \(Format.shortDate(session.date))"
    }

    var lastSessionChips: [String] { detail?.lastSession?.sets.map(Self.setText) ?? [] }

    var aim: String { detail?.aim ?? "" }

    var instructions: String {
        detail?.exercise.instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Progress

    var chartPoints: [ChartPoint] {
        (detail?.sessions ?? []).map {
            ChartPoint(label: Format.shortDate($0.date), value: $0.best.weightKg, caption: "\($0.best.reps)")
        }
    }

    var trendText: String {
        guard let trend = detail?.trend else { return "" }
        guard let change = trend.percentChange else { return "Not enough sessions to judge a trend yet" }
        let count = min(ExerciseTrend.windowSize, detail?.sessions.count ?? 0)
        let sign = change > 0 ? "+" : ""
        return "Estimated 1RM \(sign)\(Format.number(change, maxDecimals: 1))% over the last \(count) sessions"
    }

    // MARK: History

    struct HistoryRow: Identifiable {
        let id: String
        let date: String
        let sets: String
        let isDeload: Bool
    }

    var historyRows: [HistoryRow] {
        (detail?.history ?? []).map {
            HistoryRow(id: $0.date.string, date: Format.shortDate($0.date), sets: $0.sets.map(Self.setText).joined(separator: " · "),
                       isDeload: $0.sets.allSatisfy(\.isDeload))
        }
    }

    // MARK: Log sets

    var todaySets: [PerformedSet] { detail?.todaySets ?? [] }

    var todayCountText: String { "\(todaySets.count) of \(detail?.targetSets ?? 0)" }

    /// Numbered slots: logged sets first, then empty ones up to the target.
    var emptySlotNumbers: [Int] {
        let logged = todaySets.count
        let target = detail?.targetSets ?? 0
        return logged < target ? Array((logged + 1)...target) : []
    }

    var emptySlotText: String {
        guard let prefill = detail?.prefill else { return "" }
        let weight = prefill.weightKg.map { Format.number($0) } ?? "–"
        return "\(weight) kg × \(prefill.reps) reps"
    }

    var prefillWeightText: String { detail?.prefill.weightKg.map { Format.number($0) } ?? "" }
    var prefillRepsText: String { detail.map { String($0.prefill.reps) } ?? "" }

    static func setText(_ set: PerformedSet) -> String { "\(Format.number(set.weightKg)) × \(set.reps)" }
}
