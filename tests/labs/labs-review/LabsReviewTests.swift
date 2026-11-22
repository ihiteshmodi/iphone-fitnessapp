import XCTest
@testable import FitnessCore

final class LabsReviewTests: XCTestCase {
    private let json = #"""
    {"markers": [
     {"id": "ferritin", "name": "Ferritin", "chapter": "Iron", "units": [{"unit": "ng/mL", "default": true}],
      "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}]},
     {"id": "a", "name": "A", "chapter": "X", "units": [{"unit": "u", "default": true}]},
     {"id": "b", "name": "B", "chapter": "X", "units": [{"unit": "u", "default": true}]},
     {"id": "c", "name": "C", "chapter": "X", "computed": true, "units": [{"unit": "u", "default": true}],
      "formula": {"expr": "{a} - {b}", "inputs": {"a": "u", "b": "u"}}}
    ]}
    """#
    private var db: Database!
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(json.utf8))
    }

    private func export(insights: [Insight] = []) throws -> String {
        try LabsReviewService(db, catalogue: catalogue).markdown(on: date("2026-11-19"), insights: insights)
    }

    func testEachDrawListsItsResultsReadAgainstTheVault() throws {
        let draws = LabDrawService(db, catalogue: catalogue)
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-05-03"), fastedHours: 12))
        try draws.addResult(drawID: id, markerID: "ferritin", value: 40, unit: "ng/mL", labLow: 30, labHigh: 400)
        try draws.addResult(drawID: id, markerID: "a", value: 10, unit: "u")
        try draws.addResult(drawID: id, markerID: "b", value: 4, unit: "u")

        let text = try export()

        XCTAssertTrue(text.contains("## 3 May 2026"), text)
        XCTAssertTrue(text.contains("fasted 12 h"), text)
        XCTAssertTrue(text.contains("Ferritin: 40 ng/mL, low (lab range 30–400)"), text)
        XCTAssertTrue(text.contains("C: 6 u (calculated)"), text)
    }

    func testBiologicalAgeAndOpenItems() throws {
        try LabSettings(db).setBirthDate(date("1998-06-09"))
        let draws = LabDrawService(db, catalogue: PhenoAge.inputCatalogue)
        try draws.addResult(drawID: try draws.addDraw(LabDrawDraft(date: date("2026-05-03"))), markerID: "albumin", value: 4.5, unit: "g/dL")
        catalogue = PhenoAge.inputCatalogue
        let open = Insight(ruleID: "lab-band-ferritin", kind: .labs, severity: .improve, title: "Ferritin low", detail: "", why: "")

        let text = try export(insights: [open])

        XCTAssertTrue(text.contains("PhenoAge: missing"), text)
        XCTAssertTrue(text.contains("hs-crp"), text)
        XCTAssertTrue(text.contains("- Ferritin low"), text)
    }

    func testReviewExportIncludesValidityFlagsDiscordancesAndReflexCoTests() throws {
        let richJSON = #"""
        {"markers": [
          {"id": "ldl-c", "name": "LDL-C", "units": [{"unit": "mg/dL", "default": true}],
           "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 100, "unit": "mg/dL"}]},
          {"id": "apob", "name": "ApoB", "units": [{"unit": "mg/dL", "default": true}],
           "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 80, "unit": "mg/dL"}],
           "coTests": ["lpa"],
           "escalation": {"urgentSameDay": [], "routineSoon": [], "specialists": ["Preventive Cardiology"]}},
          {"id": "lpa", "name": "Lp(a)", "units": [{"unit": "nmol/L", "default": true}]},
          {"id": "total-testosterone", "name": "Total Testosterone", "units": [{"unit": "ng/dL", "default": true}],
           "bands": [{"label": "Optimal", "kind": "optimal", "low": 600, "high": 900, "unit": "ng/dL"}]}
        ]}
        """#
        catalogue = try LabCatalogue(data: Data(richJSON.utf8))
        let draws = LabDrawService(db, catalogue: catalogue)
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-11-01"), time: "15:30", fastedHours: 3))
        try draws.addResult(drawID: id, markerID: "ldl-c", value: 90, unit: "mg/dL")
        try draws.addResult(drawID: id, markerID: "apob", value: 108, unit: "mg/dL")
        try draws.addResult(drawID: id, markerID: "total-testosterone", value: 310, unit: "ng/dL")

        let text = try export()
        XCTAssertTrue(text.contains("ApoB and LDL-C disagree"), text)
        XCTAssertTrue(text.contains("Lp(a)"), text)
        XCTAssertTrue(text.contains("Drawn outside morning window"), text)
    }

    func testReviewExportIncludesActiveGeneticModifiersExternalVerifiersAndGenotypeAdjustedReadings() throws {
        let genJSON = #"""
        {
          "markers": [
            {"id": "apob", "name": "ApoB", "units": [{"unit": "mg/dL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 80, "unit": "mg/dL"}]}
          ],
          "genes": [
            {"id": "apoe", "name": "APOE", "bucket": "priority", "actionCategory": "priority_shift",
             "genotypes": [{"genotype": "e3/e4", "riskLevel": "moderate_modifier"}],
             "hardContraindications": [{"triggerGenotype": "e3/e4", "forbiddenItems": [], "mandatoryReferral": "Physician or Certified Genetic Counselor", "coachStopLine": "Live disclosure"}]},
            {"id": "hla-dq2-dq8", "name": "HLA-DQ2 / HLA-DQ8", "bucket": "read", "actionCategory": "marker_shift",
             "genotypes": [{"genotype": "HLA-DQ2.5 and/or HLA-DQ8 Positive (Heterozygous or Homozygous)", "riskLevel": "moderate_modifier"}],
             "phenotypicVerifiers": [{"kind": "external_lab", "markerID": null, "patternID": null, "markerName": "tTG-IgA (Tissue Transglutaminase IgA) / Total IgA", "role": "mandatory_confirmer", "rule": "Order while eating gluten"}]},
            {"id": "vdr", "name": "VDR", "bucket": "ignore", "actionCategory": "change_nothing", "changeNothingMandate": true,
             "genotypes": [{"genotype": "FokI FF / BsmI BB / TaqI tt (Single or Combined SNPs)", "riskLevel": "informational_only"}]}
          ]
        }
        """#
        catalogue = try LabCatalogue(data: Data(genJSON.utf8))
        let settings = LabSettings(db)
        try settings.setSex(.male)
        try settings.confirmContext(onTRTOrHRT: true, activeMedications: [.cpicPrescription], drinksAlcoholRegularly: false)

        let genes = GeneticsService(db, catalogue: catalogue)
        try genes.set("apoe", genotype: "e3/e4", on: date("2026-11-01"))
        try genes.set("hla-dq2-dq8", genotype: "HLA-DQ2.5 and/or HLA-DQ8 Positive (Heterozygous or Homozygous)", on: date("2026-11-01"))
        try genes.set("vdr", genotype: "FokI FF / BsmI BB / TaqI tt (Single or Combined SNPs)", on: date("2026-11-01"))

        let draws = LabDrawService(db, catalogue: catalogue)
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-11-10"), time: "08:00", fastedHours: 12))
        try draws.addResult(drawID: id, markerID: "apob", value: 72, unit: "mg/dL")

        let insights = try InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue)]).labs(on: date("2026-11-19"))
        let text = try export(insights: insights)

        XCTAssertTrue(text.contains("TRT/HRT: yes"), text)
        XCTAssertTrue(text.contains("# Active genetic modifiers"), text)
        XCTAssertTrue(text.contains("APOE"), text)
        XCTAssertTrue(text.contains("Change-nothing mandate"), text)
        XCTAssertTrue(text.contains("tTG-IgA"), text)
        XCTAssertTrue(text.contains("ApoB: 72 mg/dL, high"), text)
    }
}

