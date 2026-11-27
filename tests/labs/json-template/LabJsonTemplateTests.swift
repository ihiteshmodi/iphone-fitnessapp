import XCTest
@testable import FitnessCore

final class LabJsonTemplateTests: XCTestCase {
    func testExportTemplateAndIdempotentImportCoversPrepNumericLodPairedQualitativeAndGenetics() throws {
        let db = try Database.inMemory()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogueData = try Data(contentsOf: root.appendingPathComponent("output/labs-catalogue.json"))
        let catalogue = try LabCatalogue(data: catalogueData)
        let service = LabJsonTemplateService(db: db, catalogue: catalogue)

        let templateData = try service.exportTemplateJSON(includeExistingDraws: false)
        let templateObj = try XCTUnwrap(try JSONSerialization.jsonObject(with: templateData) as? [String: Any])
        XCTAssertNotNil(templateObj["instructions_for_ai"])
        let markerGuide = try XCTUnwrap(templateObj["marker_guide"] as? [[String: Any]])
        XCTAssertGreaterThan(markerGuide.count, 50)
        let geneGuide = try XCTUnwrap(templateObj["gene_guide"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(geneGuide.count, 20)

        let mthfr = try XCTUnwrap(catalogue.gene("mthfr"))
        let mthfrVariant = try XCTUnwrap(mthfr.genotypes?.first?.genotype)

        let filledPayload = """
        {
          "schema_version": 1,
          "draws": [
            {
              "draw_date": "2026-11-20",
              "draw_time": "08:15",
              "lab": "Thyrocare",
              "fasted_hours": 12.5,
              "trained_72h": false,
              "alcohol_5d": false,
              "biotin_stopped": true,
              "iron_stopped": true,
              "ill_recently": false,
              "poor_sleep": false,
              "acute_stress": false,
              "recent_vaccine_or_surgery": false,
              "meds_noted": "None",
              "note": "AI imported panel",
              "results": [
                {
                  "marker_id": "apob",
                  "value": 74.0,
                  "unit": "mg/dL",
                  "lab_low": 40.0,
                  "lab_high": 100.0
                },
                {
                  "marker_id": "hscrp",
                  "value": 0.2,
                  "value_operator": "<",
                  "unit": "mg/L"
                },
                {
                  "marker_id": "blood-pressure",
                  "value": 116.0,
                  "secondary_value": 74.0,
                  "unit": "mmHg"
                }
              ]
            }
          ],
          "genotypes": [
            {
              "gene_id": "mthfr",
              "genotype": "\(mthfrVariant)",
              "custom_genotype": "C677T homozygous",
              "entered_on": "2026-11-20",
              "lab": "MapMyGenome",
              "note": "Whole exome"
            }
          ],
          "custom_genes": [
            {
              "id": "comt",
              "name": "COMT",
              "variant": "rs4680",
              "genotype": "Met/Met",
              "entered_on": "2026-11-20",
              "lab": "MapMyGenome",
              "note": "Catecholamine clearance"
            }
          ]
        }
        """

        let firstSummary = try service.importFilledJSON(Data(filledPayload.utf8))
        XCTAssertEqual(firstSummary.drawsCreated, 1)
        XCTAssertEqual(firstSummary.resultsImported, 3)
        XCTAssertEqual(firstSummary.genotypesImported, 1)
        XCTAssertEqual(firstSummary.customGenesImported, 1)

        // Importing a second time with an updated ApoB value updates in place without duplicating draws or results!
        let updatedPayload = filledPayload.replacingOccurrences(of: "\"value\": 74.0", with: "\"value\": 71.5")
        let secondSummary = try service.importFilledJSON(Data(updatedPayload.utf8))
        XCTAssertEqual(secondSummary.drawsCreated, 0)
        XCTAssertEqual(secondSummary.drawsUpdated, 1)

        let draws = LabDrawService(db, catalogue: catalogue)
        let allDraws = try draws.draws()
        XCTAssertEqual(allDraws.count, 1)
        let results = try draws.results(inDraw: allDraws[0].id).filter { !$0.isCalculated }
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(try XCTUnwrap(results.first(where: { $0.markerID == "apob" })?.value), 71.5, accuracy: 1e-6)
        XCTAssertEqual(results.first(where: { $0.markerID == "hs-crp" })?.valueOperator, .belowLimit)
        XCTAssertEqual(results.first(where: { $0.markerID == "blood-pressure" })?.secondaryValue, 74.0)
    }
}
