import XCTest
@testable import FitnessCore

final class LabPatternEvaluatorTests: XCTestCase {
    private let fixtureJSON = #"""
    {
      "markers": [
        {"id": "wbc", "name": "WBC", "units": [{"unit": "x10^3/uL", "default": true}]},
        {"id": "neutrophil-pct", "name": "Neutrophil %", "units": [{"unit": "%", "default": true}]},
        {"id": "lymphocyte-pct", "name": "Lymphocyte %", "units": [{"unit": "%", "default": true}]},
        {"id": "neutrophils", "name": "Neutrophils", "units": [{"unit": "x 10^9/L", "default": true}]},
        {"id": "lymphocytes", "name": "Lymphocytes", "units": [{"unit": "x 10^9/L", "default": true}]},
        {"id": "nlr", "name": "NLR", "computed": true, "units": [{"unit": "ratio", "default": true}],
         "formula": {"expr": "{neutrophils} / {lymphocytes}", "inputs": {"neutrophils": "x 10^9/L", "lymphocytes": "x 10^9/L"}}},
        {"id": "cortisol", "name": "Cortisol", "units": [{"unit": "ug/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 12, "high": 20, "unit": "ug/dL"}]},
        {"id": "dhea-s", "name": "DHEA-S", "units": [{"unit": "ug/dL", "default": true}]},
        {"id": "cortisol-dhea-ratio", "name": "Cortisol / DHEA-S ratio", "computed": true, "units": [{"unit": "ratio", "default": true}]},
        {"id": "tsh", "name": "TSH", "units": [{"unit": "mIU/L", "default": true}],
         "bands": [{"label": "Lab", "kind": "lab", "low": 0.45, "high": 4.5, "unit": "mIU/L"},
                   {"label": "Optimal", "kind": "optimal", "low": 1.0, "high": 2.0, "unit": "mIU/L"}]},
        {"id": "free-t4", "name": "Free T4", "units": [{"unit": "ng/dL", "default": true}],
         "bands": [{"label": "Lab", "kind": "lab", "low": 0.8, "high": 1.8, "unit": "ng/dL"},
                   {"label": "Optimal", "kind": "optimal", "low": 1.1, "high": 1.5, "unit": "ng/dL"}]},
        {"id": "free-t3", "name": "Free T3", "units": [{"unit": "pg/mL", "default": true}],
         "bands": [{"label": "Lab", "kind": "lab", "low": 2.3, "high": 4.2, "unit": "pg/mL"},
                   {"label": "Optimal", "kind": "optimal", "low": 3.2, "high": 4.2, "unit": "pg/mL"}]},
        {"id": "reverse-t3", "name": "Reverse T3", "units": [{"unit": "ng/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 10, "high": 14, "unit": "ng/dL"}]},
        {"id": "ft3-rt3", "name": "FT3:rT3", "computed": true, "units": [],
         "formula": {"expr": "{free-t3} * 100 / {reverse-t3}", "inputs": {"free-t3": "pg/mL", "reverse-t3": "ng/dL"}},
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 20, "high": null}]},
        {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 80, "high": 150, "unit": "ng/mL"}]},
        {"id": "ldl-c", "name": "LDL-C", "units": [{"unit": "mg/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 100, "unit": "mg/dL"}]},
        {"id": "apob", "name": "ApoB", "units": [{"unit": "mg/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 80, "unit": "mg/dL"}]},
        {"id": "creatinine", "name": "Creatinine", "units": [{"unit": "mg/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 0.8, "high": 1.1, "unit": "mg/dL"}]},
        {"id": "cystatin-c", "name": "Cystatin C", "units": [{"unit": "mg/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 0.6, "high": 0.85, "unit": "mg/L"}]},
        {"id": "total-testosterone", "name": "Total T", "units": [{"unit": "ng/dL", "default": true}],
         "bands": [{"label": "Lab", "kind": "lab", "low": 264, "high": 916, "unit": "ng/dL"},
                   {"label": "Optimal", "kind": "optimal", "low": 600, "high": 900, "unit": "ng/dL"}]},
        {"id": "free-testosterone", "name": "Free T", "units": [{"unit": "pg/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 12, "high": 20, "unit": "pg/mL"}]},
        {"id": "shbg", "name": "SHBG", "units": [{"unit": "nmol/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 25, "high": 50, "unit": "nmol/L"}]},
        {"id": "ast", "name": "AST", "units": [{"unit": "U/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 25, "unit": "U/L"}]},
        {"id": "alt", "name": "ALT", "units": [{"unit": "U/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 25, "unit": "U/L"}]},
        {"id": "ck", "name": "CK", "units": [{"unit": "U/L", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 50, "high": 150, "unit": "U/L"}]}
      ],
      "patterns": [
        {
          "id": "muscle-not-liver",
          "name": "Muscle, not liver",
          "computable": true,
          "needed": "all",
          "conditions": [
            {"marker": "ast", "op": "high", "sex": "any"},
            {"marker": "alt", "op": "normal", "sex": "any"},
            {"marker": "ck", "op": "high", "sex": "any"}
          ],
          "meaning": "Training leak, not liver injury."
        },
        {
          "id": "thyroid-conversion",
          "name": "Thyroid Conversion",
          "computable": false,
          "engine": {
            "patternID": "02.14.01",
            "slug": "thyroid-conversion",
            "section": "Pattern Analysis",
            "markersRequired": ["tsh", "free-t4", "free-t3", "reverse-t3"],
            "cofactorMarkers": ["ferritin"],
            "nonBloodInputs": ["Dietary Caloric / Macronutrient Intake Log"],
            "calculatedRatios": [{
              "ratioID": "free_t3_to_rt3",
              "markerID": "ft3-rt3",
              "name": "Free T3:rT3 ratio",
              "formula": "FT3 * 100 / rT3",
              "scaleFactor": 100,
              "thresholds": [{"band": "impaired", "condition": "< 0.15", "min": null, "max": 15, "meaning": "Impaired"}]
            }],
            "primarySignature": {
              "operator": "AND",
              "minMatches": null,
              "conditions": [
                {"target": "tsh", "rawTarget": "02.02.01", "state": "Normal (1.0 - 2.5 mIU/L)", "scaleFactor": 1},
                {"target": "free-t4", "rawTarget": "02.02.02", "state": "Normal (1.0 - 1.4 ng/dL)", "scaleFactor": 1},
                {"target": "free-t3", "rawTarget": "02.02.03", "state": "Low or low-normal (< 3.0 pg/mL)", "scaleFactor": 1},
                {"target": "reverse-t3", "rawTarget": "02.02.04", "state": "Elevated (> 15 ng/dL)", "scaleFactor": 1},
                {"target": "ft3-rt3", "rawTarget": "free_t3_to_rt3", "state": "Impaired (under 0.15)", "scaleFactor": 100}
              ]
            },
            "phenotypes": [
              {
                "name": "Nutrient-Deficient Conversion Impairment",
                "rules": [
                  {"target": "ft3-rt3", "condition": "< 0.15", "scaleFactor": 100},
                  {"target": "ferritin", "condition": "< 70 ng/mL", "scaleFactor": 1}
                ],
                "interpretation": "Low ferritin impairs deiodinase."
              }
            ],
            "progressionStaging": [{"stage": "Mild conversion impairment", "criteria": "1-2 drivers", "timeline": "90-180d"}],
            "differentialLookAlikes": [{"condition": "Biotin", "howToRuleOut": "Stop 72h"}],
            "upstreamCauses": [],
            "confoundingMedications": [],
            "interventions": {
              "tier1Foundations": ["Caloric adequacy"],
              "tier2Nutrition": ["Selenium foods"],
              "tier3Supplements": [],
              "tier4Peptides": ["Peptide note"],
              "whatNotToDo": ["Never crash diet"]
            },
            "escalation": {"urgentSameDay": [], "routineSoon": ["TSH > 10"], "specialists": ["Endocrinology"]}
          }
        }
      ]
    }
    """#
    private var db: Database!
    private var catalogue: LabCatalogue!
    private var draws: LabDrawService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(fixtureJSON.utf8))
        draws = LabDrawService(db, catalogue: catalogue)
    }

    func testAutoDerivesAbsoluteDifferentialForNLRAndCortisolDHEARatio() throws {
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-11-01")))
        try draws.addResult(drawID: id, markerID: "wbc", value: 6.0, unit: "x10^3/uL")
        try draws.addResult(drawID: id, markerID: "neutrophil-pct", value: 60, unit: "%")
        try draws.addResult(drawID: id, markerID: "lymphocyte-pct", value: 30, unit: "%")
        try draws.addResult(drawID: id, markerID: "cortisol", value: 18, unit: "ug/dL")
        try draws.addResult(drawID: id, markerID: "dhea-s", value: 200, unit: "ug/dL")

        let all = try draws.results(inDraw: id)
        XCTAssertEqual(all.first { $0.markerID == "nlr" }?.value ?? 0, 2.0, accuracy: 1e-6)
        XCTAssertEqual(all.first { $0.markerID == "cortisol-dhea-ratio" }?.value ?? 0, 9.0, accuracy: 1e-6)
    }

    func testThyroidConversionPatternMatchesPhenotypeAndAttachesCalorieCutContext() throws {
        try db.execute("INSERT INTO calorie_defaults (effective_from, calories, multiplier) VALUES ('2026-10-01', 2100, 0.8)")
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-11-01")))
        try draws.addResult(drawID: id, markerID: "tsh", value: 1.7, unit: "mIU/L")
        try draws.addResult(drawID: id, markerID: "free-t4", value: 1.2, unit: "ng/dL")
        try draws.addResult(drawID: id, markerID: "free-t3", value: 2.5, unit: "pg/mL")
        try draws.addResult(drawID: id, markerID: "reverse-t3", value: 25, unit: "ng/dL")
        try draws.addResult(drawID: id, markerID: "ferritin", value: 42, unit: "ng/mL")

        let ctx = try LabNonBloodContext.load(from: db, on: date("2026-11-01"))
        XCTAssertTrue(ctx.isInCalorieCut)

        let prefs = LabPreferences(sex: .male, isSexConfirmed: true, showDrugNotes: false)
        let matches = try LabPatternEvaluator.evaluate(drawID: id, draws: draws, catalogue: catalogue, preferences: prefs, context: ctx)

        let match = try XCTUnwrap(matches.first { $0.id == "thyroid-conversion" })
        XCTAssertEqual(match.matchedPhenotypes.map(\.name), ["Nutrient-Deficient Conversion Impairment"])
        XCTAssertTrue(match.contextNotes.contains { $0.lowercased().contains("cut") || $0.contains("2100") })
        XCTAssertTrue(match.interventions.tier4Peptides.isEmpty, "Tier 4 peptides gated when showDrugNotes is false")
    }

    func testDiscordanceRulesDetectApoBLDLCreatinineCystatinAndSHBGMasking() throws {
        let id = try draws.addDraw(LabDrawDraft(date: date("2026-11-01")))
        try draws.addResult(drawID: id, markerID: "ldl-c", value: 92, unit: "mg/dL")
        try draws.addResult(drawID: id, markerID: "apob", value: 105, unit: "mg/dL")
        try draws.addResult(drawID: id, markerID: "creatinine", value: 1.32, unit: "mg/dL")
        try draws.addResult(drawID: id, markerID: "cystatin-c", value: 0.72, unit: "mg/L")
        try draws.addResult(drawID: id, markerID: "total-testosterone", value: 550, unit: "ng/dL")
        try draws.addResult(drawID: id, markerID: "shbg", value: 62, unit: "nmol/L")
        try draws.addResult(drawID: id, markerID: "free-testosterone", value: 9.5, unit: "pg/mL")

        let all = try draws.results(inDraw: id)
        let alerts = LabPatternEvaluator.discordances(in: all, catalogue: catalogue, preferences: LabPreferences(sex: .male))
        XCTAssertEqual(alerts.count, 3)
    }

    func testCrossMarkerPatternsUseLatestPerMarkerAcrossSplitDrawsAndIgnoreSupersededValues() throws {
        let draw2025 = try draws.addDraw(LabDrawDraft(date: date("2025-01-10")))
        try draws.addResult(drawID: draw2025, markerID: "ck", value: 420, unit: "U/L")

        let drawMay = try draws.addDraw(LabDrawDraft(date: date("2026-05-03")))
        try draws.addResult(drawID: drawMay, markerID: "ck", value: 110, unit: "U/L")

        let drawNov = try draws.addDraw(LabDrawDraft(date: date("2026-11-01")))
        try draws.addResult(drawID: drawNov, markerID: "ast", value: 44, unit: "U/L")
        try draws.addResult(drawID: drawNov, markerID: "alt", value: 19, unit: "U/L")

        let insightsSvc = InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue, sex: .male)])
        XCTAssertFalse(try insightsSvc.labs(on: date("2026-11-02")).contains { $0.title == "Muscle, not liver" },
                       "Superseded 2025 CK=420 must be ignored when May 2026 CK=110 is newer")

        let splitCKDraw = try draws.addDraw(LabDrawDraft(date: date("2026-11-02")))
        try draws.addResult(drawID: splitCKDraw, markerID: "ck", value: 380, unit: "U/L")
        XCTAssertTrue(try insightsSvc.labs(on: date("2026-11-03")).contains { $0.title == "Muscle, not liver" },
                      "Latest CK (Draw 4) combines with latest AST & ALT (Draw 3)")
    }
}
