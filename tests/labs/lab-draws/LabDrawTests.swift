import XCTest
@testable import FitnessCore

/// Made-up catalogue values: the real catalogue is a bundled vault file that never enters the repository.
let fixtureCatalogueJSON = #"""
{"markers": [
 {"id": "ferritin", "name": "Ferritin", "aliases": ["serum ferritin"], "chapter": "Iron Panel", "lesson": "02.10.02",
  "units": [{"unit": "ng/mL", "default": true}, {"unit": "µg/L", "toDefault": 1}], "needsLabRange": false,
  "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL", "sex": "male", "source": "T1"}],
  "doctor": [{"op": ">", "value": 900, "unit": "ng/mL", "sex": "any", "urgency": "soon", "text": "Fixture doctor line", "source": "T1"}],
  "retest": [{"text": "Fixture retest", "minWeeks": 8, "maxWeeks": 12, "after": "change", "source": "T1"}],
  "prep": ["iron-pills"]},
 {"id": "glucose", "name": "Glucose", "aliases": ["fasting glucose"], "chapter": "Metabolic", "lesson": "02.05.01",
  "units": [{"unit": "mg/dL", "default": true}, {"unit": "mmol/L", "toDefault": 18}]}
],
 "prep": [{"id": "iron-pills", "text": "Stop iron pills", "hoursBefore": 96, "markers": ["ferritin"], "source": "T0"}],
 "panels": [{"id": "iron", "name": "Iron panel", "markers": ["ferritin"], "when": "first", "source": "T0"}]
}
"""#

final class LabDrawTests: XCTestCase {
    private var db: Database!
    private var draws: LabDrawService!
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(fixtureCatalogueJSON.utf8))
        draws = LabDrawService(db, catalogue: catalogue)
    }

    private func draw(_ day: String) throws -> Int {
        try draws.addDraw(LabDrawDraft(date: date(day)))
    }

    func testADrawKeepsItsPrepState() throws {
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-12-02"), time: "08:10", lab: "Fixture lab", fastedHours: 11,
                                                trainedHard72h: true, alcohol5d: false, biotinStopped: true, ironStopped: nil, illRecently: false))

        let saved = try XCTUnwrap(try draws.draws().first { $0.id == id })
        XCTAssertEqual(saved.draft.time, "08:10")
        XCTAssertEqual(saved.draft.fastedHours, 11)
        XCTAssertEqual(saved.draft.trainedHard72h, true)
        XCTAssertEqual(saved.draft.biotinStopped, true)
        XCTAssertNil(saved.draft.ironStopped, "an unanswered question stays unanswered")
    }

    func testResultsKeepTheTypedUnitAndTheDefaultUnit() throws {
        let id = try draw("2026-12-02")

        try draws.addResult(drawID: id, markerID: "glucose", value: 5.0, unit: "mmol/L")

        let result = try XCTUnwrap(try draws.history(of: "glucose").first)
        XCTAssertEqual(result.value, 5.0)
        XCTAssertEqual(result.unit, "mmol/L")
        XCTAssertEqual(result.defaultValue ?? 0, 90, accuracy: 1e-9)
        XCTAssertEqual(result.defaultUnit, "mg/dL")
    }

    func testAnUnknownUnitIsRefused() throws {
        let id = try draw("2026-12-02")

        XCTAssertThrowsError(try draws.addResult(drawID: id, markerID: "ferritin", value: 48, unit: "pmol/L")) { error in
            XCTAssertTrue("\(error)".contains("pmol/L is not a unit the catalogue gives for Ferritin"), "\(error)")
        }
    }

    func testHistoryIsNewestFirstAndKeepsTheLabRange() throws {
        try draws.addResult(drawID: try draw("2026-06-01"), markerID: "ferritin", value: 40, unit: "ng/mL")
        try draws.addResult(drawID: try draw("2026-12-02"), markerID: "ferritin", value: 48, unit: "ng/mL", labLow: 30, labHigh: 400)

        let history = try draws.history(of: "ferritin")

        XCTAssertEqual(history.map(\.date.string), ["2026-12-02", "2026-06-01"])
        XCTAssertEqual(history.first?.labLow, 30)
        XCTAssertEqual(history.first?.labHigh, 400)
    }

    func testDeletingADrawRemovesItsResults() throws {
        let id = try draw("2026-12-02")
        try draws.addResult(drawID: id, markerID: "ferritin", value: 48, unit: "ng/mL")
        try draws.addResult(drawID: id, markerID: "glucose", value: 88, unit: "mg/dL")

        try draws.deleteDraw(id)

        XCTAssertTrue(try draws.history(of: "ferritin").isEmpty)
        XCTAssertTrue(try draws.history(of: "glucose").isEmpty)
    }

    func testTheCatalogueReadsSymptomLinesQualitativeBandsAndMonthRetests() throws {
        let json = #"""
        {"markers": [{"id": "urine-protein", "name": "Urine protein",
          "bands": [{"label": "Negative", "kind": "optimal", "low": null, "high": null, "unit": null, "values": ["Negative", "Trace"]}],
          "doctor": [{"op": null, "value": null, "unit": null, "urgency": "goNow", "text": "With chest pain", "requires": "chest pain"}],
          "retest": [{"text": "In a few months", "minMonths": 3, "maxMonths": 6, "after": "abnormal"}]}],
         "patterns": [{"id": "p", "name": "P", "conditions": [{"marker": "tsh", "op": "high", "value": null}], "extra": 1}]}
        """#
        let read = try LabCatalogue(data: Data(json.utf8))

        let marker = try XCTUnwrap(read.marker("urine-protein"))
        XCTAssertEqual(marker.bands.first?.values, ["Negative", "Trace"])
        XCTAssertNil(marker.doctor.first?.value)
        XCTAssertEqual(marker.retest.first?.minMonths, 3)
        XCTAssertEqual(read.patterns.first?.conditions?.first?.op, "high")
    }

    func testTheCatalogueFindsMarkersByNameOrAlias() {
        XCTAssertEqual(catalogue.search("serum").map(\.id), ["ferritin"])
        XCTAssertEqual(catalogue.marker("glucose")?.defaultUnit, "mg/dL")
        XCTAssertEqual(catalogue.panel("iron")?.markers, ["ferritin"])
    }

    func testUnitScalerShowsExpectedUnitAndFlags10xUnitMismatch() throws {
        let json = #"""
        {"markers": [{"id": "free-t3", "name": "Free T3",
          "units": [{"unit": "pg/mL", "default": true}, {"unit": "ng/dL", "toDefault": 10}],
          "bands": [{"label": "Lab", "kind": "lab", "low": 2.3, "high": 4.2, "unit": "pg/mL", "sex": "any"}]}]}
        """#
        let marker = try XCTUnwrap(try LabCatalogue(data: Data(json.utf8)).marker("free-t3"))

        let hint = try XCTUnwrap(LabUnitScaler.expectedHint(for: marker, sex: .male))
        XCTAssertEqual(hint.defaultUnit, "pg/mL")
        XCTAssertEqual(hint.typicalLow, 2.3)
        XCTAssertEqual(hint.typicalHigh, 4.2)

        let suggestion = try XCTUnwrap(LabUnitScaler.checkScaleMismatch(value: 0.31, unit: "pg/mL", marker: marker, sex: .male))
        XCTAssertEqual(suggestion.suggestedUnit, "ng/dL")
        XCTAssertEqual(suggestion.convertedDefaultValue, 3.1, accuracy: 1e-6)
        XCTAssertNil(LabUnitScaler.checkScaleMismatch(value: 3.1, unit: "pg/mL", marker: marker, sex: .male))
    }

    func testCustomMultiplierAcceptsUnlistedLabUnitAndConvertsToDefault() throws {
        let id = try draw("2026-12-02")

        try draws.addResult(drawID: id, markerID: "ferritin", value: 0.048, unit: "mg/L", customToDefault: 1000)

        let saved = try XCTUnwrap(try draws.history(of: "ferritin").first)
        XCTAssertEqual(saved.value, 0.048, accuracy: 1e-9)
        XCTAssertEqual(saved.unit, "mg/L")
        XCTAssertEqual(saved.customToDefault, 1000)
        XCTAssertEqual(saved.defaultValue ?? 0, 48, accuracy: 1e-6)
    }

    func testQualitativeDipsticksTitersBelowLimitAndPairedBloodPressureRoundTrip() throws {
        let json = #"""
        {"markers": [
          {"id": "urine-nitrites", "name": "Urine nitrites", "units": [],
           "bands": [{"label": "Negative", "kind": "optimal", "values": ["Negative"]}]},
          {"id": "ana", "name": "ANA", "units": [{"unit": "titer ratio", "default": true}]},
          {"id": "hs-crp", "name": "hs-CRP", "units": [{"unit": "mg/L", "default": true}]},
          {"id": "blood-pressure", "name": "Blood pressure", "units": [{"unit": "mmHg", "default": true}]}
        ]}
        """#
        let cat = try LabCatalogue(data: Data(json.utf8))
        let svc = LabDrawService(db, catalogue: cat)
        let id = try svc.addDraw(LabDrawDraft(date: date("2026-12-02"), poorSleep: true, acuteStress: false, recentVaccineOrSurgery: false, medsNoted: "Creatine 5g"))

        try svc.addQualitativeResult(drawID: id, markerID: "urine-nitrites", textValue: "Negative", specimen: "Urine")
        try svc.addQualitativeResult(drawID: id, markerID: "ana", textValue: "1:80", unit: "titer ratio")
        try svc.addResult(drawID: id, markerID: "hs-crp", value: 0.3, unit: "mg/L", valueOperator: .belowLimit)
        try svc.addResult(drawID: id, markerID: "blood-pressure", value: 126, unit: "mmHg", secondaryValue: 84, assay: "home-cuff")

        let savedDraw = try XCTUnwrap(try svc.draws().first { $0.id == id })
        XCTAssertEqual(savedDraw.draft.poorSleep, true)
        XCTAssertEqual(savedDraw.draft.medsNoted, "Creatine 5g")

        let nitrites = try XCTUnwrap(try svc.history(of: "urine-nitrites").first)
        XCTAssertEqual(nitrites.textValue, "Negative")
        XCTAssertEqual(nitrites.specimen, "Urine")

        let ana = try XCTUnwrap(try svc.history(of: "ana").first)
        XCTAssertEqual(ana.textValue, "1:80")
        XCTAssertEqual(ana.value, 80)

        let crp = try XCTUnwrap(try svc.history(of: "hs-crp").first)
        XCTAssertEqual(crp.valueOperator, .belowLimit)

        let bp = try XCTUnwrap(try svc.history(of: "blood-pressure").first)
        XCTAssertEqual(bp.value, 126)
        XCTAssertEqual(bp.secondaryValue, 84)
        XCTAssertEqual(bp.assay, "home-cuff")
    }

    func testEditingADrawUpdatesMetadataAndKeepsExistingResults() throws {
        let id = try draws.addDraw(LabDrawDraft(date: date("2025-09-27"), time: "10:11", lab: "Vardhaman jain trust"))
        try draws.addResult(drawID: id, markerID: "ferritin", value: 48, unit: "ng/mL")
        try draws.addResult(drawID: id, markerID: "glucose", value: 86, unit: "mg/dL")

        try draws.updateDraw(id, LabDrawDraft(
            date: date("2025-09-28"), time: "08:30", lab: "Sthanak Lab (Vardhman Jain Trust)",
            fastedHours: 12, biotinStopped: true, note: "Morning CBC"))

        let updated = try XCTUnwrap(try draws.draws().first { $0.id == id })
        XCTAssertEqual(updated.draft.date, date("2025-09-28"))
        XCTAssertEqual(updated.draft.time, "08:30")
        XCTAssertEqual(updated.draft.lab, "Sthanak Lab (Vardhman Jain Trust)")
        XCTAssertEqual(updated.draft.fastedHours, 12)
        XCTAssertEqual(updated.draft.biotinStopped, true)
        XCTAssertEqual(updated.draft.note, "Morning CBC")

        let inDraw = try draws.results(inDraw: id)
        XCTAssertEqual(inDraw.count, 2)
        XCTAssertEqual(try draws.history(of: "ferritin").first?.date, date("2025-09-28"))
    }

    func testSavedLabNamesReturnsUniqueTrimmedNamesOrderedNewestFirst() throws {
        _ = try draws.addDraw(LabDrawDraft(date: date("2025-06-17"), lab: "tata 1mg labs"))
        _ = try draws.addDraw(LabDrawDraft(date: date("2025-09-27"), lab: "   "))
        _ = try draws.addDraw(LabDrawDraft(date: date("2026-05-03"), lab: "  Tata 1mg Labs  "))
        _ = try draws.addDraw(LabDrawDraft(date: date("2026-10-02"), lab: "Healthians Labs"))

        let names = try draws.savedLabNames()

        XCTAssertEqual(names, ["Healthians Labs", "Tata 1mg Labs"])
    }

    func testEditingAResultUpdatesValueUnitAndRangeWhilePreservingSiblings() throws {
        let drawID = try draws.addDraw(LabDrawDraft(date: date("2025-09-27"), lab: "Vardhaman jain trust"))
        let glucoseID = try draws.addResult(drawID: drawID, markerID: "glucose", value: 86, unit: "mg/dL")
        _ = try draws.addResult(drawID: drawID, markerID: "ferritin", value: 40, unit: "ng/mL")

        try draws.updateResult(glucoseID, value: 5.0, unit: "mmol/L", labLow: 3.9, labHigh: 5.6, assay: "hexokinase")

        let updatedGlucose = try XCTUnwrap(try draws.history(of: "glucose").first)
        XCTAssertEqual(updatedGlucose.id, glucoseID)
        XCTAssertEqual(updatedGlucose.value, 5.0, accuracy: 1e-9)
        XCTAssertEqual(updatedGlucose.unit, "mmol/L")
        XCTAssertEqual(updatedGlucose.defaultValue ?? 0, 90.0, accuracy: 1e-9)
        XCTAssertEqual(updatedGlucose.labLow, 3.9)
        XCTAssertEqual(updatedGlucose.labHigh, 5.6)
        XCTAssertEqual(updatedGlucose.assay, "hexokinase")
        XCTAssertEqual(try draws.history(of: "ferritin").first?.value, 40)
    }

    func testEditingQualitativeResultAndRejectingInvalidUnitKeepIntegrity() throws {
        let json = #"""
        {"markers": [
          {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}]},
          {"id": "ana", "name": "ANA", "units": [{"unit": "titer ratio", "default": true}]}
        ]}
        """#
        let svc = LabDrawService(db, catalogue: try LabCatalogue(data: Data(json.utf8)))
        let drawID = try svc.addDraw(LabDrawDraft(date: date("2025-09-27")))
        let ferrID = try svc.addResult(drawID: drawID, markerID: "ferritin", value: 48, unit: "ng/mL")
        let anaID = try svc.addQualitativeResult(drawID: drawID, markerID: "ana", textValue: "1:40", unit: "titer ratio")

        XCTAssertThrowsError(try svc.updateResult(ferrID, value: 50, unit: "pmol/L"))
        XCTAssertEqual(try svc.history(of: "ferritin").first?.value, 48)

        try svc.updateQualitativeResult(anaID, textValue: "1:160", unit: "titer ratio")
        let ana = try XCTUnwrap(try svc.history(of: "ana").first)
        XCTAssertEqual(ana.textValue, "1:160")
        XCTAssertEqual(ana.value, 160)
    }
}
