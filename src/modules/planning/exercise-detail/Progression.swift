import Foundation

/// How a session at the top of the rep range counts.
public enum SessionMark: Equatable {
    /// Top of the rep range reached with clean form: a PR.
    case pr
    /// Top of the rep range reached, but the form was not clean: not a PR.
    case notClean
}

/// What the screens tell the lifter to do next, from the last session that mattered.
public enum Progression: Equatable {
    case none
    /// The weight to take next time. `isToday` when the PR was set in today's session.
    case pr(nextWeightKg: Double, oneRepMax: Double, fromWeightKg: Double, fromReps: Int, isToday: Bool)
    /// Reached the top reps without clean form: same weight again, with a full contraction on every rep.
    case repeatForCleanReps(weightKg: Double)
}

/// Pure rules for PRs: no database, no clock.
public enum ProgressionCalculator {
    /// nil when the session did not reach the top of the rep range, or (today only) the form question is still open.
    /// Sessions from before the question existed have no answer and count as clean.
    public static func mark(of session: ExerciseSession, maxReps: Int, answers: [ISODate: Bool], today: ISODate) -> SessionMark? {
        guard session.sets.contains(where: { $0.reps >= maxReps }) else { return nil }
        guard let answer = answers[session.date] else { return session.date < today ? .pr : nil }
        return answer ? .pr : .notClean
    }

    public static func marks(of sessions: [ExerciseSession], maxReps: Int, answers: [ISODate: Bool], today: ISODate) -> [ISODate: SessionMark] {
        var result: [ISODate: SessionMark] = [:]
        for session in sessions {
            if let mark = mark(of: session, maxReps: maxReps, answers: answers, today: today) { result[session.date] = mark }
        }
        return result
    }

    public static func progression(sessions: [ExerciseSession], minReps: Int, maxReps: Int, answers: [ISODate: Bool], today: ISODate,
                                   deloadActive: Bool) -> Progression {
        guard !deloadActive else { return .none }
        // A lighter session than the heaviest weight ever lifted is not the one to progress from.
        let heaviestEver = sessions.flatMap(\.sets).map(\.weightKg).max() ?? 0

        if let todaySession = sessions.last(where: { $0.date == today }),
           let mark = mark(of: todaySession, maxReps: maxReps, answers: answers, today: today),
           let top = topSet(of: todaySession, maxReps: maxReps), top.weightKg >= heaviestEver {
            return outcome(mark, top: top, minReps: minReps, isToday: true)
        }

        guard let last = sessions.last(where: { $0.date < today }),
              let mark = mark(of: last, maxReps: maxReps, answers: answers, today: today),
              let top = topSet(of: last, maxReps: maxReps), top.weightKg >= heaviestEver else { return .none }
        // Once a heavier set is logged today, the PR has been acted on.
        let todayHeaviest = sessions.last(where: { $0.date == today })?.sets.map(\.weightKg).max()
        if let todayHeaviest, todayHeaviest > top.weightKg { return .none }
        return outcome(mark, top: top, minReps: minReps, isToday: false)
    }

    /// The set that reached the top of the range; the heaviest, then the one with most reps.
    private static func topSet(of session: ExerciseSession, maxReps: Int) -> PerformedSet? {
        session.sets.filter { $0.reps >= maxReps }.max { ($0.weightKg, $0.reps) < ($1.weightKg, $1.reps) }
    }

    private static func outcome(_ mark: SessionMark, top: PerformedSet, minReps: Int, isToday: Bool) -> Progression {
        switch mark {
        case .notClean:
            return .repeatForCleanReps(weightKg: top.weightKg)
        case .pr:
            return .pr(nextWeightKg: OneRepMax.nextWeight(afterWeightKg: top.weightKg, reps: top.reps, minReps: minReps),
                       oneRepMax: pyRound(OneRepMax.estimate(weightKg: top.weightKg, reps: top.reps), 2),
                       fromWeightKg: top.weightKg, fromReps: top.reps, isToday: isToday)
        }
    }
}
