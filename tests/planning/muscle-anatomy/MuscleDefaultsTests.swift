import XCTest
@testable import FitnessCore

/// Scenarios from muscle-anatomy.feature about automatic muscles.
final class MuscleDefaultsTests: XCTestCase {
    private func primary(_ name: String, _ group: String?) -> Set<MusclePart> {
        Set(MuscleDefaults.assignments(exerciseName: name, group: group).filter { $0.role == .primary }.map(\.part))
    }

    private func secondary(_ name: String, _ group: String?) -> Set<MusclePart> {
        Set(MuscleDefaults.assignments(exerciseName: name, group: group).filter { $0.role == .secondary }.map(\.part))
    }

    // Scenario Outline: Automatic muscles come from the exercise name and group
    func testAutomaticMusclesFromNameAndGroup() {
        let rows: [(name: String, group: String, primary: Set<MusclePart>, secondary: Set<MusclePart>)] = [
            ("Guillotine press - incline black chest machine", "Chest", [.chestUpper], [.chestMid, .deltFront, .tricepsLong, .tricepsLateral]),
            ("Chest Dips Machine", "Chest", [.chestLower], [.chestMid, .deltFront, .tricepsLong, .tricepsLateral]),
            ("Chest Fly Machine", "Chest", [.chestMid], [.chestUpper, .chestLower, .deltFront]),
            ("Champagne Press", "Chest", [.chestUpper, .chestMid, .chestLower], [.deltFront, .tricepsLong, .tricepsLateral]),
            ("Lat Pulldown", "Back", [.lats], [.teres, .biceps, .deltRear]),
            ("Power Row machine - Orange", "Back", [.trapsMid, .rhomboids, .lats], [.trapsLower, .deltRear, .biceps]),
            ("Triceps Pushdown", "Triceps", [.tricepsLateral], [.tricepsLong]),
            ("DB Overhead Triceps", "Triceps", [.tricepsLong], [.tricepsLateral]),
            ("Triceps Press", "Triceps", [.tricepsLong, .tricepsLateral], []),
            ("Preacher Curls", "Biceps", [.biceps], [.brachialis, .forearmFlexors]),
            ("DB Hammer Curls", "Biceps", [.biceps, .brachialis], [.forearmFlexors]),
            ("Belt machine Stiff Leg Deadlift", "Hamstrings", [.hamOuter, .hamInner, .gluteMax], [.erectors]),
            ("Goblet Squat", "Legs", [.quadRectus, .quadOuter, .quadInner], [.gluteMax, .adductors]),
            ("Cable Hip Abduction", "Legs", [.abductors], [.gluteMax]),
            ("Shrugs", "Traps", [.trapsUpper], [.trapsMid]),
        ]
        for row in rows {
            XCTAssertEqual(primary(row.name, row.group), row.primary, "primary of \(row.name)")
            XCTAssertEqual(secondary(row.name, row.group), row.secondary, "secondary of \(row.name)")
        }
    }

    func testSeatedRowsMidBackIsARow() {
        XCTAssertEqual(primary("Seated rows mid back", "Back"), [.trapsMid, .rhomboids, .lats])
    }

    // Scenario: Unknown exercise names fall back to the whole muscle group
    func testUnknownNameFallsBackToTheWholeGroup() {
        XCTAssertEqual(primary("Bicep Station", "Biceps"), [.biceps, .brachialis])
        XCTAssertEqual(secondary("Bicep Station", "Biceps"), [])
        XCTAssertEqual(primary("Whatever", "Chest"), [.chestUpper, .chestMid, .chestLower])
        XCTAssertEqual(primary("Whatever", "Shoulders"), [.deltFront, .deltSide, .deltRear])
        XCTAssertEqual(primary("Whatever", "Back"), [.lats, .rhomboids, .trapsMid, .trapsLower, .teres])
    }

    // Scenario: An exercise with no group and no clue highlights nothing
    func testNoGroupAndNoClueMeansNothing() {
        XCTAssertEqual(MuscleDefaults.assignments(exerciseName: "Mystery Move", group: nil), [])
        XCTAssertEqual(MuscleDefaults.assignments(exerciseName: "Mystery Move", group: "  "), [])
    }

    func testLogLabelsFromTheOldSheetAreUnderstood() {
        XCTAssertEqual(primary("Whatever", "Legs"), [.quadRectus, .quadOuter, .quadInner, .hamOuter, .hamInner, .gluteMax])
        XCTAssertEqual(primary("Whatever", "Mid Back"), [.rhomboids, .trapsMid, .lats])
        XCTAssertEqual(primary("Whatever", "Lats"), [.lats, .teres])
        XCTAssertEqual(primary("Whatever", "Forearm"), [.forearmFlexors, .forearmExtensors])
        XCTAssertEqual(MuscleDefaults.assignments(exerciseName: "HIIT", group: "HIIT"), [])
        XCTAssertEqual(MuscleDefaults.assignments(exerciseName: "Hold", group: "Hold"), [])
    }

