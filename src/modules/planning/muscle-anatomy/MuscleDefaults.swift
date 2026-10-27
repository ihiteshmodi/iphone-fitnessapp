import Foundation

/// Works out which muscles an exercise trains from its name and muscle group, when the user has not chosen any.
/// These are sensible defaults, not a lookup from a reference book, so the editor lets the user correct them.
public enum MuscleDefaults {
    public static func assignments(exerciseName: String, group: String?) -> [MuscleAssignment] {
        let groups = groupNames(group)
        let text = " \(words(exerciseName)) "

        if let rule = rules.first(where: { $0.matches(text: text, groups: groups) }) {
            return build(primary: rule.primary, secondary: rule.secondary)
        }
        return build(primary: groups.flatMap { groupFallback[$0] ?? [] }, secondary: [])
    }

    // MARK: Rules

    private struct Rule {
        /// Whole words or phrases; a plural "s" is accepted ("deadlifts").
        let keywords: [String]
        /// The rule only applies to exercises in one of these groups; nil means any group.
        let groups: Set<String>?
        let primary: [MusclePart]
        let secondary: [MusclePart]

        func matches(text: String, groups exerciseGroups: [String]) -> Bool {
            if let groups, groups.isDisjoint(with: exerciseGroups) { return false }
            return keywords.contains { text.contains(" \($0) ") || text.contains(" \($0)s ") }
        }
    }

    private static let chestGroup: Set<String> = ["chest"]
    private static let backGroups: Set<String> = ["back", "mid back", "lats"]
    private static let quads: [MusclePart] = [.quadRectus, .quadOuter, .quadInner]
    private static let triceps: [MusclePart] = [.tricepsLong, .tricepsLateral]
    private static let hamstrings: [MusclePart] = [.hamOuter, .hamInner]

    /// The first matching rule wins, so specific rules come before general ones.
    private static let rules: [Rule] = [
        // Hinge and lower body
        Rule(keywords: ["stiff leg", "romanian", "rdl"], groups: nil, primary: hamstrings + [.gluteMax], secondary: [.erectors]),
        Rule(keywords: ["deadlift"], groups: nil, primary: [.erectors, .gluteMax] + hamstrings, secondary: [.trapsUpper, .lats]),
        Rule(keywords: ["good morning"], groups: nil, primary: [.erectors, .gluteMax] + hamstrings, secondary: []),
        Rule(keywords: ["hyperextension", "back extension"], groups: nil, primary: [.erectors], secondary: [.gluteMax] + hamstrings),
        Rule(keywords: ["hip thrust", "glute bridge", "kickback"], groups: ["glutes", "legs"], primary: [.gluteMax], secondary: hamstrings),
        Rule(keywords: ["abduction"], groups: nil, primary: [.abductors], secondary: [.gluteMax]),
        Rule(keywords: ["adduction"], groups: nil, primary: [.adductors], secondary: []),
        Rule(keywords: ["seated calf"], groups: nil, primary: [.soleus], secondary: [.gastrocnemius]),
        Rule(keywords: ["calf raise", "calf press", "calf"], groups: nil, primary: [.gastrocnemius, .soleus], secondary: []),
        Rule(keywords: ["tibialis", "shin"], groups: nil, primary: [.tibialis], secondary: []),
        Rule(keywords: ["leg curl", "hamstring curl"], groups: nil, primary: hamstrings, secondary: [.gastrocnemius]),
        Rule(keywords: ["leg extension"], groups: nil, primary: quads, secondary: []),
        Rule(keywords: ["lunge", "split squat", "step up"], groups: nil, primary: quads + [.gluteMax], secondary: [.adductors] + hamstrings),
        Rule(keywords: ["squat", "leg press", "hacksquat"], groups: nil, primary: quads, secondary: [.gluteMax, .adductors]),

        // Chest
        Rule(keywords: ["incline"], groups: chestGroup, primary: [.chestUpper], secondary: [.chestMid, .deltFront] + triceps),
        Rule(keywords: ["decline", "dip"], groups: chestGroup, primary: [.chestLower], secondary: [.chestMid, .deltFront] + triceps),
        Rule(keywords: ["fly", "flye", "pec deck", "crossover", "cross over"], groups: chestGroup,
             primary: [.chestMid], secondary: [.chestUpper, .chestLower, .deltFront]),
        Rule(keywords: ["press", "push up", "pushup"], groups: chestGroup,
             primary: [.chestUpper, .chestMid, .chestLower], secondary: [.deltFront] + triceps),

        // Back
        Rule(keywords: ["pulldown", "pull down", "pull up", "chin up", "pullover"], groups: backGroups,
             primary: [.lats], secondary: [.teres, .biceps, .deltRear]),
        Rule(keywords: ["row"], groups: backGroups, primary: [.trapsMid, .rhomboids, .lats], secondary: [.trapsLower, .deltRear, .biceps]),
        Rule(keywords: ["shrug"], groups: nil, primary: [.trapsUpper], secondary: [.trapsMid]),
        Rule(keywords: ["face pull", "rear delt", "reverse fly", "reverse pec"], groups: nil,
             primary: [.deltRear], secondary: [.trapsMid, .rhomboids]),

        // Shoulders
        Rule(keywords: ["lateral raise", "side lateral", "side raise"], groups: ["shoulders"], primary: [.deltSide], secondary: [.trapsUpper]),
        Rule(keywords: ["front raise"], groups: ["shoulders"], primary: [.deltFront], secondary: [.deltSide]),
        Rule(keywords: ["overhead press", "shoulder press", "military press", "arnold"], groups: ["shoulders"],
             primary: [.deltFront, .deltSide], secondary: triceps + [.trapsUpper]),

        // Arms
        Rule(keywords: ["hammer curl"], groups: nil, primary: [.biceps, .brachialis], secondary: [.forearmFlexors]),
        Rule(keywords: ["curl"], groups: ["biceps"], primary: [.biceps], secondary: [.brachialis, .forearmFlexors]),
        Rule(keywords: ["reverse wrist", "wrist extension"], groups: nil, primary: [.forearmExtensors], secondary: []),
        Rule(keywords: ["wrist curl", "forearm curl"], groups: nil, primary: [.forearmFlexors], secondary: []),
        Rule(keywords: ["overhead", "french press", "skull"], groups: ["triceps"], primary: [.tricepsLong], secondary: [.tricepsLateral]),
        Rule(keywords: ["pushdown", "push down", "pressdown", "kickback"], groups: ["triceps"], primary: [.tricepsLateral], secondary: [.tricepsLong]),

        // Core
        Rule(keywords: ["crunch", "sit up", "leg raise", "knee raise", "plank", "ab wheel", "rollout"], groups: nil,
             primary: [.abs], secondary: [.obliques]),
        Rule(keywords: ["twist", "woodchop", "wood chop", "side bend", "oblique"], groups: nil, primary: [.obliques], secondary: [.abs]),
    ]

