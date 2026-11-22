import XCTest
@testable import FitnessCore

final class GeneticsTests: XCTestCase {
    private let json = #"""
    {"markers": [{"id": "mma", "name": "MMA", "units": [{"unit": "nmol/L", "default": true}]}],
     "genes": [
      {"id": "fut2", "name": "FUT2", "variant": "rs-fixture", "bucket": "read",
       "genotypes": [{"genotype": "AA", "meaning": "Fixture meaning", "actions": ["Fixture action"], "addsMarkers": ["mma"]},
                     {"genotype": "GG", "meaning": "Typical"}]},
      {"id": "g6pd", "name": "G6PD", "bucket": "doctor",
       "genotypes": [{"genotype": "Deficient", "meaning": "Fixture doctor meaning", "urgency": "sameDay"}]}]}
    """#
    private var db: Database!
    private var catalogue: LabCatalogue!
    private var genetics: GeneticsService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(json.utf8))
        genetics = GeneticsService(db, catalogue: catalogue)
    }

    func testPickingAGenotypeGivesItsMeaningAndAddsItsMarkersToTheOrder() throws {
        try genetics.set("fut2", genotype: "AA", on: date("2027-01-10"))

        let entry = try XCTUnwrap(try genetics.entries().first)
        XCTAssertEqual(entry.gene.id, "fut2")
        XCTAssertEqual(entry.row.meaning, "Fixture meaning")
        let order = try DrawPlanner(catalogue: catalogue, draws: LabDrawService(db, catalogue: catalogue), sex: .male, genetics: genetics).order()
        let fromGenes = try XCTUnwrap(order.first { $0.panel.id == "from-genetics" })
        XCTAssertEqual(fromGenes.tests.map(\.markerID), ["mma"])
        XCTAssertEqual(fromGenes.reason, "FUT2 AA")
    }

    func testOnlyGenotypesFromTheTableCanBePicked() {
        XCTAssertThrowsError(try genetics.set("fut2", genotype: "XY", on: date("2027-01-10"))) { error in
            XCTAssertEqual((error as? ValidationError)?.message, "XY is not in the vault's FUT2 table")
        }
    }

    func testADoctorGenotypeIsAFixItemWithItsUrgency() throws {
        try genetics.set("g6pd", genotype: "Deficient", on: date("2027-01-10"))

        let item = try XCTUnwrap(try InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue)])
            .labs(on: date("2027-01-11")).first { $0.ruleID == "lab-gene-g6pd" })
        XCTAssertEqual(item.title, "Same day: G6PD Deficient")
        XCTAssertEqual(item.severity, .fix)
    }

    func testClinicalContextProfileStartsUnconfirmedSavesOnceAndUpdatesLaterWhenTRTStarts() throws {
        let settings = LabSettings(db)
        XCTAssertFalse(try settings.load().isContextConfirmed)
        XCTAssertFalse(try settings.load().onTRTOrHRT)

        try settings.confirmContext(onTRTOrHRT: false, activeMedications: [.metforminOrAcidBlocker], drinksAlcoholRegularly: false)
        let initial = try settings.load()
        XCTAssertTrue(initial.isContextConfirmed)
        XCTAssertFalse(initial.onTRTOrHRT)
        XCTAssertEqual(initial.activeMedications, [.metforminOrAcidBlocker])

        try settings.setOnTRTOrHRT(true)
        let later = try settings.load()
        XCTAssertTrue(later.isContextConfirmed)
        XCTAssertTrue(later.onTRTOrHRT)
    }

    func testLegacyGeneIDsExternalTTGVerifierBaselineSuppressionAndNonLabFiltering() throws {
        let richJSON = #"""
        {
          "markers": [
            {"id": "tg-antibodies", "name": "Thyroglobulin Antibodies", "lessonID": "02.02.06", "units": [{"unit": "IU/mL", "default": true}]},
            {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}]},
            {"id": "lpa", "name": "Lp(a)", "units": [{"unit": "nmol/L", "default": true}]}
          ],
          "genes": [
            {"id": "hla-dq2-dq8", "name": "HLA-DQ2 / DQ8", "bucket": "read", "actionCategory": "marker_shift",
             "genotypes": [
               {"genotype": "HLA-DQ2 and HLA-DQ8 Negative", "riskLevel": "baseline"},
               {"genotype": "HLA-DQ2.5 Positive", "riskLevel": "mild_modifier"}
             ],
             "phenotypicVerifiers": [
               {"kind": "external_lab", "markerID": null, "patternID": null,
                "markerName": "tTG-IgA (Tissue Transglutaminase IgA) / Total IgA", "role": "mandatory_confirmer", "rule": "Stay on gluten"}
             ]},
            {"id": "actn3-ace", "name": "ACTN3 / ACE", "legacyIDs": ["actn3", "ace"], "bucket": "nothing",
             "actionCategory": "change_nothing", "changeNothingMandate": true,
             "genotypes": [{"genotype": "ACTN3 XX", "riskLevel": "baseline"}],
             "phenotypicVerifiers": [
               {"kind": "non_lab", "markerID": null, "patternID": null,
                "markerName": "Actual Gym Performance Testing", "role": "outranks_genotype", "rule": "Log lifts"}
             ]},
            {"id": "lpa-gene", "name": "LPA", "bucket": "nothing", "actionCategory": "change_nothing", "changeNothingMandate": true,
             "genotypes": [{"genotype": "High KIV-2 Copy Number / Tag Non-carrier", "riskLevel": "baseline"}],
             "phenotypicVerifiers": [
               {"kind": "marker", "markerID": "lpa", "patternID": null, "markerName": "Lp(a)", "role": "outranks_genotype", "rule": "Measure once"}
             ]}
          ]
        }
        """#
        let cat = try LabCatalogue(data: Data(richJSON.utf8))
        let svc = GeneticsService(db, catalogue: cat)
        let drawSvc = LabDrawService(db, catalogue: cat)

        try svc.set("hla-dq2-dq8", genotype: "HLA-DQ2.5 Positive", on: date("2027-01-10"))
        try svc.set("actn3", genotype: "ACTN3 XX", on: date("2027-01-10"))
        try svc.set("lpa-gene", genotype: "High KIV-2 Copy Number / Tag Non-carrier", on: date("2027-01-10"))

        let order1 = try DrawPlanner(catalogue: cat, draws: drawSvc, sex: .male, genetics: svc).order()
        let fromGenes1 = try XCTUnwrap(order1.first { $0.panel.id == "from-genetics" })
        XCTAssertTrue(fromGenes1.tests.contains { $0.name.contains("tTG-IgA") && $0.markerID == nil })
        XCTAssertFalse(fromGenes1.tests.contains { $0.markerID == "tg-antibodies" })
        XCTAssertFalse(fromGenes1.tests.contains { $0.name.contains("Gym Performance") })
        XCTAssertTrue(fromGenes1.tests.contains { $0.markerID == "lpa" }, "untested Lp(a) is ordered once even on reassuring tag SNP")

        // Switch HLA to Negative and log one Lp(a) blood draw -> neither orders anymore
        try svc.set("hla-dq2-dq8", genotype: "HLA-DQ2 and HLA-DQ8 Negative", on: date("2027-01-12"))
        let drawID = try drawSvc.addDraw(LabDrawDraft(date: date("2027-01-12")))
        try drawSvc.addResult(drawID: drawID, markerID: "lpa", value: 22, unit: "nmol/L")

        let order2 = try DrawPlanner(catalogue: cat, draws: drawSvc, sex: .male, genetics: svc).order()
        XCTAssertNil(order2.first { $0.panel.id == "from-genetics" })
    }

    func testFUT2ShiftAPOE4TargetMTHFRSilentAndFactorVTRTCollision() throws {
        let modJSON = #"""
        {
          "markers": [
            {"id": "b12", "name": "Vitamin B12", "units": [{"unit": "pg/mL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 500, "high": 1500, "unit": "pg/mL"}]},
            {"id": "mma", "name": "MMA", "units": [{"unit": "nmol/mL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 0.27, "unit": "nmol/mL"}]},
            {"id": "apob", "name": "ApoB", "units": [{"unit": "mg/dL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 80, "unit": "mg/dL"}]},
            {"id": "homocysteine", "name": "Homocysteine", "units": [{"unit": "umol/L", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 8, "unit": "umol/L"}]},
            {"id": "hematocrit", "name": "Hematocrit", "units": [{"unit": "%", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 43, "high": 48, "unit": "%"}]}
          ],
          "genes": [
            {"id": "fut2", "name": "FUT2", "bucket": "read", "actionCategory": "marker_shift",
             "genotypes": [{"genotype": "rs601338 AA (Homozygous non-secretor)", "riskLevel": "moderate_modifier"}]},
            {"id": "apoe", "name": "APOE", "bucket": "priority", "actionCategory": "priority_shift",
             "genotypes": [{"genotype": "e3/e4", "riskLevel": "moderate_modifier"}]},
            {"id": "mthfr", "name": "MTHFR", "bucket": "take", "actionCategory": "nutrient_swap",
             "genotypes": [{"genotype": "C677T TT (Homozygous / Two Copies)", "riskLevel": "high_impact"}]},
            {"id": "f5-f2", "name": "Factor V Leiden / Prothrombin", "legacyIDs": ["f5"], "bucket": "doctor",
             "actionCategory": "hard_contraindication",
             "genotypes": [{"genotype": "Factor V Leiden Heterozygous (F5 rs6025)", "riskLevel": "high_impact"}]}
          ]
        }
        """#
        let cat = try LabCatalogue(data: Data(modJSON.utf8))
        let svc = GeneticsService(db, catalogue: cat)
        try svc.set("fut2", genotype: "rs601338 AA (Homozygous non-secretor)", on: date("2027-01-10"))
        try svc.set("apoe", genotype: "e3/e4", on: date("2027-01-10"))
        try svc.set("mthfr", genotype: "C677T TT (Homozygous / Two Copies)", on: date("2027-01-10"))
        try svc.set("f5", genotype: "Factor V Leiden Heterozygous (F5 rs6025)", on: date("2027-01-10"))

        let entries = try svc.entries()
        let prefsTRT = LabPreferences(sex: .male, isSexConfirmed: true, isContextConfirmed: true, onTRTOrHRT: true)
        let prefsNoTRT = LabPreferences(sex: .male, isSexConfirmed: true, isContextConfirmed: true, onTRTOrHRT: false)

        let b12Res = LabResult(id: 1, drawID: 1, date: date("2027-02-01"), markerID: "b12", value: 620, unit: "pg/mL", defaultValue: 620, defaultUnit: "pg/mL")
        let b12Read = LabReader.read(result: b12Res, marker: cat.marker("b12")!, preferences: prefsNoTRT, genotypes: entries)
        XCTAssertTrue(b12Read.geneticNotes.contains { $0.contains("FUT2") && $0.contains("MMA") })

        let apobRes = LabResult(id: 2, drawID: 1, date: date("2027-02-01"), markerID: "apob", value: 72, unit: "mg/dL", defaultValue: 72, defaultUnit: "mg/dL")
        let apobRead = LabReader.read(result: apobRes, marker: cat.marker("apob")!, preferences: prefsNoTRT, genotypes: entries)
        XCTAssertEqual(apobRead.status, .high)
        XCTAssertTrue(apobRead.geneticNotes.contains { $0.contains("60") })

        let hcySilent = LabResult(id: 3, drawID: 1, date: date("2027-02-01"), markerID: "homocysteine", value: 6.2, unit: "umol/L", defaultValue: 6.2, defaultUnit: "umol/L")
        let hcyRead = LabReader.read(result: hcySilent, marker: cat.marker("homocysteine")!, preferences: prefsNoTRT, genotypes: entries)
        XCTAssertEqual(hcyRead.status, .optimal)
        XCTAssertTrue(hcyRead.geneticNotes.contains { $0.lowercased().contains("silent") })

        let hctRes = LabResult(id: 4, drawID: 1, date: date("2027-02-01"), markerID: "hematocrit", value: 53.5, unit: "%", defaultValue: 53.5, defaultUnit: "%")
        XCTAssertTrue(LabReader.read(result: hctRes, marker: cat.marker("hematocrit")!, preferences: prefsNoTRT, genotypes: entries).doctorLines.isEmpty)
        let hctOnTRT = LabReader.read(result: hctRes, marker: cat.marker("hematocrit")!, preferences: prefsTRT, genotypes: entries)
        XCTAssertFalse(hctOnTRT.doctorLines.isEmpty)

        let mmaClean = LabResult(id: 5, drawID: 1, date: date("2027-02-01"), markerID: "mma", value: 0.18, unit: "nmol/mL", defaultValue: 0.18, defaultUnit: "nmol/mL")
        let epistatic = GeneticsModifierEvaluator.evaluateEpistaticGrid(
            results: [b12Res, apobRes, hcySilent, hctRes, mmaClean], genotypes: entries, preferences: prefsTRT)
        XCTAssertTrue(epistatic.contains { $0.geneID == "f5-f2" && $0.isUrgentSafetyStop })
        XCTAssertTrue(epistatic.contains { $0.geneID == "mthfr" })
    }
}