    func testCombinedGroupLabelUsesBothGroups() {
        XCTAssertEqual(primary("Dips", "Triceps & Chest"), [.chestLower], "the Chest rule for dips applies")
        XCTAssertEqual(primary("Something", "Triceps & Chest"), [.tricepsLong, .tricepsLateral, .chestUpper, .chestMid, .chestLower])
    }

    func testMatchingIgnoresCaseSpacingAndPlurals() {
        XCTAssertEqual(primary("  LAT   PULLDOWNS ", "back"), [.lats])
        XCTAssertEqual(primary("Seated Cable Rows", "BACK"), [.trapsMid, .rhomboids, .lats])
        XCTAssertEqual(primary("barbell stiff-leg deadlifts", "Hamstrings"), [.hamOuter, .hamInner, .gluteMax])
    }

    func testKeywordsMatchWholeWordsOnly() {
        XCTAssertEqual(primary("Narrow Grip Chest Work", "Chest"), [.chestUpper, .chestMid, .chestLower], "'narrow' is not a row")
        XCTAssertEqual(primary("Arrowhead Drill", "Back"), [.lats, .rhomboids, .trapsMid, .trapsLower, .teres])
    }

    func testMoreSpecificRulesWinOverGeneralOnes() {
        XCTAssertEqual(primary("Stiff Leg Deadlift", "Back"), [.hamOuter, .hamInner, .gluteMax])
        XCTAssertEqual(primary("Traditional Deadlift", "Legs"), [.erectors, .gluteMax, .hamOuter, .hamInner])
        XCTAssertEqual(primary("Seated Calf Raise", "Calves"), [.soleus])
        XCTAssertEqual(primary("Standing Calf Raise", "Calves"), [.gastrocnemius, .soleus])
        XCTAssertEqual(primary("Bulgarian Split Squat", "Quads"), [.quadRectus, .quadOuter, .quadInner, .gluteMax])
        XCTAssertEqual(primary("Reverse Wrist Curl", "Forearms"), [.forearmExtensors])
        XCTAssertEqual(primary("Wrist Curl", "Forearms"), [.forearmFlexors])
    }

    func testChestRulesDoNotLeakIntoOtherGroups() {
        XCTAssertEqual(primary("Incline Dumbbell Curl", "Biceps"), [.biceps])
        XCTAssertEqual(primary("Triceps Kickback", "Triceps"), [.tricepsLateral])
        XCTAssertEqual(primary("Glutes Kickback", "Legs"), [.gluteMax])
    }

    func testLowerBodyAndCoreExamples() {
        XCTAssertEqual(primary("Lying Leg Curl (back)", "Legs"), [.hamOuter, .hamInner])
        XCTAssertEqual(secondary("Lying Leg Curl (back)", "Legs"), [.gastrocnemius])
        XCTAssertEqual(primary("Single Leg Extension (front)", "Legs"), [.quadRectus, .quadOuter, .quadInner])
        XCTAssertEqual(primary("Step Ups", "Legs"), [.quadRectus, .quadOuter, .quadInner, .gluteMax])
        XCTAssertEqual(primary("Hanging leg raises", "Abs"), [.abs])
        XCTAssertEqual(secondary("Hanging leg raises", "Abs"), [.obliques])
        XCTAssertEqual(primary("Cable Woodchop", "Abs"), [.obliques])
        XCTAssertEqual(primary("Reverse Hacksquat", "Legs"), [.quadRectus, .quadOuter, .quadInner])
    }

    func testShoulderExamples() {
        XCTAssertEqual(primary("Side Lateral (Cable)", "Shoulders"), [.deltSide])
        XCTAssertEqual(primary("Machine Shoulder Press", "Shoulders"), [.deltFront, .deltSide])
        XCTAssertEqual(primary("Face Pulls", "Shoulders"), [.deltRear])
        XCTAssertEqual(primary("Front Raise", "Shoulders"), [.deltFront])
    }

    func testPrimaryAndSecondaryNeverOverlap() {
        for name in ["Champagne Press", "Lat Pulldown", "Goblet Squat", "Cable Woodchop", "Preacher Curls", "Triceps Pushdown"] {
            let all = MuscleDefaults.assignments(exerciseName: name, group: "Chest")
            XCTAssertEqual(all.count, Set(all.map(\.part)).count, "\(name) lists a part twice")
        }
    }

    func testResultsComeInBodyOrder() {
        let order = MuscleDefaults.assignments(exerciseName: "Whatever", group: "Back").map(\.part)
        XCTAssertEqual(order, [.trapsMid, .trapsLower, .lats, .rhomboids, .teres])
    }
}
