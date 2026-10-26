import XCTest
@testable import FitnessCore

/// Scenarios from muscle-anatomy.feature about where the small card frames the body.
final class MuscleFigureCropTests: XCTestCase {
    private func primary(_ parts: MusclePart...) -> [MuscleAssignment] { parts.map { MuscleAssignment(part: $0, role: .primary) } }

    private func views(_ assignments: [MuscleAssignment]) -> [BodyView] { MuscleFigureCrop.frames(for: assignments).map(\.view) }

    private let figure = CGRect(x: 0, y: 0, width: MuscleFigureData.width, height: MuscleFigureData.height)

    // Scenario Outline: Where the card frames
    func testWhichSidesOfTheBodyAreShown() {
        XCTAssertEqual(views(primary(.tricepsLateral)), [.back])
        XCTAssertEqual(views(primary(.chestUpper)), [.front])
        XCTAssertEqual(views(primary(.lats)), [.back])
        XCTAssertEqual(views(primary(.biceps)), [.front])
        XCTAssertEqual(views(primary(.quadRectus, .quadOuter, .quadInner, .gluteMax)), [.front, .back])
    }

    func testAPartDrawnOnBothSidesIsShownOnBoth() {
        XCTAssertEqual(views(primary(.deltSide)), [.front, .back])
    }

    // Scenario: A secondary muscle on the other side of the body gets its own picture
    func testASecondaryMuscleOnTheOtherSideAddsItsOwnPicture() {
        let latPulldown = primary(.lats) + [
            MuscleAssignment(part: .biceps, role: .secondary),
            MuscleAssignment(part: .deltRear, role: .secondary),
            MuscleAssignment(part: .teres, role: .secondary),
        ]
        XCTAssertEqual(views(latPulldown), [.front, .back])
    }

    func testLegExtensionWithHamstringsAddedShowsTheFrontAndTheBack() {
        let legExtension = primary(.quadRectus, .quadOuter, .quadInner) + [MuscleAssignment(part: .hamOuter, role: .secondary)]
        XCTAssertEqual(views(legExtension), [.front, .back])
    }

    func testSecondaryMusclesOnTheSameSideAreFramedWithThePrimaryOnes() throws {
        let primaryOnly = try XCTUnwrap(MuscleFigureCrop.frames(for: primary(.lats)).first).rect
        let withSecondary = try XCTUnwrap(MuscleFigureCrop.frames(for: primary(.lats) + [MuscleAssignment(part: .hamOuter, role: .secondary)])
            .first { $0.view == .back }).rect

        XCTAssertGreaterThan(withSecondary.height, primaryOnly.height, "the back frame now reaches down to the hamstrings")
    }

    func testWhenNothingIsPrimaryTheSecondaryMusclesAreFramed() {
        let onlySecondary = [MuscleAssignment(part: .biceps, role: .secondary)]
        XCTAssertEqual(views(onlySecondary), [.front])
    }

    func testNoMusclesMeansNoPictures() {
        XCTAssertTrue(MuscleFigureCrop.frames(for: []).isEmpty)
    }

    // Scenario: The card zooms to the arms for pushdowns
    func testTricepsAreFramedOnTheUpperBackNotTheWholeBody() throws {
        let frame = try XCTUnwrap(MuscleFigureCrop.frames(for: primary(.tricepsLateral, .tricepsLong)).first).rect

        XCTAssertLessThan(frame.maxY, 220, "only the upper body")
        XCTAssertLessThan(frame.height, MuscleFigureData.height / 2)
    }

    // Scenario: The frame never gets too tight
    func testASmallMuscleStillGetsAFrameOfAtLeast90Units() throws {
        let frame = try XCTUnwrap(MuscleFigureCrop.frames(for: primary(.brachialis)).first).rect

        XCTAssertGreaterThanOrEqual(frame.width, 90)
        XCTAssertGreaterThanOrEqual(frame.height, 90)
    }

    func testTheFrameNeverLeavesTheFigure() {
        for part in MusclePart.allCases {
            for frame in MuscleFigureCrop.frames(for: primary(part)) {
                XCTAssertTrue(figure.contains(frame.rect), "\(part) \(frame.view): \(frame.rect)")
            }
        }
    }

    func testTheFrameContainsEveryPrimaryPartOfThatSideUnlessItIsTallerThanTheFigureAllows() throws {
        for part in MusclePart.allCases {
            for frame in MuscleFigureCrop.frames(for: primary(part)) {
                let shapes = (frame.view == .front ? MuscleFigureData.front : MuscleFigureData.back)[part.rawValue] ?? []
                let bounds = try XCTUnwrap(MuscleFigureCrop.bounds(of: shapes))
                XCTAssertTrue(frame.rect.insetBy(dx: -0.01, dy: -0.01).contains(bounds), "\(part) \(frame.view)")
            }
        }
    }

    func testFramesAreSquareWhenTheyFitAndNeverNarrowerThanTheContent() throws {
        let frame = try XCTUnwrap(MuscleFigureCrop.frames(for: primary(.chestUpper)).first).rect
        XCTAssertEqual(frame.width, frame.height, accuracy: 0.001)
    }

    func testFramesComeFrontFirstThenBack() {
        let order = MuscleFigureCrop.frames(for: primary(.gluteMax, .quadOuter)).map(\.view)
        XCTAssertEqual(order, [.front, .back])
    }

    func testBoundsOfPathData() throws {
        let bounds = try XCTUnwrap(MuscleFigureCrop.bounds(of: ["M 10 20 C 12 22 30 40 50 60 Z"]))
        XCTAssertEqual(bounds, CGRect(x: 10, y: 20, width: 40, height: 40))
        XCTAssertNil(MuscleFigureCrop.bounds(of: []))
    }
}
