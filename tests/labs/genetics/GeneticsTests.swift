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

    func testAllFiveActionCategoriesInLabInsightsWithDietAndContextCrossChecks() throws {
        let catJSON = #"""
        {
          "markers": [
            {"id": "homocysteine", "name": "Homocysteine", "units": [{"unit": "µmol/L", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 7.5, "unit": "µmol/L"}]},
            {"id": "apob", "name": "ApoB", "units": [{"unit": "mg/dL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 80, "unit": "mg/dL"}],
             "interventions": {"tier1Foundations": ["Walk daily"], "tier2Nutrition": ["Lower sat fat"], "tier3Supplements": [], "tier4Peptides": [], "whatNotToDo": []}},
            {"id": "b12", "name": "Vitamin B12", "units": [{"unit": "pg/mL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 500, "high": 1300, "unit": "pg/mL"}]},
            {"id": "mma", "name": "MMA", "units": [{"unit": "nmol/mL", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 0.27, "unit": "nmol/mL"}]},
            {"id": "hematocrit", "name": "Hematocrit", "units": [{"unit": "%", "default": true}],
             "bands": [{"label": "Optimal", "kind": "optimal", "low": 43, "high": 49, "unit": "%"}]}
          ],
          "genes": [
            {"id": "mthfr", "name": "MTHFR", "bucket": "take", "actionCategory": "nutrient_swap",
             "genotypes": [{"genotype": "C677T TT (Homozygous / Two Copies)", "riskLevel": "high_impact"}],
             "formSubstitutions": [{"replaceOrAvoid": "Folic acid", "useInstead": "L-5-MTHF (methylfolate) 400–800 mcg", "targetGenotypes": ["C677T TT"], "crossVolumeRef": null}]},
            {"id": "hfe", "name": "HFE", "bucket": "doctor", "actionCategory": "nutrient_swap",
             "genotypes": [{"genotype": "C282Y / H63D Compound Heterozygous", "riskLevel": "moderate_modifier"}],
             "formSubstitutions": [{"replaceOrAvoid": "Iron supplements and iron-containing multivitamins", "useInstead": "Iron-free formulas", "targetGenotypes": ["C282Y / H63D"], "crossVolumeRef": null}]},
            {"id": "fut2", "name": "FUT2", "bucket": "read", "actionCategory": "marker_shift",
             "genotypes": [{"genotype": "rs601338 AA (Homozygous non-secretor)", "riskLevel": "moderate_modifier"}]},
            {"id": "lct-mcm6", "name": "LCT / MCM6", "bucket": "take", "actionCategory": "marker_shift",
             "genotypes": [{"genotype": "CC (Adult-type hypolactasia / Lactase non-persistence)", "riskLevel": "moderate_modifier"}]},
            {"id": "apoe", "name": "APOE", "bucket": "priority", "actionCategory": "priority_shift",
             "genotypes": [{"genotype": "e3/e4", "riskLevel": "moderate_modifier"}],
             "hardContraindications": [{"triggerGenotype": "e3/e4 or e4/e4", "forbiddenItems": [], "mandatoryReferral": "Physician or Certified Genetic Counselor", "coachStopLine": "Live genetic counseling required"}]},
            {"id": "cyp1a2", "name": "CYP1A2", "bucket": "priority", "actionCategory": "priority_shift",
             "genotypes": [{"genotype": "CC (Homozygous slow metabolizer)", "riskLevel": "high_impact"}]},
            {"id": "vdr", "name": "VDR", "bucket": "ignore", "actionCategory": "change_nothing", "changeNothingMandate": true,
             "genotypes": [{"genotype": "FokI FF / BsmI BB / TaqI tt (Single or Combined SNPs)", "riskLevel": "informational_only"}]},
            {"id": "actn3-ace", "name": "ACTN3 & ACE", "bucket": "ignore", "actionCategory": "change_nothing", "changeNothingMandate": true,
             "genotypes": [{"genotype": "ACTN3 XX (rs1815739 TT, alpha-actinin-3 null) / ACE II", "riskLevel": "informational_only"}]},
            {"id": "gstm1-gstt1", "name": "GSTM1 & GSTT1", "bucket": "ignore", "actionCategory": "change_nothing", "changeNothingMandate": true,
             "genotypes": [{"genotype": "GSTM1 Null (homozygous deletion)", "riskLevel": "informational_only"}]},
            {"id": "g6pd", "name": "G6PD", "bucket": "doctor", "actionCategory": "hard_contraindication",
             "genotypes": [{"genotype": "Hemizygous Male or Homozygous Female Pathogenic Variant (Class II/III Deficiency)", "riskLevel": "contraindicated", "urgency": "sameDay", "meaning": "G6PD deficiency"}],
             "hardContraindications": [{"triggerGenotype": "Class II/III Deficiency", "forbiddenItems": ["High-dose IV Vitamin C", "Methylene blue", "Fava beans"], "mandatoryReferral": "Hematologist / Physician", "coachStopLine": "Immediate ED if dark urine or jaundice"}]},
            {"id": "f5-f2", "name": "Factor V Leiden / Prothrombin", "bucket": "doctor", "actionCategory": "hard_contraindication",
             "genotypes": [{"genotype": "Factor V Leiden Heterozygous (F5 rs6025)", "riskLevel": "high_impact", "urgency": "soon", "meaning": "Activated protein C resistance"}],
             "hardContraindications": [{"triggerGenotype": "Factor V Leiden Heterozygous", "forbiddenItems": ["Combined oral estrogen contraceptives", "Unsupervised TRT"], "mandatoryReferral": "Hematologist / Prescribing Physician", "coachStopLine": "Hematocrit > 52% on TRT requires immediate prescriber review"}]},
            {"id": "cyp2d6-cyp2c19", "name": "CYP2D6 & CYP2C19", "bucket": "doctor", "actionCategory": "hard_contraindication",
             "genotypes": [{"genotype": "CYP2D6 Ultrarapid Metabolizer (*1/*1xN, *2/*2xN)", "riskLevel": "contraindicated", "urgency": "soon", "meaning": "Ultrarapid CYP2D6 pharmacogene"}],
             "hardContraindications": [{"triggerGenotype": "CYP2D6 Ultrarapid", "forbiddenItems": ["Codeine", "Tramadol", "St. John's Wort"], "mandatoryReferral": "Prescribing Physician or Clinical Pharmacist", "coachStopLine": "Never alter prescription doses without prescriber"}]}
          ]
        }
        """#
        let fullCat = try LabCatalogue(data: Data(catJSON.utf8))
        let genes = GeneticsService(db, catalogue: fullCat)
        let settings = LabSettings(db)
        let foods = FoodLibrary(db)
        let plans = DietPlanService(db)
        let drawSvc = LabDrawService(db, catalogue: fullCat)
        let today = date("2027-03-10")

        try settings.setSex(.male)
        try settings.confirmContext(onTRTOrHRT: false, activeMedications: [], drinksAlcoholRegularly: false)

        // 1. Save genes across all 5 categories:
        // nutrient_swap: MTHFR + HFE; marker_shift: FUT2 + LCT; priority_shift: APOE + CYP1A2;
        // change_nothing: VDR + ACTN3 + GSTM1; hard_contraindication: G6PD + F5 + CYP2D6
        try genes.set("mthfr", genotype: "C677T TT (Homozygous / Two Copies)", on: date("2027-03-01"))
        try genes.set("hfe", genotype: "C282Y / H63D Compound Heterozygous", on: date("2027-03-01"))
        try genes.set("fut2", genotype: "rs601338 AA (Homozygous non-secretor)", on: date("2027-03-01"))
        try genes.set("lct-mcm6", genotype: "CC (Adult-type hypolactasia / Lactase non-persistence)", on: date("2027-03-01"))
        try genes.set("apoe", genotype: "e3/e4", on: date("2027-03-01"))
        try genes.set("cyp1a2", genotype: "CC (Homozygous slow metabolizer)", on: date("2027-03-01"))
        try genes.set("vdr", genotype: "FokI FF / BsmI BB / TaqI tt (Single or Combined SNPs)", on: date("2027-03-01"))
        try genes.set("actn3-ace", genotype: "ACTN3 XX (rs1815739 TT, alpha-actinin-3 null) / ACE II", on: date("2027-03-01"))
        try genes.set("gstm1-gstt1", genotype: "GSTM1 Null (homozygous deletion)", on: date("2027-03-01"))
        try genes.set("g6pd", genotype: "Hemizygous Male or Homozygous Female Pathogenic Variant (Class II/III Deficiency)", on: date("2027-03-01"))
        try genes.set("f5-f2", genotype: "Factor V Leiden Heterozygous (F5 rs6025)", on: date("2027-03-01"))
        try genes.set("cyp2d6-cyp2c19", genotype: "CYP2D6 Ultrarapid Metabolizer (*1/*1xN, *2/*2xN)", on: date("2027-03-01"))

        // Clean baseline draw (Homocysteine 6.1 optimal, ApoB 55 optimal, B12 + MMA present) -> change_nothing & clean swaps stay quiet!
        let d1 = try drawSvc.addDraw(LabDrawDraft(date: date("2027-03-02"), time: "08:00", fastedHours: 12))
        try drawSvc.addResult(drawID: d1, markerID: "homocysteine", value: 6.1, unit: "µmol/L")
        try drawSvc.addResult(drawID: d1, markerID: "apob", value: 55, unit: "mg/dL")
        try drawSvc.addResult(drawID: d1, markerID: "b12", value: 600, unit: "pg/mL")
        try drawSvc.addResult(drawID: d1, markerID: "mma", value: 0.19, unit: "nmol/mL")

        let insightSvc = InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: fullCat)])
        let cleanAlerts = try insightSvc.labs(on: today)

        // Change-nothing genes emit ZERO alerts when diet is clean
        XCTAssertFalse(cleanAlerts.contains { $0.ruleID.contains("vdr") || $0.ruleID.contains("actn3") || $0.ruleID.contains("gstm1") })
        // Clean MTHFR, LCT, CYP1A2 emit ZERO diet-collision alerts when no folic acid, lactose, or >200mg caffeine is logged
        XCTAssertFalse(cleanAlerts.contains { $0.ruleID == "lab-gene-swap-mthfr" })
        XCTAssertFalse(cleanAlerts.contains { $0.ruleID == "lab-gene-diet-lct-mcm6" })
        XCTAssertFalse(cleanAlerts.contains { $0.ruleID == "lab-gene-diet-cyp1a2" })
        // Mandatory hard-contraindication & APOE e4 clinical referrals DO appear even on clean diet
        XCTAssertTrue(cleanAlerts.contains { $0.ruleID == "lab-gene-contra-g6pd" && $0.severity == .fix })
        XCTAssertTrue(cleanAlerts.contains { $0.ruleID == "lab-gene-contra-apoe" && $0.severity == .fix })

        // 2. Now add colliding foods/supplements, ApoB 72, Hematocrit 53.5%, and switch TRT + SSRI context ON!
        let folicSupp = try foods.add(FoodDraft(name: "Synthetic Folic Acid 800mcg", kind: .supplement, unit: "cap", baseQuantity: 1, nutrients: [.folate: 800]))
        let ironSupp = try foods.add(FoodDraft(name: "Ferrous Sulfate Iron", kind: .supplement, unit: "tab", baseQuantity: 1, nutrients: [.iron: 28]))
        let nacSupp = try foods.add(FoodDraft(name: "NAC Glutathione Detox", kind: .supplement, unit: "cap", baseQuantity: 1))
        let sjwHerb = try foods.add(FoodDraft(name: "St John's Wort Extract", kind: .herb, unit: "cap", baseQuantity: 1))
        let wheyConc = try foods.add(FoodDraft(name: "Whey Concentrate Shake", kind: .food, unit: "scoop", baseQuantity: 1, protein: 24))
        let espresso = try foods.add(FoodDraft(name: "Double Espresso", kind: .liquid, unit: "cup", baseQuantity: 1, nutrients: [.caffeine: 160]))

        try plans.addItem(foodID: folicSupp, quantity: 1, meal: "Morning", from: date("2027-03-05"))
        try plans.addItem(foodID: ironSupp, quantity: 1, meal: "Morning", from: date("2027-03-05"))
        try plans.addItem(foodID: nacSupp, quantity: 1, meal: "Morning", from: date("2027-03-05"))
        try plans.addItem(foodID: sjwHerb, quantity: 1, meal: "Evening", from: date("2027-03-05"))
        try plans.addItem(foodID: wheyConc, quantity: 1, meal: "Post-Workout", from: date("2027-03-05"))
        try plans.addItem(foodID: espresso, quantity: 2, meal: "Afternoon", from: date("2027-03-05"))

        try settings.confirmContext(onTRTOrHRT: true, activeMedications: [.cpicPrescription], drinksAlcoholRegularly: false)

        let d2 = try drawSvc.addDraw(LabDrawDraft(date: date("2027-03-08"), time: "08:00", fastedHours: 12))
        try drawSvc.addResult(drawID: d2, markerID: "apob", value: 72, unit: "mg/dL")
        try drawSvc.addResult(drawID: d2, markerID: "hematocrit", value: 53.5, unit: "%")
        try drawSvc.addResult(drawID: d2, markerID: "b12", value: 650, unit: "pg/mL") // no MMA on newest draw -> FUT2 reminder

        let activeAlerts = try insightSvc.labs(on: today)

        // Nutrient swaps fire on real diet collisions
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-swap-mthfr" && $0.detail.contains("L-5-MTHF") })
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-swap-hfe" && $0.severity == .fix })
        // Change-nothing guardrail fires on NAC detox stack, while VDR & ACTN3 remain silent
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-guardrail-gstm1-gstt1" })
        XCTAssertFalse(activeAlerts.contains { $0.ruleID.contains("vdr") || $0.ruleID.contains("actn3") })
        // Marker shift & priority shift fire
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-shift-fut2" })
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-diet-lct-mcm6" })
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-diet-cyp1a2" })
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-band-apob" && $0.title == "ApoB high" })
        // Hard contraindications + TRT / Hematocrit / SSRI + St John's Wort fire as .fix
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-doctor-hematocrit" && $0.severity == .fix })
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-contra-f5-f2" && $0.detail.contains("TRT") })
        XCTAssertTrue(activeAlerts.contains { $0.ruleID == "lab-gene-contra-cyp2d6-cyp2c19" && $0.detail.contains("St. John") })
    }
}

