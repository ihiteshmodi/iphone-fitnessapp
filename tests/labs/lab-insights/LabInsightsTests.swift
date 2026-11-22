import XCTest
@testable import FitnessCore

final class LabInsightsTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}],
      "doctor": [{"op": ">", "value": 1500, "unit": "ng/mL", "urgency": "sameDay", "text": "Fixture: get seen today", "source": "T9"}],
      "whatToDo": [{"text": "Low-side fixture action", "when": "low"}, {"text": "High-side fixture action", "when": "high"},
                   {"text": "Drug fixture action", "when": "low", "tag": "drug"}]},
     {"id": "tsat", "name": "Transferrin saturation", "units": [{"unit": "%", "default": true}]},
     {"id": "glucose", "name": "Glucose", "units": [{"unit": "mg/dL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 70, "high": 90, "unit": "mg/dL"}],
      "retest": [{"text": "Routine fixture", "minWeeks": 26, "maxWeeks": 52, "after": "routine"}]}
    ],
     "patterns": [{"id": "fixture-overload", "name": "Fixture overload", "computable": true, "needed": "all",
       "conditions": [{"marker": "ferritin", "op": ">", "value": 300, "unit": "ng/mL"}, {"marker": "tsat", "op": ">", "value": 45, "unit": "%"}],
       "meaning": "Fixture meaning", "whatToDo": ["Fixture step"], "source": "T14"}]}
    """#
    private var db: Database!
    private var catalogue: LabCatalogue!
    private var draws: LabDrawService!
    private let today = date("2027-03-02")

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(json.utf8))
        draws = LabDrawService(db, catalogue: catalogue)
    }

    private func service(showDrug: Bool = false) -> InsightService {
        InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue, sex: .male, showDrugNotes: showDrug)])
    }

    private func results(_ day: String, _ values: [(String, Double, String)]) throws {
        let id = try draws.addDraw(LabDrawDraft(date: date(day)))
        for (marker, value, unit) in values { try draws.addResult(drawID: id, markerID: marker, value: value, unit: unit) }
    }

    func testADoctorLineIsAFixWithTheVaultsUrgency() throws {
        try results("2027-03-01", [("ferritin", 1600, "ng/mL")])

        let item = try XCTUnwrap(try service().labs(on: today).first)
        XCTAssertEqual(item.title, "Same day: Ferritin")
        XCTAssertEqual(item.severity, .fix)
        XCTAssertEqual(item.kind, .labs)
        XCTAssertTrue(item.detail.contains("Fixture: get seen today"), item.detail)
    }

    func testOutOfTheOptimalBandShowsThatSidesActionsAndHidesDrugNotes() throws {
        try results("2027-03-01", [("ferritin", 40, "ng/mL")])

        let item = try XCTUnwrap(try service().labs(on: today).first { $0.title == "Ferritin low" })
        XCTAssertTrue(item.detail.contains("Low-side fixture action"))
        XCTAssertFalse(item.detail.contains("High-side fixture action"))
        XCTAssertFalse(item.detail.contains("Drug fixture action"))
        XCTAssertTrue(try service(showDrug: true).labs(on: today).first { $0.title == "Ferritin low" }!.detail.contains("Drug fixture action"))
    }

    func testAPatternFiresOnlyWhenItsConditionsHold() throws {
        try results("2027-03-01", [("ferritin", 350, "ng/mL"), ("tsat", 50, "%")])
        XCTAssertTrue(try service().labs(on: today).contains { $0.title == "Fixture overload" })

        try results("2027-03-02", [("ferritin", 350, "ng/mL"), ("tsat", 30, "%")])
        XCTAssertFalse(try service().labs(on: today).contains { $0.title == "Fixture overload" })
    }

    func testDismissingHidesItUntilANewerResult() throws {
        try results("2027-02-01", [("ferritin", 40, "ng/mL")])
        let labs = service()
        try labs.dismiss(try XCTUnwrap(try labs.labs(on: today).first { $0.title == "Ferritin low" }))
        XCTAssertFalse(try labs.labs(on: today).contains { $0.title == "Ferritin low" })

        try results("2027-03-01", [("ferritin", 45, "ng/mL")])
        XCTAssertTrue(try labs.labs(on: today).contains { $0.title == "Ferritin low" })
    }

    func testWithoutOverridesTheRuleReadsLabsSettings() throws {
        try results("2027-03-01", [("ferritin", 40, "ng/mL")])
        let fromSettings = InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue)])
        XCTAssertFalse(try fromSettings.labs(on: today).first { $0.title == "Ferritin low" }!.detail.contains("Drug fixture action"))

        try LabSettings(db).setShowDrugNotes(true)

        XCTAssertTrue(try fromSettings.labs(on: today).first { $0.title == "Ferritin low" }!.detail.contains("Drug fixture action"))
    }

    func testValuesKeepTheirDecimals() {
        XCTAssertEqual([123.4, 4.85, 1600].map(LabInsightsRule.number), ["123.4", "4.85", "1600"])
    }

    func testARetestThatIsDueIsATip() throws {
        try results("2026-09-01", [("glucose", 80, "mg/dL")])

        let item = try XCTUnwrap(try service().labs(on: today).first { $0.title == "Retest Glucose" })
        XCTAssertEqual(item.severity, .tip)
        XCTAssertFalse(try service().labs(on: date("2027-01-01")).contains { $0.title == "Retest Glucose" })
    }

    func testSymptomPairedPanicMultilineageCytopeniaSpecialistsSteppedTiersAndWhatNotToDo() throws {
        let safetyJSON = #"""
        {
          "markers": [
            {"id": "triglycerides", "name": "Triglycerides", "units": [{"unit": "mg/dL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 100, "unit": "mg/dL"}],
             "doctor": [{"op": ">=", "value": 500, "unit": "mg/dL", "urgency": "sameDay",
                         "text": "Acute pancreatitis risk.", "requires": "severe abdominal pain"}],
             "escalation": {"urgentSameDay": [], "routineSoon": [], "specialists": ["Endocrinology", "Cardiology"]},
             "interventions": {
               "tier1Foundations": ["Eliminate alcohol"],
               "tier2Nutrition": ["Cut refined sugars"],
               "tier3Supplements": [{"name": "Omega-3 EPA/DHA", "dose": "2-4 g/day", "target": "high", "notes": "Lowers VLDL"}],
               "tier4Peptides": ["Educational peptide X"],
               "whatNotToDo": ["Do not ignore abdominal pain radiating to the back"]
             }},
            {"id": "hemoglobin", "name": "Hemoglobin", "units": [{"unit": "g/dL", "default": true}],
             "bands": [{"label": "Lab", "kind": "lab", "low": 13.5, "high": 17.5, "unit": "g/dL"},
                       {"label": "Optimal", "kind": "optimal", "low": 15.5, "high": 17.0, "unit": "g/dL"}]},
            {"id": "wbc", "name": "WBC", "units": [{"unit": "x10^3/uL", "default": true}],
             "bands": [{"label": "Lab", "kind": "lab", "low": 4.0, "high": 11.0, "unit": "x10^3/uL"},
                       {"label": "Optimal", "kind": "optimal", "low": 4.5, "high": 7.5, "unit": "x10^3/uL"}]},
            {"id": "platelets", "name": "Platelets", "units": [{"unit": "x10^3/uL", "default": true}],
             "bands": [{"label": "Lab", "kind": "lab", "low": 150, "high": 400, "unit": "x10^3/uL"},
                       {"label": "Optimal", "kind": "optimal", "low": 175, "high": 300, "unit": "x10^3/uL"}]}
          ]
        }
        """#
        let cat = try LabCatalogue(data: Data(safetyJSON.utf8))
        let localDraws = LabDrawService(db, catalogue: cat)
        let id = try localDraws.addDraw(LabDrawDraft(date: date("2027-03-01"), time: "16:00", fastedHours: 2))
        try localDraws.addResult(drawID: id, markerID: "triglycerides", value: 560, unit: "mg/dL")
        try localDraws.addResult(drawID: id, markerID: "hemoglobin", value: 11.2, unit: "g/dL")
        try localDraws.addResult(drawID: id, markerID: "wbc", value: 3.1, unit: "x10^3/uL")
        try localDraws.addResult(drawID: id, markerID: "platelets", value: 110, unit: "x10^3/uL")

        let offItems = try InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: cat, sex: .male, showDrugNotes: false)]).labs(on: today)

        let symptomFix = try XCTUnwrap(offItems.first { $0.ruleID == "lab-doctor-symptom-triglycerides" })
        XCTAssertEqual(symptomFix.severity, .fix)
        XCTAssertTrue(symptomFix.detail.contains("severe abdominal pain"), symptomFix.detail)
        XCTAssertTrue(symptomFix.detail.contains("Endocrinology"), symptomFix.detail)

        let cytopenia = try XCTUnwrap(offItems.first { $0.ruleID == "lab-doctor-multilineage-cytopenia" })
        XCTAssertEqual(cytopenia.severity, .fix)
        XCTAssertTrue(cytopenia.detail.contains("Hematology"), cytopenia.detail)

        let tgBand = try XCTUnwrap(offItems.first { $0.ruleID == "lab-band-triglycerides" })
        XCTAssertTrue(tgBand.detail.contains("Eliminate alcohol"), tgBand.detail)
        XCTAssertTrue(tgBand.detail.contains("Omega-3 EPA/DHA"), tgBand.detail)
        XCTAssertTrue(tgBand.detail.contains("Do not ignore abdominal pain"), tgBand.detail)
        XCTAssertTrue(tgBand.detail.contains("fasted"), tgBand.detail)
        XCTAssertFalse(tgBand.detail.contains("Educational peptide X"), tgBand.detail)

        let onItems = try InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: cat, sex: .male, showDrugNotes: true)]).labs(on: today)
        let tgBandDrug = try XCTUnwrap(onItems.first { $0.ruleID == "lab-band-triglycerides" })
        XCTAssertTrue(tgBandDrug.detail.contains("Educational peptide X"), tgBandDrug.detail)
    }
}
