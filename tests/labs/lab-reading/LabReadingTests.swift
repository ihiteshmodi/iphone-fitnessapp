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

    func testUndisputedAdjacentOptimalBandsUnionCleanlyWithoutFalseDisputedStatus() throws {
        let altJSON = #"""
        {"markers": [{"id": "alt-split", "name": "ALT", "units": [{"unit": "U/L", "default": true}],
          "bands": [
            {"label": "Excellent", "kind": "optimal", "low": null, "high": 17, "unit": "U/L"},
            {"label": "Normal-optimal", "kind": "optimal", "low": 17, "high": 25, "unit": "U/L"}
          ]}]}
        """#
        let cat = try LabCatalogue(data: Data(altJSON.utf8))
        let m = try XCTUnwrap(cat.marker("alt-split"))

        XCTAssertEqual(LabReader.read(value: 14, unit: "U/L", marker: m, sex: .male).status, .optimal)
        XCTAssertEqual(LabReader.read(value: 21, unit: "U/L", marker: m, sex: .male).status, .optimal)
        XCTAssertEqual(LabReader.read(value: 32, unit: "U/L", marker: m, sex: .male).status, .high)
    }

    func testDemographicStratumSelectorPicksAgeBracketAndAssay() throws {
        let strataJSON = #"""
        {"markers": [{"id": "igf-1", "name": "IGF-1", "units": [{"unit": "ng/mL", "default": true}],
          "strata": [
            {"population": "Adult 21-30", "sex": "any", "unit": "ng/mL", "standardLow": 115, "standardHigh": 340, "optimalLow": 160, "optimalHigh": 260, "ageMin": 21, "ageMax": 30, "bands": []},
            {"population": "Adult 31-40", "sex": "any", "unit": "ng/mL", "standardLow": 100, "standardHigh": 280, "optimalLow": 140, "optimalHigh": 220, "ageMin": 31, "ageMax": 40,
             "bands": [{"tier": "suboptimal_low", "min": 100, "max": 140, "meaning": "Low-normal"}, {"tier": "optimal", "min": 140, "max": 220, "meaning": "Sweet spot"}]}
          ]}]}
        """#
        let cat = try LabCatalogue(data: Data(strataJSON.utf8))
        let m = try XCTUnwrap(cat.marker("igf-1"))
        let prefs = LabPreferences(sex: .male, isSexConfirmed: true, birthDate: date("1992-05-01"))
        let res = LabResult(id: 1, drawID: 1, date: date("2026-10-01"), markerID: "igf-1", value: 130, unit: "ng/mL", defaultValue: 130, defaultUnit: "ng/mL")

        let reading = LabReader.read(result: res, marker: m, preferences: prefs)
        XCTAssertEqual(reading.activeStratum?.population, "Adult 31-40")
        XCTAssertEqual(reading.status, .low)
        XCTAssertEqual(reading.tier, .suboptimalLow)
    }

    func testQualitativeDipsticksTitersLabULNPairedBPAndConditionalDoctorLines() throws {
        let mixJSON = #"""
        {"markers": [
          {"id": "urine-nitrites", "name": "Urine nitrites", "units": [],
           "bands": [{"label": "Negative", "kind": "optimal", "values": ["Negative"]},
                     {"label": "Positive", "kind": "high", "values": ["Positive"]}]},
          {"id": "ana", "name": "ANA", "units": [{"unit": "titer ratio", "default": true}],
           "strata": [{"population": "Adult All", "sex": "any", "unit": "titer ratio", "optimalLow": null, "optimalHigh": 40,
                       "bands": [{"tier": "optimal", "min": null, "max": 40, "meaning": "Negative or 1:40"},
                                 {"tier": "borderline_high", "min": 40, "max": 160, "meaning": "1:80 borderline"}]}]},
          {"id": "rf", "name": "Rheumatoid Factor", "needsLabRange": true, "units": [{"unit": "IU/mL", "default": true}]},
          {"id": "blood-pressure", "name": "Blood pressure", "units": [{"unit": "mmHg", "default": true}]},
          {"id": "triglycerides", "name": "Triglycerides", "units": [{"unit": "mg/dL", "default": true}],
           "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 100, "unit": "mg/dL"}],
           "doctor": [{"op": ">=", "value": 500, "unit": "mg/dL", "urgency": "sameDay", "text": "Pancreatitis risk", "requires": "severe abdominal pain"}]}
        ]}
        """#
        let cat = try LabCatalogue(data: Data(mixJSON.utf8))
        let prefs = LabPreferences(sex: .male, isSexConfirmed: true)

        let nitNeg = LabResult(id: 1, drawID: 1, date: date("2026-10-01"), markerID: "urine-nitrites", value: 0, textValue: "Negative", unit: "")
        let nitPos = LabResult(id: 2, drawID: 1, date: date("2026-10-01"), markerID: "urine-nitrites", value: 0, textValue: "Positive", unit: "")
        XCTAssertEqual(LabReader.read(result: nitNeg, marker: cat.marker("urine-nitrites")!, preferences: prefs).status, .optimal)
        XCTAssertEqual(LabReader.read(result: nitPos, marker: cat.marker("urine-nitrites")!, preferences: prefs).status, .high)

        let ana80 = LabResult(id: 3, drawID: 1, date: date("2026-10-01"), markerID: "ana", value: 80, textValue: "1:80", unit: "titer ratio", defaultValue: 80, defaultUnit: "titer ratio")
        let anaRead = LabReader.read(result: ana80, marker: cat.marker("ana")!, preferences: prefs)
        XCTAssertEqual(anaRead.status, .high)
        XCTAssertEqual(anaRead.tier, .watchHigh)

        let rfHigh = LabResult(id: 4, drawID: 1, date: date("2026-10-01"), markerID: "rf", value: 45, unit: "IU/mL", labLow: 0, labHigh: 14, defaultValue: 45, defaultUnit: "IU/mL")
        let rfRead = LabReader.read(result: rfHigh, marker: cat.marker("rf")!, preferences: prefs)
        XCTAssertEqual(rfRead.status, .high)
        XCTAssertEqual(rfRead.tier, .high)
        XCTAssertTrue(rfRead.tierLabel?.contains("3× ULN") ?? false)

        let bp = LabResult(id: 5, drawID: 1, date: date("2026-10-01"), markerID: "blood-pressure", value: 124, secondaryValue: 84, unit: "mmHg", defaultValue: 124, defaultUnit: "mmHg")
        let bpRead = LabReader.read(result: bp, marker: cat.marker("blood-pressure")!, preferences: prefs)
        XCTAssertEqual(bpRead.status, .high)
        XCTAssertEqual(bpRead.tierLabel, "Stage 1 hypertension")

        let tg = LabResult(id: 6, drawID: 1, date: date("2026-10-01"), markerID: "triglycerides", value: 540, unit: "mg/dL", defaultValue: 540, defaultUnit: "mg/dL")
        let tgRead = LabReader.read(result: tg, marker: cat.marker("triglycerides")!, preferences: prefs)
        XCTAssertEqual(tgRead.conditionalDoctorLines.count, 1)
    }
}
