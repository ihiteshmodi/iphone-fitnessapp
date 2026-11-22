import XCTest
@testable import FitnessCore

final class LabValidityGateTests: XCTestCase {
    private let json = #"""
    {
      "markers": [
        {"id": "total-testosterone", "name": "Total Testosterone", "units": [{"unit": "ng/dL", "default": true}],
         "preAnalytic": {"fastingRequired": true, "timingWindow": "7:00 - 10:00 AM", "washouts": [], "redrawTriggers": ["Afternoon draw"]}},
        {"id": "vitamin-d", "name": "Vitamin D", "units": [{"unit": "ng/mL", "default": true}],
         "preAnalytic": {"fastingRequired": false, "washouts": [], "redrawTriggers": []}},
        {"id": "tsh", "name": "TSH", "units": [{"unit": "mIU/L", "default": true}],
         "preAnalytic": {"fastingRequired": true, "timingWindow": "Morning",
                         "washouts": [{"item": "Biotin", "window": "72h", "effect": "Falsely lowers TSH"}], "redrawTriggers": []}},
        {"id": "cortisol", "name": "Cortisol", "units": [{"unit": "ug/dL", "default": true}],
         "preAnalytic": {"fastingRequired": true, "timingWindow": "7:00 - 9:00 AM", "washouts": [], "redrawTriggers": []}},
        {"id": "ast", "name": "AST", "units": [{"unit": "U/L", "default": true}]},
        {"id": "hs-crp", "name": "hs-CRP", "units": [{"unit": "mg/L", "default": true}]},
        {"id": "estradiol", "name": "Estradiol", "units": [{"unit": "pg/mL", "default": true}],
         "specimens": [{"matrix": "Serum", "preferredAssay": "Ultrasensitive LC-MS/MS", "targetPopulation": "Adult males",
                        "assayPitfall": "Standard female immunoassays lack precision at low male levels."}]},
        {"id": "urine-specific-gravity", "name": "Urine specific gravity", "units": [{"unit": "ratio", "default": true}]},
        {"id": "urine-squamous-cells", "name": "Urine squamous cells", "units": [{"unit": "cells/HPF", "default": true}]},
        {"id": "urine-protein", "name": "Urine protein", "units": []}
      ],
      "globalProtocols": {
        "fastingExemptMarkers": ["vitamin-d", "hs-crp"],
        "recommendedDrawWindow": "7:00 AM to 10:00 AM",
        "checklist": {"nightBefore": [], "morningOf": [], "postDraw": [], "loggingProtocol": []},
        "emergencySymptoms": []
      }
    }
    """#
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws {
        catalogue = try LabCatalogue(data: Data(json.utf8))
    }

    private func makeResult(_ id: String, _ val: Double, _ unit: String = "", text: String? = nil, assay: String? = nil) -> LabResult {
        LabResult(id: 1, drawID: 1, date: date("2026-11-01"), markerID: id, value: val, textValue: text,
                  assay: assay, unit: unit, defaultValue: val, defaultUnit: unit)
    }

    func testLateAfternoonUnfastedTestosteroneFiresCircadianAndFastingWarnings() {
        let draw = LabDrawDraft(date: date("2026-11-01"), time: "15:45", fastedHours: 3)
        let res = makeResult("total-testosterone", 285, "ng/dL")

        let warnings = LabValidityGate.evaluate(result: res, marker: catalogue.marker("total-testosterone")!,
                                                draw: draw, catalogue: catalogue, sex: .male)

        XCTAssertTrue(warnings.contains { $0.kind == .circadianTiming && $0.recommendsRedraw })
        XCTAssertTrue(warnings.contains { $0.kind == .fasting })
    }

    func testFastingExemptMarkersSkipFastingWarning() {
        let draw = LabDrawDraft(date: date("2026-11-01"), time: "08:30", fastedHours: 1)
        let res = makeResult("vitamin-d", 58, "ng/mL")

        let warnings = LabValidityGate.evaluate(result: res, marker: catalogue.marker("vitamin-d")!,
                                                draw: draw, catalogue: catalogue, sex: .male)

        XCTAssertTrue(warnings.isEmpty)
    }

    func testBiotinStoppedFalseFlagsImmunoassayTargetsButSkipsLCMSMS() {
        let draw = LabDrawDraft(date: date("2026-11-01"), time: "08:15", fastedHours: 11, biotinStopped: false)
        let tsh = makeResult("tsh", 0.2, "mIU/L")
        let cortLCMS = makeResult("cortisol", 14, "ug/dL", assay: "lc-ms-ms")

        let tshWarnings = LabValidityGate.evaluate(result: tsh, marker: catalogue.marker("tsh")!, draw: draw, catalogue: catalogue, sex: .male)
        let cortWarnings = LabValidityGate.evaluate(result: cortLCMS, marker: catalogue.marker("cortisol")!, draw: draw, catalogue: catalogue, sex: .male)

        XCTAssertTrue(tshWarnings.contains { $0.kind == .biotinInterference })
        XCTAssertFalse(cortWarnings.contains { $0.kind == .biotinInterference })
    }

    func testTrainingIllnessAndMaleEstradiolImmunoassayWarnings() {
        let draw = LabDrawDraft(date: date("2026-11-01"), time: "08:00", fastedHours: 11, trainedHard72h: true, illRecently: true)
        let ast = makeResult("ast", 52, "U/L")
        let crp = makeResult("hs-crp", 3.4, "mg/L")
        let e2 = makeResult("estradiol", 42, "pg/mL", assay: "immunoassay")

        let astW = LabValidityGate.evaluate(result: ast, marker: catalogue.marker("ast")!, draw: draw, catalogue: catalogue, sex: .male)
        let crpW = LabValidityGate.evaluate(result: crp, marker: catalogue.marker("hs-crp")!, draw: draw, catalogue: catalogue, sex: .male)
        let e2W = LabValidityGate.evaluate(result: e2, marker: catalogue.marker("estradiol")!, draw: draw, catalogue: catalogue, sex: .male)

        XCTAssertEqual(astW.map(\.kind), [.trainingWashout])
        XCTAssertEqual(Set(crpW.map(\.kind)), [.trainingWashout, .illnessOrVaccine])
        XCTAssertTrue(e2W.contains { $0.kind == .assayPitfall })
    }

    func testUrinalysisDilutionConcentrationAndSquamousContaminationGates() {
        let draw = LabDrawDraft(date: date("2026-11-01"))
        let protNeg = makeResult("urine-protein", 0, text: "Negative")
        let diluteSG = makeResult("urine-specific-gravity", 1.003, "ratio")

        let diluteW = LabValidityGate.evaluate(result: protNeg, marker: catalogue.marker("urine-protein")!,
                                               draw: draw, sameDrawResults: [protNeg, diluteSG], catalogue: catalogue, sex: .male)
        XCTAssertEqual(diluteW.map(\.kind), [.urineDilutionMasking])

        let protTrace = makeResult("urine-protein", 0, text: "Trace")
        let concSG = makeResult("urine-specific-gravity", 1.034, "ratio")
        let squamous = makeResult("urine-squamous-cells", 12, "cells/HPF")

        let concW = LabValidityGate.evaluate(result: protTrace, marker: catalogue.marker("urine-protein")!,
                                             draw: draw, sameDrawResults: [protTrace, concSG, squamous], catalogue: catalogue, sex: .male)
        XCTAssertEqual(Set(concW.map(\.kind)), [.urineConcentrationArtifact, .urineContamination])
    }
}
