import FitnessCore
import Foundation

/// Loads one exercise's detail and performs its writes (log set, delete set, edit how-to).
@MainActor
final class ExerciseDetailViewModel: ObservableObject {
    @Published private(set) var detail: ExerciseDetail?
    @Published private(set) var earlierSessions: [SetSession] = []
    @Published private(set) var hasMoreEarlier = false
    @Published var errorMessage: String?

    private let services: Services
    private var earlierLimit = ExerciseDetailViewModel.firstEarlierPage
    private static let firstEarlierPage = 5
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
            // One extra session tells whether "Show all" has anything more to show.
            let sessions = try services.logSets.sessions(exerciseId: exerciseId, excluding: today, limit: earlierLimit + 1)
            hasMoreEarlier = sessions.count > earlierLimit
            earlierSessions = Array(sessions.prefix(earlierLimit))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Writes. Each returns true when the screen should call `session.didChange()`.

    var today: ISODate { services.clock.today() }

    func showAllEarlier() {
        earlierLimit = Int.max - 1
        load()
    }

    func logSet(weightText: String, repsText: String, on day: ISODate? = nil) -> Bool {
        guard let (weight, reps) = parse(weightText: weightText, repsText: repsText) else { return false }
        return perform { try services.logSets.logSet(.existing(id: exerciseId), weightKg: weight, reps: reps, on: day ?? today) }
    }

    func updateSet(id: Int, weightText: String, repsText: String, on day: ISODate) -> Bool {
        guard let (weight, reps) = parse(weightText: weightText, repsText: repsText) else { return false }
        return perform { try services.logSets.updateSet(id: id, weightKg: weight, reps: reps, on: day) }
    }

    private func parse(weightText: String, repsText: String) -> (Double, Int)? {
        guard let weight = Format.decimal(weightText) else {
            errorMessage = "Enter the weight in kg (0 for bodyweight)"
            return nil
        }
        guard let reps = Int(repsText.trimmingCharacters(in: .whitespaces)) else {
            errorMessage = "Enter the number of reps"
            return nil
        }
        return (weight, reps)
    }

    /// Today's answer to "did every rep have a full contraction?". True when it is due.
    var needsFormAnswer: Bool { detail?.needsFormAnswer ?? false }

    /// The best set today, for the question: "60 kg × 16".
    var topSetText: String {
        guard let set = todaySets.max(by: { ($0.reps, $0.weightKg) < ($1.reps, $1.weightKg) }) else { return "" }
        return "\(Format.number(set.weightKg)) kg × \(set.reps)"
    }

