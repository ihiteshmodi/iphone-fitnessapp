import XCTest
@testable import FitnessCore

final class RepRangeTests: XCTestCase {
    func testTheMiddleOfARepRangeIsTheAverageRoundedUp() {
        let examples: [(min: Double, max: Double, middle: Int)] = [(8, 16, 12), (6, 10, 8), (10, 15, 13), (12, 15, 14), (6, 12, 9), (4.5, 7.5, 6), (1, 1, 1)]

        for example in examples {
            XCTAssertEqual(RepRange.middle(min: example.min, max: example.max), example.middle, "\(example.min) to \(example.max)")
        }
    }

    func testTheMiddleIsAtLeastOneRep() {
        XCTAssertEqual(RepRange.middle(min: 0, max: 0), 1)
    }
}
