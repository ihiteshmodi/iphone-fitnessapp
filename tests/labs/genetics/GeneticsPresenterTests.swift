import XCTest
@testable import FitnessCore

final class GeneticsPresenterTests: XCTestCase {
    private let json = #"""
    {
      "markers": [
        {"id": "mma", "name": "MMA", "units": [{"unit": "nmol/mL", "default": true}]},
        {"id": "hematocrit", "name": "Hematocrit", "units": [{"unit": "%", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 43, "high": 49, "unit": "%"}]}
      ],
      "genes": [
        {"id": "vdr", "name": "VDR", "bucket": "ignore", "actionCategory": "change_nothing", "changeNothingMandate": true,
         "coreThesis": "Dose by serum 25(OH)D.",
         "genotypes": [{"genotype": "FokI FF", "riskLevel": "informational_only"}]},
        {"id": "mthfr", "name": "MTHFR", "bucket": "take", "actionCategory": "nutrient_swap",
         "genotypes": [{"genotype": "C677T TT", "riskLevel": "high_impact", "clinicalRule": "Check homocysteine first"}],
         "formSubstitutions": [{"replaceOrAvoid": "Folic acid", "useInstead": "L-5-MTHF", "targetGenotypes": ["C677T TT"], "crossVolumeRef": null}]},
        {"id": "hla-dq2-dq8", "name": "HLA-DQ2 / DQ8", "bucket": "read", "actionCategory": "marker_shift",
         "genotypes": [{"genotype": "HLA-DQ2.5 Positive", "riskLevel": "moderate_modifier"}],
         "phenotypicVerifiers": [{"kind": "external_lab", "markerID": null, "patternID": null,
                                  "markerName": "tTG-IgA / Total IgA", "role": "mandatory_confirmer", "rule": "Test while eating gluten"}]},
        {"id": "apoe", "name": "APOE", "bucket": "priority", "actionCategory": "priority_shift",
         "genotypes": [{"genotype": "e3/e4", "riskLevel": "moderate_modifier"}],
         "thresholdShifts": {"advanceScreeningYears": 10, "tightenedTargets": ["ApoB <= 60 mg/dL"], "behavioralStrictness": ["Limit sat fat"]}},
        {"id": "f5-f2", "name": "Factor V Leiden / Prothrombin", "bucket": "doctor", "actionCategory": "hard_contraindication",
         "genotypes": [{"genotype": "Factor V Leiden Heterozygous", "riskLevel": "high_impact", "urgency": "soon"}],
         "hardContraindications": [{"triggerGenotype": "Factor V Leiden", "forbiddenItems": ["Oral estrogen"],
                                    "mandatoryReferral": "Hematologist", "coachStopLine": "Immediate prescriber review if Hct > 52%"}],
         "whatNotToDo": ["Never start unsupervised TRT"],
         "caveats": {"dtcBlindSpots": ["Consumer chips only check 2 SNPs"], "ancestryDiscrepancies": [], "timingOrAssayTraps": []}}
      ]
    }
    """#

    func testPresenterGroupsFiveCategoriesFormatsContextSummaryAndBuildsGeneDetailSections() throws {
        let db = try Database.inMemory()
        let cat = try LabCatalogue(data: Data(json.utf8))
        let settings = LabSettings(db)
        let genes = GeneticsService(db, catalogue: cat)
        let draws = LabDrawService(db, catalogue: cat)
        let today = date("2027-03-10")

        let initialVM = try GeneticsPresenter.screen(catalogue: cat, db: db, today: today)
        XCTAssertTrue(initialVM.needsContextPrompt)
        XCTAssertEqual(initialVM.sections.map(\.id), [
            "hard_contraindication", "nutrient_swap", "marker_shift", "priority_shift", "change_nothing"
        ])
        XCTAssertEqual(initialVM.sections.last?.genes.first?.changeNothingBadge, "Bloodwork wins")

        try settings.confirmContext(onTRTOrHRT: true, activeMedications: [.cpicPrescription], drinksAlcoholRegularly: false)
        try genes.set("f5-f2", genotype: "Factor V Leiden Heterozygous", on: date("2027-03-01"))
        try genes.set("hla-dq2-dq8", genotype: "HLA-DQ2.5 Positive", on: date("2027-03-01"))
        let drawID = try draws.addDraw(LabDrawDraft(date: date("2027-03-05")))
        try draws.addResult(drawID: drawID, markerID: "hematocrit", value: 53.5, unit: "%")

        let updatedVM = try GeneticsPresenter.screen(catalogue: cat, db: db, today: today)
        XCTAssertFalse(updatedVM.needsContextPrompt)
        XCTAssertTrue(updatedVM.contextSummary.contains("TRT/HRT: On"))
        XCTAssertTrue(updatedVM.contextSummary.contains("CYP2D6 / CYP2C19"))
        XCTAssertFalse(updatedVM.activeFindings.isEmpty)

        let f5Detail = GeneticsPresenter.detail(gene: try XCTUnwrap(cat.gene("f5-f2")), pickedGenotype: "Factor V Leiden Heterozygous")
        XCTAssertEqual(f5Detail.riskBadge, "High impact")
        XCTAssertEqual(f5Detail.riskLevelTone, .amber)
        XCTAssertFalse(f5Detail.contraindications.isEmpty)
        XCTAssertFalse(f5Detail.whatNotToDo.isEmpty)
        XCTAssertFalse(f5Detail.caveatLines.isEmpty)

        let hlaDetail = GeneticsPresenter.detail(gene: try XCTUnwrap(cat.gene("hla-dq2-dq8")), pickedGenotype: "HLA-DQ2.5 Positive")
        XCTAssertEqual(hlaDetail.verifiers.first?.badge, "External lab test")
        XCTAssertNil(hlaDetail.verifiers.first?.markerID)
    }
}