    /// With no naming rule, the whole muscle group counts. Includes the labels used in the old spreadsheet log.
    private static let groupFallback: [String: [MusclePart]] = [
        "back": [.lats, .rhomboids, .trapsMid, .trapsLower, .teres],
        "mid back": [.rhomboids, .trapsMid, .lats],
        "lats": [.lats, .teres],
        "traps": [.trapsUpper, .trapsMid],
        "chest": MuscleRegion.chest.parts,
        "shoulders": MuscleRegion.shoulders.parts,
        "biceps": MuscleRegion.biceps.parts,
        "triceps": triceps,
        "forearm": MuscleRegion.forearms.parts,
        "forearms": MuscleRegion.forearms.parts,
        "abs": [.abs],
        "quads": quads,
        "hamstrings": hamstrings,
        "glutes": [.gluteMax],
        "calves": MuscleRegion.calves.parts,
        "abductors": [.abductors],
        "shins": [.tibialis],
        "legs": quads + hamstrings + [.gluteMax],
    ]

    // MARK: Helpers

    /// Lowercase words separated by single spaces, so "Stiff-Leg  Deadlifts" becomes "stiff leg deadlifts".
    private static func words(_ text: String) -> String {
        text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }

    /// "Triceps & Chest" counts as both groups.
    private static func groupNames(_ group: String?) -> [String] {
        guard let group else { return [] }
        return group.lowercased().split(whereSeparator: { $0 == "&" || $0 == "/" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func build(primary: [MusclePart], secondary: [MusclePart]) -> [MuscleAssignment] {
        let primaryParts = Set(primary)
        let all = primary.map { MuscleAssignment(part: $0, role: .primary) }
            + secondary.filter { !primaryParts.contains($0) }.map { MuscleAssignment(part: $0, role: .secondary) }
        return MuscleSelection(assignments: all).assignments
    }
}
