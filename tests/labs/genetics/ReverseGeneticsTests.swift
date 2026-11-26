import XCTest
@testable import FitnessCore

final class ReverseGeneticsTests: XCTestCase {
    private let catalogueJSON = #"""
    {
      "markers": [
        {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 150, "unit": "ng/mL"}]},
        {"id": "tsat", "name": "Transferrin Saturation", "units": [{"unit": "%", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 25, "high": 40, "unit": "%"}]},
        {"id": "hs-crp", "name": "hs-CRP", "units": [{"unit": "mg/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 1.0, "unit": "mg/L"}]},
        {"id": "b12", "name": "Vitamin B12", "units": [{"unit": "pg/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 500, "high": 1300, "unit": "pg/mL"}]},
        {"id": "mma", "name": "MMA", "units": [{"unit": "nmol/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 0.27, "unit": "nmol/mL"}]},
        {"id": "homocysteine", "name": "Homocysteine", "units": [{"unit": "µmol/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 8.0, "unit": "µmol/L"}]},
        {"id": "folate", "name": "Serum Folate", "units": [{"unit": "ng/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 10, "high": 25, "unit": "ng/mL"}]},
        {"id": "hematocrit", "name": "Hematocrit", "units": [{"unit": "%", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 42, "high": 49, "unit": "%"}]},
        {"id": "apob", "name": "ApoB", "units": [{"unit": "mg/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 40, "high": 80, "unit": "mg/dL"}]},
        {"id": "vitamin-d", "name": "25-OH Vitamin D", "units": [{"unit": "ng/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 40, "high": 60, "unit": "ng/mL"}]},
        {"id": "lpa", "name": "Lp(a)", "units": [{"unit": "nmol/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 75, "unit": "nmol/L"}]},
        {"id": "alt", "name": "ALT", "units": [{"unit": "U/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 25, "unit": "U/L"}]}
      ],
      "genes": [
        {"id": "mthfr", "name": "MTHFR", "source": "07.01.01", "bucket": "take", "actionCategory": "nutrient_swap",
         "genotypes": [{"genotype": "C677T TT", "riskLevel": "high_impact"}]},
        {"id": "hfe", "name": "HFE", "source": "07.01.06", "bucket": "take", "actionCategory": "nutrient_swap",
         "genotypes": [{"genotype": "C282Y Homozygous", "riskLevel": "high_impact"},
                       {"genotype": "Wild-type (No C282Y/H63D)", "riskLevel": "baseline"}]},
        {"id": "fut2", "name": "FUT2", "source": "07.02.01", "bucket": "read", "actionCategory": "marker_shift",
         "genotypes": [{"genotype": "rs601338 AA", "riskLevel": "moderate_modifier"}]},
        {"id": "hla-dq2-dq8", "name": "HLA-DQ2 / DQ8", "source": "07.02.02", "bucket": "read", "actionCategory": "marker_shift",
         "genotypes": [{"genotype": "HLA-DQ2.5 Positive", "riskLevel": "moderate_modifier"}]},
        {"id": "lct-mcm6", "name": "LCT / MCM6", "source": "07.02.03", "bucket": "read", "actionCategory": "marker_shift",
         "genotypes": [{"genotype": "CC (Lactase non-persistence)", "riskLevel": "moderate_modifier"}]},
        {"id": "apoe", "name": "APOE", "source": "07.03.01", "bucket": "priority", "actionCategory": "priority_shift",
         "genotypes": [{"genotype": "e3/e4", "riskLevel": "moderate_modifier"}]},
        {"id": "lpa-gene", "name": "LPA", "source": "07.04.01", "bucket": "nothing", "actionCategory": "change_nothing",
         "changeNothingMandate": true,
         "phenotypicVerifiers": [{"kind": "marker", "markerID": "lpa", "markerName": "Serum Lp(a) particle count", "role": "outranks_genotype", "rule": "Measure once"}],
         "genotypes": [{"genotype": "Tag SNP Carrier", "riskLevel": "informational_only"}]},
        {"id": "vdr", "name": "VDR", "source": "07.04.02", "bucket": "nothing", "actionCategory": "change_nothing",
         "changeNothingMandate": true,
         "phenotypicVerifiers": [{"kind": "marker", "markerID": "vitamin-d", "markerName": "25(OH)D", "role": "outranks_genotype", "rule": "Test 25(OH)D"}],
         "genotypes": [{"genotype": "FokI FF", "riskLevel": "informational_only"}]},
        {"id": "actn3-ace", "name": "ACTN3 / ACE", "source": "07.04.03", "bucket": "nothing", "actionCategory": "change_nothing",
         "changeNothingMandate": true, "genotypes": [{"genotype": "ACTN3 XX", "riskLevel": "informational_only"}]},
        {"id": "gstm1-gstt1", "name": "GSTM1 / GSTT1", "source": "07.04.04", "bucket": "nothing", "actionCategory": "change_nothing",
         "changeNothingMandate": true,
         "phenotypicVerifiers": [{"kind": "marker", "markerID": "alt", "markerName": "GGT / ALT / AST", "role": "outranks_genotype", "rule": "Liver enzymes"}],
         "genotypes": [{"genotype": "GSTM1 Null", "riskLevel": "informational_only"}]},
        {"id": "sod2", "name": "SOD2", "source": "07.04.05", "bucket": "nothing", "actionCategory": "change_nothing",
         "changeNothingMandate": true, "genotypes": [{"genotype": "Val/Val", "riskLevel": "informational_only"}]},
        {"id": "salt-sensitivity", "name": "Salt Sensitivity", "source": "07.04.06", "bucket": "nothing", "actionCategory": "change_nothing",
         "changeNothingMandate": true, "genotypes": [{"genotype": "AGT Variant", "riskLevel": "informational_only"}]},
        {"id": "f5-f2", "name": "Factor V Leiden / Prothrombin", "source": "07.05.01", "bucket": "doctor", "actionCategory": "hard_contraindication",
         "genotypes": [{"genotype": "Factor V Leiden Heterozygous", "riskLevel": "high_impact"}]},
        {"id": "g6pd", "name": "G6PD", "source": "07.05.02", "bucket": "doctor", "actionCategory": "hard_contraindication",
         "genotypes": [{"genotype": "Class II/III Deficiency", "riskLevel": "contraindicated"}]},
        {"id": "cyp2d6-cyp2c19", "name": "CYP2D6 / CYP2C19", "source": "07.05.03", "bucket": "doctor", "actionCategory": "hard_contraindication",
         "genotypes": [{"genotype": "CYP2D6 Poor Metabolizer", "riskLevel": "contraindicated"}]}
      ]
    }
    """#

    private var db: Database!
    private var catalogue: LabCatalogue!
    private var settings: LabSettings!
    private var draws: LabDrawService!
    private var genetics: GeneticsService!
    private let today = date("2026-11-26")

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(catalogueJSON.utf8))
        settings = LabSettings(db)
        draws = LabDrawService(db, catalogue: catalogue)
        genetics = GeneticsService(db, catalogue: catalogue)
    }

    func testReverseGeneticsDefaultsOnStaysSilentWhenCleanAndFiresHFEFUT2AndHLAGuardrails() throws {
        let initialPrefs = try settings.load()
        XCTAssertTrue(initialPrefs.reverseGeneticsEnabled, "Reverse genetics must default to ON")
        XCTAssertFalse(initialPrefs.oxidativeTherapyPlanned)
        XCTAssertFalse(initialPrefs.clottingRiskHistory)
        XCTAssertFalse(initialPrefs.persistentLactoseSymptoms)

        // Clean draw -> zero reverse triggers
        let cleanID = try draws.addDraw(LabDrawDraft(date: date("2026-10-01")))
        try draws.addResult(drawID: cleanID, markerID: "ferritin", value: 95, unit: "ng/mL")
        try draws.addResult(drawID: cleanID, markerID: "tsat", value: 32, unit: "%")
        try draws.addResult(drawID: cleanID, markerID: "b12", value: 650, unit: "pg/mL")
        try draws.addResult(drawID: cleanID, markerID: "mma", value: 0.18, unit: "nmol/mL")

        let cleanSnap = try draws.latestResultsSnapshot()
        let cleanRecs = GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: [],
            preferences: initialPrefs, latestResults: Array(cleanSnap.byMarker.values))
        XCTAssertTrue(cleanRecs.isEmpty, "Clean panel must stay 100% silent")

        // Trigger HFE (Ferritin 340 > 300, TSAT 48% > 45%, hs-CRP 0.7 clean) + FUT2 (B12 720 normal, MMA 0.36 high)
        let d2 = try draws.addDraw(LabDrawDraft(date: date("2026-11-01")))
        try draws.addResult(drawID: d2, markerID: "ferritin", value: 340, unit: "ng/mL")
        try draws.addResult(drawID: d2, markerID: "tsat", value: 48, unit: "%")
        try draws.addResult(drawID: d2, markerID: "hs-crp", value: 0.7, unit: "mg/L")
        try draws.addResult(drawID: d2, markerID: "b12", value: 720, unit: "pg/mL")
        try draws.addResult(drawID: d2, markerID: "mma", value: 0.36, unit: "nmol/mL")

        let snap2 = try draws.latestResultsSnapshot()
        let recs2 = GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: [],
            preferences: initialPrefs, latestResults: Array(snap2.byMarker.values))
        XCTAssertEqual(Set(recs2.map(\.geneID)), ["hfe", "fut2"])

        // Logging HFE immediately removes HFE while keeping FUT2
        try genetics.set("hfe", genotype: "Wild-type (No C282Y/H63D)", on: today)
        let afterLog = GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: try genetics.entries(),
            preferences: initialPrefs, latestResults: Array(snap2.byMarker.values))
        XCTAssertEqual(afterLog.map(\.geneID), ["fut2"])

        // Switching Reverse Genetics OFF silences everything
        try settings.setReverseGeneticsEnabled(false)
        let disabledRecs = GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: try genetics.entries(),
            preferences: try settings.load(), latestResults: Array(snap2.byMarker.values))
        XCTAssertTrue(disabledRecs.isEmpty)
    }

    func testHLADQ2LCTG6PDFactorVAndCYP2D6TriggersEnforceClinicalGradeAndTimingGuardrails() throws {
        // Malabsorption draw for HLA-DQ2/DQ8 + TRT with Hematocrit 51.5% for F5/F2 + CPIC Rx + Oxidative + Lactose switches
        try settings.confirmContext(
            onTRTOrHRT: true, activeMedications: [.cpicPrescription], drinksAlcoholRegularly: false,
            reverseGeneticsEnabled: true, oxidativeTherapyPlanned: true,
            clottingRiskHistory: false, persistentLactoseSymptoms: true)

        let drawID = try draws.addDraw(LabDrawDraft(date: date("2026-11-10")))
        try draws.addResult(drawID: drawID, markerID: "ferritin", value: 18, unit: "ng/mL")
        try draws.addResult(drawID: drawID, markerID: "b12", value: 240, unit: "pg/mL")
        try draws.addResult(drawID: drawID, markerID: "folate", value: 3.1, unit: "ng/mL")
        try draws.addResult(drawID: drawID, markerID: "hematocrit", value: 51.5, unit: "%")

        let prefs = try settings.load()
        let snap = try draws.latestResultsSnapshot()
        let recs = GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: [],
            preferences: prefs, latestResults: Array(snap.byMarker.values))

        let ids = Set(recs.map(\.geneID))
        XCTAssertEqual(ids, ["hla-dq2-dq8", "lct-mcm6", "g6pd", "f5-f2", "cyp2d6-cyp2c19"])

        let hla = try XCTUnwrap(recs.first { $0.geneID == "hla-dq2-dq8" })
        XCTAssertTrue(hla.requiresClinicalGradeAssay)
        XCTAssertTrue(hla.guardrailWarning?.lowercased().contains("gluten") == true)

        let g6pd = try XCTUnwrap(recs.first { $0.geneID == "g6pd" })
        XCTAssertTrue(g6pd.requiresClinicalGradeAssay)
        XCTAssertTrue(g6pd.guardrailWarning?.contains("2–3 months") == true || g6pd.guardrailWarning?.contains("2-3 months") == true)

        let f5 = try XCTUnwrap(recs.first { $0.geneID == "f5-f2" })
        XCTAssertTrue(f5.requiresClinicalGradeAssay)
        XCTAssertTrue(f5.clinicalGradeWarning?.contains("23andMe") == true || f5.clinicalGradeWarning?.lowercased().contains("consumer") == true)

        let cyp = try XCTUnwrap(recs.first { $0.geneID == "cyp2d6-cyp2c19" })
        XCTAssertTrue(cyp.requiresClinicalGradeAssay)

        // Exported labs-review markdown contains # Conditional Genetic Tests Warranted
        let insights = try InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue)]).labs(on: today)
        let md = try LabsReviewService(db, catalogue: catalogue).markdown(on: today, insights: insights)
        XCTAssertTrue(md.contains("# Conditional Genetic Tests Warranted"), md)
        XCTAssertTrue(md.contains("HLA-DQ2 / DQ8"), md)
        XCTAssertTrue(md.contains("G6PD"), md)
    }

    func testZeroReverseTriggersEverFireFor0704ChangeNothingGenesAndTier1BadgesWarnDoNotBuy() throws {
        let drawID = try draws.addDraw(LabDrawDraft(date: date("2026-11-15")))
        try draws.addResult(drawID: drawID, markerID: "vitamin-d", value: 14, unit: "ng/mL")
        try draws.addResult(drawID: drawID, markerID: "lpa", value: 210, unit: "nmol/L")
        try draws.addResult(drawID: drawID, markerID: "alt", value: 88, unit: "U/L")

        let snap = try draws.latestResultsSnapshot()
        let recs = GeneticsModifierEvaluator.evaluateReverseTriggers(
            catalogue: catalogue, db: db, today: today, genotypes: [],
            preferences: try settings.load(), latestResults: Array(snap.byMarker.values))
        let forbidden: Set<String> = ["vdr", "lpa-gene", "actn3-ace", "gstm1-gstt1", "sod2", "salt-sensitivity"]
        XCTAssertTrue(recs.filter { forbidden.contains($0.geneID) }.isEmpty, "07.04.* genes must NEVER reverse-trigger")
        XCTAssertTrue(recs.isEmpty)

        let screenVM = try GeneticsPresenter.screen(catalogue: catalogue, db: db, today: today)
        let changeNothingSection = try XCTUnwrap(screenVM.sections.first { $0.id == "change_nothing" })
        for row in changeNothingSection.genes {
            XCTAssertEqual(row.triageBadge, "Skip / Do Not Buy — Test Phenotype Directly")
        }
        let vdrRow = try XCTUnwrap(changeNothingSection.genes.first { $0.id == "vdr" })
        XCTAssertTrue(vdrRow.directPhenotypeNote?.contains("25(OH)D") == true)

        let apoeDetail = GeneticsPresenter.detail(gene: try XCTUnwrap(catalogue.gene("apoe")), pickedGenotype: "e3/e4")
        XCTAssertTrue(apoeDetail.requiresClinicalGradeAssay, "APOE must flag Clinical-Grade vs DTC microarray guardrail")
    }

    func testRangeBarShiftsOptimalBoundsAndDisplaysStandardVsGeneticTargetForMTHFRAndAPOE4() throws {
        try genetics.set("mthfr", genotype: "C677T TT", on: today)
        try genetics.set("apoe", genotype: "e3/e4", on: today)
        let entries = try genetics.entries()
        let prefs = try settings.load()

        let hcyMarker = try XCTUnwrap(catalogue.marker("homocysteine"))
        let hcyBarUnlogged = try XCTUnwrap(LabRangeBarModel.build(
            marker: hcyMarker, sex: .male, reading: nil, latestResult: nil, genotypes: entries, preferences: prefs))
        XCTAssertTrue(hcyBarUnlogged.optimalLabel.contains("7"), hcyBarUnlogged.optimalLabel)
        XCTAssertTrue(hcyBarUnlogged.geneticShiftSummary?.contains("8") == true && hcyBarUnlogged.geneticShiftSummary?.contains("7") == true,
                      "\(String(describing: hcyBarUnlogged.geneticShiftSummary))")

        let apobMarker = try XCTUnwrap(catalogue.marker("apob"))
        let apobRes = LabResult(id: 1, drawID: 1, date: today, markerID: "apob", value: 72, unit: "mg/dL", defaultValue: 72, defaultUnit: "mg/dL")
        let apobReading = LabReader.read(result: apobRes, marker: apobMarker, preferences: prefs, genotypes: entries)
        let apobBar = try XCTUnwrap(LabRangeBarModel.build(
            marker: apobMarker, sex: .male, reading: apobReading, latestResult: apobRes, genotypes: entries, preferences: prefs))
        XCTAssertTrue(apobBar.optimalLabel.contains("60"), apobBar.optimalLabel)
        XCTAssertTrue(apobBar.geneticShiftSummary?.contains("80") == true && apobBar.geneticShiftSummary?.contains("60") == true)
    }
}
