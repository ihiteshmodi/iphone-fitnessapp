import XCTest
@testable import FitnessCore

final class LabExpressionTests: XCTestCase {
    func testArithmeticFollowsPrecedenceAndParentheses() {
        XCTAssertEqual(LabExpression.evaluate("{a} + {b} * 2", values: ["a": 1, "b": 3]), 7)
        XCTAssertEqual(LabExpression.evaluate("({a} + {b}) * 2", values: ["a": 1, "b": 3]), 8)
        XCTAssertEqual(LabExpression.evaluate("{x-y} - -2 / 4", values: ["x-y": 1]), 1.5)
    }

    func testComparisonsGiveOneOrZero() {
        XCTAssertEqual(LabExpression.evaluate("{a} > 20", values: ["a": 30]), 1)
        XCTAssertEqual(LabExpression.evaluate("{a} >= 20", values: ["a": 10]), 0)
    }

    func testNoValueForAMissingInputABadExpressionOrDivisionByZero() {
        XCTAssertNil(LabExpression.evaluate("{a} + {b}", values: ["a": 1]))
        XCTAssertNil(LabExpression.evaluate("{a} +", values: ["a": 1]))
        XCTAssertNil(LabExpression.evaluate("{a} / {b}", values: ["a": 1, "b": 0]))
    }
}

final class LabFormulaTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "a", "name": "A", "chapter": "X", "units": [{"unit": "u", "default": true}, {"unit": "big-unit", "toDefault": 5}]},
     {"id": "b", "name": "B", "chapter": "X", "units": [{"unit": "u", "default": true}]},
     {"id": "c", "name": "C", "chapter": "X", "computed": true, "units": [{"unit": "u", "default": true}],
      "formula": {"expr": "{a} - {b}", "inputs": {"a": "u", "b": "u"}}},
     {"id": "d", "name": "D", "chapter": "X", "computed": true, "units": [{"unit": "u", "default": true}],
      "formula": {"expr": "{a} + 1", "inputs": {"a": "u"}, "onlyIf": "{a} > 20"}},
     {"id": "e", "name": "E", "chapter": "X", "computed": true, "units": [{"unit": "u", "default": true}],
      "formula": {"expr": "{c} * 2", "inputs": {"c": "u"}}},
     {"id": "r", "name": "R", "chapter": "X", "computed": true, "units": [],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 2, "high": 3}],
      "formula": {"expr": "{a} / {b}", "inputs": {"a": "u", "b": "u"}}}
    ]}
    """#
    private var draws: LabDrawService!
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws {
        catalogue = try LabCatalogue(data: Data(json.utf8))
        draws = LabDrawService(try Database.inMemory(), catalogue: catalogue)
    }

    private func draw(_ day: String, _ values: [(String, Double, String)]) throws -> Int {
        let id = try draws.addDraw(LabDrawDraft(date: date(day)))
        for (marker, value, unit) in values { try draws.addResult(drawID: id, markerID: marker, value: value, unit: unit) }
        return id
    }

    private func value(_ marker: String, in drawID: Int) throws -> LabResult? {
        try draws.results(inDraw: drawID).first { $0.markerID == marker }
    }

    func testAFormulaIsWorkedOutFromOneDraw() throws {
        let id = try draw("2026-05-03", [("a", 10, "u"), ("b", 4, "u")])

        let c = try XCTUnwrap(try value("c", in: id))
        XCTAssertEqual(c.value, 6)
        XCTAssertEqual(c.unit, "u")
        XCTAssertTrue(c.isCalculated)
    }

    func testInputsTypedInAnotherUnitAreConvertedFirst() throws {
        let id = try draw("2026-05-03", [("a", 2, "big-unit"), ("b", 4, "u")])

        XCTAssertEqual(try value("c", in: id)?.value, 6)
    }

    func testNothingIsCalculatedWithoutEveryInputFromThatDraw() throws {
        let first = try draw("2026-05-03", [("a", 10, "u")])
        let second = try draw("2026-06-03", [("b", 4, "u")])

        XCTAssertNil(try value("c", in: first))
        XCTAssertNil(try value("c", in: second))
    }

    func testAValueTheLabPrintedWins() throws {
        let id = try draw("2026-05-03", [("a", 10, "u"), ("b", 4, "u"), ("c", 7, "u")])

        let cs = try draws.results(inDraw: id).filter { $0.markerID == "c" }
        XCTAssertEqual(cs.map(\.value), [7])
        XCTAssertEqual(cs.map(\.isCalculated), [false])
    }

    func testAFormulaWithAConditionIsOnlyUsedWhenItHolds() throws {
        let low = try draw("2026-05-03", [("a", 10, "u")])
        let high = try draw("2026-06-03", [("a", 30, "u")])

        XCTAssertNil(try value("d", in: low))
        XCTAssertEqual(try value("d", in: high)?.value, 31)
    }

    func testOneCalculatedMarkerCanFeedAnother() throws {
        let id = try draw("2026-05-03", [("a", 10, "u"), ("b", 4, "u")])

        XCTAssertEqual(try value("e", in: id)?.value, 12)
    }

    func testACalculatedRatioIsReadAgainstBandsWithNoUnit() throws {
        let id = try draw("2026-05-03", [("a", 10, "u"), ("b", 4, "u")])
        let r = try XCTUnwrap(try value("r", in: id))

        let reading = LabReader.read(value: r.value, unit: r.unit, marker: try XCTUnwrap(catalogue.marker("r")), sex: .male)

        XCTAssertEqual(reading.status, .optimal)
    }

    func testTheHistoryOfACalculatedMarkerListsEveryDrawNewestFirst() throws {
        _ = try draw("2026-05-03", [("a", 10, "u"), ("b", 4, "u")])
        _ = try draw("2026-10-01", [("a", 9, "u"), ("b", 4, "u")])

        XCTAssertEqual(try draws.history(of: "c").map(\.value), [5, 6])
    }
}
