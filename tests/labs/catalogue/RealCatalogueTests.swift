import XCTest
@testable import FitnessCore

/// Checks the real catalogue (output/labs-catalogue.json, the vault's content, git-ignored) when it is present.
final class RealCatalogueTests: XCTestCase {
    private func realCatalogue() throws -> LabCatalogue {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("output/labs-catalogue.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("output/labs-catalogue.json is not built") }
        return try LabCatalogue(data: Data(contentsOf: url))
    }

    func testTheRealCatalogueReadsAndEveryOrderedTestHasAName() throws {
        let catalogue = try realCatalogue()
        let draws = LabDrawService(try Database.inMemory(), catalogue: catalogue)

        XCTAssertGreaterThan(catalogue.markers.count, 100)
        XCTAssertGreaterThanOrEqual(catalogue.genes.count, 24)
        XCTAssertFalse(catalogue.geneticsGuide.isEmpty)
        let order = try DrawPlanner(catalogue: catalogue, draws: draws, sex: .male).order()
        XCTAssertFalse(order.isEmpty)
        XCTAssertTrue(order.flatMap(\.tests).allSatisfy { !$0.name.isEmpty })
        XCTAssertEqual(Set(catalogue.markers.map(\.id)).count, catalogue.markers.count, "marker ids are unique")
    }

    func testEveryMarkerHasOneDefaultUnitWhenItHasUnits() throws {
        for marker in try realCatalogue().markers where !marker.units.isEmpty {
            XCTAssertEqual(marker.units.filter(\.isDefault).count, 1, marker.id)
        }
    }

    func testEveryFormulaReadsOnlyItsInputsInUnitsTheyHave() throws {
        let catalogue = try realCatalogue()
        let formulas = catalogue.markers.filter { $0.formula != nil }
        XCTAssertGreaterThan(formulas.count, 15)
        for marker in formulas {
            let formula = try XCTUnwrap(marker.formula)
            let named = try NSRegularExpression(pattern: "\\{([^}]+)\\}")
                .matches(in: formula.expr, range: NSRange(formula.expr.startIndex..., in: formula.expr))
                .map { String(formula.expr[Range($0.range(at: 1), in: formula.expr)!]) }
            XCTAssertEqual(Set(named), Set(formula.inputs.keys), marker.id)
            for (id, unit) in formula.inputs {
                XCTAssertTrue(catalogue.marker(id)?.units.contains { $0.unit == unit } ?? false, "\(marker.id): \(id) in \(unit)")
            }
            XCTAssertNotNil(LabExpression.evaluate(formula.expr, values: formula.inputs.mapValues { _ in 3 }), marker.id)
        }
    }

    func testAffineUnitConversionRoundTripsToAndFromDefaultUnit() throws {
        let json = #"""
        {"markers": [{"id": "glycated", "name": "Glycated",
          "units": [{"unit": "%", "default": true}, {"unit": "mmol/mol", "toDefault": 0.09149131, "toDefaultOffset": 2.15004575}]}]}
        """#
        let marker = try XCTUnwrap(try LabCatalogue(data: Data(json.utf8)).marker("glycated"))

        let inDefault = try XCTUnwrap(marker.toDefault(31.0, unit: "mmol/mol"))
        XCTAssertEqual(inDefault, 4.986, accuracy: 0.005)
        let backToIFCC = try XCTUnwrap(marker.fromDefault(inDefault, to: "mmol/mol"))
        XCTAssertEqual(backToIFCC, 31.0, accuracy: 0.01)
    }

    func testCompiledClinicalRulesDecodeStrataPatternEnginesProtocolsAndOverviewFlags() throws {
        let catalogue = try realCatalogue()

        XCTAssertNotNil(catalogue.globalProtocols)
        XCTAssertFalse(catalogue.globalProtocols?.checklist.morningOf.isEmpty ?? true)
        XCTAssertFalse(catalogue.globalProtocols?.emergencySymptoms.isEmpty ?? true)

        let engines = catalogue.patterns.compactMap(\.engine)
        XCTAssertEqual(engines.count, 6)
        let thyroid = try XCTUnwrap(engines.first { $0.slug == "thyroid-conversion" })
        let ratio = try XCTUnwrap(thyroid.calculatedRatios.first)
        XCTAssertEqual(ratio.scaleFactor, 100.0)
        XCTAssertFalse(thyroid.interventions.whatNotToDo.isEmpty)

        let ferritin = try XCTUnwrap(catalogue.markerByLessonOrID("02.10.02"))
        XCTAssertEqual(ferritin.id, "ferritin")
        XCTAssertFalse(ferritin.strata.isEmpty)
        XCTAssertFalse(ferritin.coTests.isEmpty)
        XCTAssertFalse(ferritin.interventions?.whatNotToDo.isEmpty ?? true)
        XCTAssertFalse(ferritin.escalation?.specialists.isEmpty ?? true)

        let overviews = catalogue.markers.filter(\.isOverview)
        XCTAssertGreaterThanOrEqual(overviews.count, 5)
        XCTAssertTrue(overviews.allSatisfy { $0.bands.isEmpty })

        XCTAssertEqual(catalogue.panel("baseline-male")?.tag, "male")
        XCTAssertEqual(catalogue.panel("baseline-female")?.tag, "female")
        XCTAssertEqual(catalogue.panel("baseline-upgrades")?.when, "upgrade")
        XCTAssertFalse(catalogue.panel("baseline-male")?.drawNotes?.isEmpty ?? true)

        XCTAssertEqual(catalogue.genes.count, 24)
        let fut2 = try XCTUnwrap(catalogue.gene("fut2"))
        XCTAssertEqual(fut2.actionCategory, .markerShift)
        XCTAssertTrue(fut2.phenotypicVerifiers.contains { $0.markerID == "mma" && $0.role == "outranks_genotype" })

        let hla = try XCTUnwrap(catalogue.gene("hla-dq2-dq8"))
        let ttg = try XCTUnwrap(hla.phenotypicVerifiers.first { $0.markerName.contains("tTG-IgA") })
        XCTAssertEqual(ttg.kind, .externalLab)
        XCTAssertNil(ttg.markerID)

        let f5Alias = try XCTUnwrap(catalogue.gene("f5"))
        XCTAssertEqual(f5Alias.id, "f5-f2")
        XCTAssertEqual(f5Alias.actionCategory, .hardContraindication)

        let vdr = try XCTUnwrap(catalogue.gene("vdr"))
        XCTAssertTrue(vdr.changeNothingMandate)
    }

    func testRealCompiledGeneticsEndToEndAcrossAllFiveActionCategories() throws {
        let catalogue = try realCatalogue()
        let db = try Database.inMemory()
        let settings = LabSettings(db)
        try settings.setSex(.male)
        try settings.confirmContext(onTRTOrHRT: true, activeMedications: [.cpicPrescription], drinksAlcoholRegularly: false)

        let genes = GeneticsService(db, catalogue: catalogue)
        // Pick real compiled genotypes across all 5 categories + legacy alias
        try genes.set("mthfr", genotype: try XCTUnwrap(catalogue.gene("mthfr")?.genotypes?.last?.genotype), on: date("2027-03-01"))
        try genes.set("hfe", genotype: try XCTUnwrap(catalogue.gene("hfe")?.genotypes?.last?.genotype), on: date("2027-03-01"))
        try genes.set("fut2", genotype: try XCTUnwrap(catalogue.gene("fut2")?.genotypes?.last?.genotype), on: date("2027-03-01"))
        try genes.set("hla-dq2-dq8", genotype: try XCTUnwrap(catalogue.gene("hla-dq2-dq8")?.genotypes?.last?.genotype), on: date("2027-03-01"))
        try genes.set("apoe", genotype: "e3/e4", on: date("2027-03-01"))
        try genes.set("vdr", genotype: try XCTUnwrap(catalogue.gene("vdr")?.genotypes?.last?.genotype), on: date("2027-03-01"))
        try genes.set("g6pd", genotype: try XCTUnwrap(catalogue.gene("g6pd")?.genotypes?.last?.genotype), on: date("2027-03-01"))
        try genes.set("f5", genotype: try XCTUnwrap(catalogue.gene("f5")?.genotypes?.first { !$0.isBaseline }?.genotype), on: date("2027-03-01"))

        let draws = LabDrawService(db, catalogue: catalogue)
        let order = try DrawPlanner(catalogue: catalogue, draws: draws, sex: .male, genetics: genes).order()
        let genPanel = try XCTUnwrap(order.first { $0.panel.id == "from-genetics" })
        XCTAssertTrue(genPanel.tests.contains { $0.name.contains("tTG-IgA") && $0.markerID == nil })
        XCTAssertFalse(genPanel.tests.contains { $0.markerID == "tg-antibodies" })
        XCTAssertTrue(genPanel.tests.contains { $0.markerID == "mma" })

        let drawID = try draws.addDraw(LabDrawDraft(date: date("2027-03-05"), time: "08:00", fastedHours: 12))
        try draws.addResult(drawID: drawID, markerID: "apob", value: 72, unit: "mg/dL")
        try draws.addResult(drawID: drawID, markerID: "hematocrit", value: 53.5, unit: "%")
        try draws.addResult(drawID: drawID, markerID: "b12", value: 640, unit: "pg/mL")

        let insights = try InsightService(db, daily: [], setup: [], labs: [LabInsightsRule(catalogue: catalogue)]).labs(on: date("2027-03-10"))
        XCTAssertTrue(insights.contains { $0.ruleID == "lab-band-apob" && $0.title == "ApoB high" })
        XCTAssertTrue(insights.contains { $0.ruleID == "lab-doctor-hematocrit" && $0.severity == .fix })
        XCTAssertTrue(insights.contains { $0.ruleID == "lab-gene-contra-g6pd" && $0.severity == .fix })
        XCTAssertFalse(insights.contains { $0.ruleID.contains("vdr") })

        let md = try LabsReviewService(db, catalogue: catalogue).markdown(on: date("2027-03-10"), insights: insights)
        XCTAssertTrue(md.contains("# Active genetic modifiers"))
        XCTAssertTrue(md.contains("tTG-IgA"))
    }

    func testCholesterolAlbuminHormoneBUNAndMineralMarkersConvertFromMolarAndMetricUnits() throws {
        let catalogue = try realCatalogue()
        let cases: [(id: String, input: Double, unit: String, expected: Double, accuracy: Double)] = [
            ("total-cholesterol", 5.17, "mmol/L", 199.92, 0.1),
            ("hdl-c", 1.55, "mmol/L", 59.94, 0.1),
            ("non-hdl", 3.10, "mmol/L", 119.88, 0.1),
            ("albumin", 45.0, "g/L", 4.5, 0.01),
            ("free-testosterone", 100.0, "pmol/L", 28.842, 0.05),
            ("dhea-s", 6.0, "µmol/L", 221.1, 0.5),
            ("reverse-t3", 0.30, "nmol/L", 19.53, 0.1),
            ("bun", 5.0, "urea mmol/L", 14.005, 0.05),
            ("serum-magnesium", 0.90, "mmol/L", 2.187, 0.02),
            ("rbc-magnesium", 2.50, "mmol/L", 6.076, 0.02),
            ("zinc", 15.0, "µmol/L", 98.07, 0.2),
            ("selenium", 1.60, "µmol/L", 126.34, 0.2),
        ]
        for row in cases {
            let marker = try XCTUnwrap(catalogue.marker(row.id), "Missing marker \(row.id)")
            let converted = try XCTUnwrap(marker.toDefault(row.input, unit: row.unit), "\(row.id) missing \(row.unit) conversion")
            XCTAssertEqual(converted, row.expected, accuracy: row.accuracy, "\(row.id) in \(row.unit)")
        }

        let lpa = try XCTUnwrap(catalogue.marker("lpa"))
        XCTAssertNil(lpa.toDefault(28, unit: "mg/dL"), "Lp(a) keeps separate unit bands rather than a fixed multiplier")
        XCTAssertEqual(LabReader.read(value: 28, unit: "mg/dL", marker: lpa, sex: .male).status, .optimal)
        XCTAssertEqual(LabReader.read(value: 40, unit: "mg/dL", marker: lpa, sex: .male).status, .high)
    }
}
