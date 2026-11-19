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
}