    func answerForm(clean: Bool) -> Bool {
        perform { try services.formChecks.setClean(clean, exerciseId: exerciseId, on: today) }
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
        let reps = "\(Format.number(detail.target.minReps))–\(Format.number(detail.target.maxReps)) reps"
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

    /// "75%  33.75 kg" and "90%  40.5 kg", labelled so it is clear they are shares of the working weight.
    struct Warmup: Identifiable {
        let percent: String
        let kg: String
        var id: String { percent }
    }

    var warmups: [Warmup] {
        (detail?.target.warmups ?? []).map { Warmup(percent: "\($0.percent)%", kg: "\(Format.number($0.weightKg)) kg") }
    }

    // MARK: PR banner

    var progression: Progression { detail?.progression ?? .none }

    struct Banner {
        enum Style { case pr, repeatClean }
        let style: Style
        let kicker: String
        let headline: String
        let detail: String
        /// "Est. 1RM from 60 kg × 16" and "92 kg".
        let oneRepMaxLabel: String?
        let oneRepMaxValue: String?
        let nextWeightLabel: String?
        let nextWeightValue: String?
    }

    var banner: Banner? {
        switch progression {
        case .none:
            return nil
        case .pr(let next, let oneRepMax, let weight, let reps, let isToday):
            let lifted = "\(Format.number(weight)) kg × \(reps)"
            let minReps = Format.number(detail?.target.minReps ?? 0)
            return Banner(
                style: .pr,
                kicker: isToday ? "★ PR today · clean form" : "★ PR last time · clean form",
                headline: isToday ? "Next time: \(Format.number(next)) kg" : "Increase weight to \(Format.number(next)) kg",
                detail: isToday ? "You did \(lifted) at the top of your range." : "You did \(lifted) at the top of your range. Start at \(Format.number(next)) kg and aim for \(minReps) reps or more.",
                oneRepMaxLabel: "Est. 1RM from \(lifted)", oneRepMaxValue: "\(Format.number(oneRepMax, maxDecimals: 1)) kg",
                nextWeightLabel: "At \(minReps) reps the 1RM allows", nextWeightValue: "\(Format.number(next)) kg")
        case .repeatForCleanReps(let weight):
            return Banner(
                style: .repeatClean,
                kicker: "Repeat · aim for clean reps",
                headline: "Stay at \(Format.number(weight)) kg",
                detail: "Last time you reached the top reps but said the form was not clean. Hit them again with a full contraction on every rep, then it counts as a PR.",
                oneRepMaxLabel: nil, oneRepMaxValue: nil, nextWeightLabel: nil, nextWeightValue: nil)
        }
    }

    var isPRNextWeight: Bool { if case .pr(_, _, _, _, let isToday) = progression { return !isToday }; return false }

    // MARK: Aim, how to

    /// The aim as a pill and an optional hint. Hidden when there is no working weight yet (the card says so itself).
    var aimSummary: AimSummary? {
        guard let detail, detail.target.workingWeight != nil else { return nil }
        return detail.aimSummary
    }

    var aimTone: Pill.Tone {
        if isPRNextWeight { return .gold }
        switch aimSummary?.pill {
        case "Increase weight", "Increase reps": return .green
        case "Maintain", "Deload", "Repeat": return .amber
        default: return .grey
        }
    }

    var instructions: String {
        detail?.exercise.instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Progress

    var sessionPoints: [SessionPoint] {
        (detail?.sessions ?? []).map {
            SessionPoint(id: $0.date.string, label: Format.shortDate($0.date), kg: $0.best.weightKg, repsText: "×\($0.best.reps)",
                         mark: detail?.sessionMarks[$0.date])
        }
    }

    var trendText: String {
        guard let trend = detail?.trend else { return "" }
        guard let change = trend.percentChange else { return "Not enough sessions to judge a trend yet" }
        let count = min(ExerciseTrend.windowSize, detail?.sessions.count ?? 0)
        let sign = change > 0 ? "+" : ""
        return "Estimated 1RM \(sign)\(Format.number(change, maxDecimals: 1))% over the last \(count) sessions"
    }

    // MARK: Muscles worked

    var muscles: ExerciseMuscles? { detail?.muscles }

    func saveMuscles(_ assignments: [MuscleAssignment]) -> Bool {
        perform { try services.muscles.save(exerciseId: exerciseId, assignments: assignments) }
    }

    func resetMuscles() -> Bool {
        perform { try services.muscles.reset(exerciseId: exerciseId) }
    }

    private func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    /// "starts in the middle of 8–16" under the reps stepper.
    var repRangeHint: String {
        guard let target = detail?.target else { return "" }
        return "starts in the middle of \(Format.number(target.minReps))–\(Format.number(target.maxReps))"
    }

    /// "≈ 92 kg" once a set is logged today, from the best set (Epley).
    var oneRepMaxText: String? {
        detail?.todayOneRepMax.map { "≈ \(Format.number($0, maxDecimals: 1)) kg" }
    }

    var prefillWeightText: String { detail?.prefill.weightKg.map { Format.number($0) } ?? "" }
    var prefillRepsText: String { detail.map { String($0.prefill.reps) } ?? "" }

    static func setText(_ set: PerformedSet) -> String { "\(Format.number(set.weightKg)) × \(set.reps)" }
}
