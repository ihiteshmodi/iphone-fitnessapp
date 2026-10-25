import XCTest
@testable import FitnessCore

/// Scenarios from muscle-anatomy.feature about choosing muscles in the editor.
final class MuscleSelectionTests: XCTestCase {
    // Scenario: Tapping a part cycles none, primary, secondary
    func testTappingCyclesNonePrimarySecondaryNone() {
        var selection = MuscleSelection()
        XCTAssertNil(selection.role(of: .lats))
        selection.cycle(.lats)
        XCTAssertEqual(selection.role(of: .lats), .primary)
        selection.cycle(.lats)
        XCTAssertEqual(selection.role(of: .lats), .secondary)
        selection.cycle(.lats)
        XCTAssertNil(selection.role(of: .lats))
    }

    // Scenario: Choose the entire upper back
    func testSelectingTheEntireRegionMakesEveryPartPrimary() {
        var selection = MuscleSelection()
        selection.selectEntire(.upperBack)
        for part in MuscleRegion.upperBack.parts {
            XCTAssertEqual(selection.role(of: part), .primary, "\(part)")
        }
        XCTAssertNil(selection.role(of: .biceps), "other regions are untouched")
    }

    func testSelectingTheEntireRegionOverridesSecondaryParts() {
        var selection = MuscleSelection(assignments: [MuscleAssignment(part: .lats, role: .secondary)])
        selection.selectEntire(.upperBack)
        XCTAssertEqual(selection.role(of: .lats), .primary)
    }

    func testClearingARegionOnlyClearsThatRegion() {
        var selection = MuscleSelection()
        selection.selectEntire(.upperBack)
        selection.selectEntire(.biceps)
        selection.clear(.upperBack)
        XCTAssertTrue(MuscleRegion.upperBack.parts.allSatisfy { selection.role(of: $0) == nil })
        XCTAssertEqual(selection.role(of: .biceps), .primary)
    }

    func testRegionStateSaysNoneSomeOrAll() {
        var selection = MuscleSelection()
        XCTAssertEqual(selection.state(of: .triceps), .none)
        selection.setRole(.primary, for: .tricepsLong)
        XCTAssertEqual(selection.state(of: .triceps), .some)
        selection.setRole(.secondary, for: .tricepsLateral)
        XCTAssertEqual(selection.state(of: .triceps), .some, "secondary is not 'entire region'")
        selection.selectEntire(.triceps)
        XCTAssertEqual(selection.state(of: .triceps), .all)
    }

    func testTheRegionButtonTogglesBetweenEntireAndNone() {
        var selection = MuscleSelection()
        selection.toggleEntire(.chest)
        XCTAssertEqual(selection.state(of: .chest), .all)
        selection.toggleEntire(.chest)
        XCTAssertEqual(selection.state(of: .chest), .none)
        selection.setRole(.primary, for: .chestUpper)
        selection.toggleEntire(.chest)
        XCTAssertEqual(selection.state(of: .chest), .all, "a partial selection grows to the whole region")
    }

    // Scenario: Choose specific parts only
    func testSpecificPartsOnly() {
        var selection = MuscleSelection()
        selection.setRole(.primary, for: .rhomboids)
        selection.setRole(.secondary, for: .lats)
        XCTAssertEqual(selection.assignments, [
            MuscleAssignment(part: .lats, role: .secondary),
            MuscleAssignment(part: .rhomboids, role: .primary),
        ])
    }

    func testSettingNilRemovesAPart() {
        var selection = MuscleSelection(assignments: [MuscleAssignment(part: .lats, role: .primary)])
        selection.setRole(nil, for: .lats)
        XCTAssertTrue(selection.assignments.isEmpty)
        XCTAssertTrue(selection.isEmpty)
    }

    func testAssignmentsComeBackInBodyOrder() {
        var selection = MuscleSelection()
        selection.setRole(.primary, for: .tibialis)
        selection.setRole(.primary, for: .chestUpper)
        selection.setRole(.secondary, for: .biceps)
        XCTAssertEqual(selection.assignments.map(\.part), [.chestUpper, .biceps, .tibialis])
    }

    func testBuildingFromAssignmentsKeepsTheLastRoleForARepeatedPart() {
        let selection = MuscleSelection(assignments: [
            MuscleAssignment(part: .lats, role: .primary),
            MuscleAssignment(part: .lats, role: .secondary),
        ])
        XCTAssertEqual(selection.role(of: .lats), .secondary)
        XCTAssertEqual(selection.assignments.count, 1)
    }
}
