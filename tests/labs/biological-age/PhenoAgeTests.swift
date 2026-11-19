import XCTest
@testable import FitnessCore

final class PhenoAgeTests: XCTestCase {
    private let example = PhenoAgeInputs(ageYears: 45, albuminGdL: 4.5, creatinineMgdL: 0.90, glucoseMgdL: 90, hsCRPmgL: 1.0,
                                         lymphocytePercent: 30, mcvFL: 90, rdwCVPercent: 13, alpUL: 70, wbcK: 6.0)

    func testTheResearchAgentsWorkedExample() throws {
        let result = PhenoAge.calculate(example)

        XCTAssertEqual(result.linearPredictor, -9.4751, accuracy: 1e-4)
        XCTAssertEqual(result.mortalityScore, 0.01502, accuracy: 1e-5)
        XCTAssertEqual(result.phenoAge, 37.4, accuracy: 0.05)
        XCTAssertFalse(result.isEstimate)
    }

    func testCRPBelowTheDetectionLimitUsesLimitOverRootTwoAndIsAnEstimate() {
        var below = example
        below.hsCRPmgL = nil
        below.hsCRPBelowLimit = 0.3

        let result = PhenoAge.calculate(below)
        var direct = example
        direct.hsCRPmgL = 0.3 / 2.0.squareRoot()

        XCTAssertEqual(result.phenoAge, PhenoAge.calculate(direct).phenoAge, accuracy: 1e-9)
        XCTAssertTrue(result.isEstimate)
    }

    func testOnlyAWholeDrawGivesAnAge() throws {
        let db = try Database.inMemory()
        let draws = LabDrawService(db, catalogue: PhenoAge.inputCatalogue)
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-05-03")))
        for (marker, value, unit) in [("albumin", 4.5, "g/dL"), ("creatinine", 0.9, "mg/dL"), ("glucose", 90.0, "mg/dL"),
                                      ("lymphocyte-pct", 30.0, "%"), ("mcv", 90.0, "fL"), ("rdw", 13.0, "%"), ("alp", 70.0, "U/L"),
                                      ("wbc", 6.0, "x10^3/uL")] {
            try draws.addResult(drawID: id, markerID: marker, value: value, unit: unit)
        }

        let missing = try PhenoAge.forDraw(id, draws: draws, birthDate: date("1981-05-03"))
        guard case .missing(let inputs) = missing else { return XCTFail("needs hs-CRP") }
        XCTAssertEqual(inputs, [.hsCRP])

        try draws.addResult(drawID: id, markerID: "hs-crp", value: 1.0, unit: "mg/L")
        guard case .calculated(let result) = try PhenoAge.forDraw(id, draws: draws, birthDate: date("1981-05-03")) else { return XCTFail("complete") }
        XCTAssertEqual(result.phenoAge, 37.4, accuracy: 0.05)
    }
}
