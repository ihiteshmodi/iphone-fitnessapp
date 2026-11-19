import XCTest
@testable import FitnessCore

final class LabReadingTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}, {"unit": "µg/L", "toDefault": 1}],
      "bands": [
        {"label": "Lab", "kind": "lab", "low": 30, "high": 400, "unit": "ng/mL", "sex": "any"},
        {"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL", "sex": "male", "dispute": "C900", "source": "T1"},
        {"label": "Optimal", "kind": "optimal", "low": 80, "high": 150, "unit": "ng/mL", "sex": "male", "dispute": "C900", "source": "T2"},
        {"label": "Women", "kind": "optimal", "low": 40, "high": 100, "unit": "ng/mL", "sex": "female"},
        {"label": "Wordy", "kind": "flag", "low": 1, "high": 5000, "unit": null}],
      "doctor": [
        {"op": ">", "value": 900, "unit": "ng/mL", "urgency": "soon", "text": "Soon line"},
        {"op": ">", "value": 1500, "unit": "ng/mL", "urgency": "sameDay", "text": "Same-day line"}]},
     {"id": "alt", "name": "ALT", "units": [{"unit": "U/L", "default": true}],
      "bands": [
        {"label": "Optimal", "kind": "optimal", "low": 0, "high": 20, "unit": "U/L"},
        {"label": "Watch", "kind": "watch", "low": 20, "high": 25, "unit": "U/L"},
        {"label": "Flag", "kind": "flag", "low": 25, "high": 40, "unit": "U/L"}]}
    ]}
    """#
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws { catalogue = try LabCatalogue(data: Data(json.utf8)) }

    private func read(_ value: Double, _ unit: String = "ng/mL", marker: String = "ferritin", sex: LabSex = .male) -> LabReading {
        LabReader.read(value: value, unit: unit, marker: catalogue.marker(marker)!, sex: sex)
    }

    func testInsideEveryOptimalBandIsOptimal() {
        XCTAssertEqual(read(100).status, .optimal)
    }

    func testInTheGapBetweenDisputedBandsIsDisputedWithoutAFlag() {
        let reading = read(70)

        XCTAssertEqual(reading.status, .disputed)
        XCTAssertEqual(reading.disputes, ["C900"])
        XCTAssertEqual(reading.optimalBands.map(\.source), ["T1", "T2"])
    }

    func testBelowOrAboveTheOptimalBands() {
        XCTAssertEqual(read(50).status, .low)
        XCTAssertEqual(read(160).status, .high)
    }

    func testAValueOnASharedEdgeNamesBothBands() {
        XCTAssertEqual(read(25, "U/L", marker: "alt").edgeLabels, ["Watch", "Flag"])
        XCTAssertEqual(read(30, "U/L", marker: "alt").edgeLabels, [])
    }

    func testDoctorLinesAreListedMostUrgentFirst() {
        XCTAssertEqual(read(1600).doctorLines.map(\.urgency), [.sameDay, .soon])
        XCTAssertEqual(read(1000).doctorLines.map(\.text), ["Soon line"])
        XCTAssertTrue(read(100).doctorLines.isEmpty)
    }

    func testOtherUnitsConvertOnlyByTheCatalogueFactorAndUnitlessBandsAreNeverCompared() {
        XCTAssertEqual(read(100, "µg/L").status, .optimal)
        XCTAssertFalse(read(100).bands.contains { $0.label == "Wordy" })
        XCTAssertEqual(read(100, "pmol/L").status, .notComparable)
    }

    func testFemaleBandsAreIgnoredForAMan() {
        XCTAssertFalse(read(45).bands.contains { $0.label == "Women" })
        XCTAssertTrue(read(45, sex: .female).bands.contains { $0.label == "Women" })
    }
}
