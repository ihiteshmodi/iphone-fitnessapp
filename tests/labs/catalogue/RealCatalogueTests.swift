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
}
