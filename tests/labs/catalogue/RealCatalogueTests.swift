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
}
