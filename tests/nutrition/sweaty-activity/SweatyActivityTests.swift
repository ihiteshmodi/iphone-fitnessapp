import XCTest
@testable import FitnessCore

final class SweatyActivityTests: XCTestCase {
    func testAFourHourHikeWithHeavySweating() throws {
        let plan = try SweatyActivity.plan(hours: 4, sweat: .heavy, bottleLitres: 3)

        XCTAssertEqual(plan.sodiumMg, 2000...2800)
        XCTAssertEqual(plan.saltGrams.lowerBound, 5.26, accuracy: 0.01)
        XCTAssertEqual(plan.saltGrams.upperBound, 7.37, accuracy: 0.01)
        XCTAssertEqual(plan.potassiumMg, 320...900)
        XCTAssertEqual(plan.potassiumChlorideGrams.upperBound, 1.72, accuracy: 0.01)
        XCTAssertEqual(plan.sipMl, 180...360)
    }

    func testLightSweatingUsesTheLowEnd() throws {
        let plan = try SweatyActivity.plan(hours: 2, sweat: .light, bottleLitres: 1)

        XCTAssertEqual(plan.sodiumMg, 600...600)
        XCTAssertEqual(plan.saltGrams.lowerBound, 1.58, accuracy: 0.01)
    }

    func testTheInputsMustMakeSense() {
        XCTAssertThrowsError(try SweatyActivity.plan(hours: 0, sweat: .light, bottleLitres: 1)) {
            XCTAssertEqual($0 as? ValidationError, ValidationError("Enter how long the activity is"))
        }
    }
}
