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
        XCTAssertGreaterThan(catalogue.genes.count, 30)
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
}
