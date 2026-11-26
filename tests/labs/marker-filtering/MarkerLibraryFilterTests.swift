import XCTest
@testable import FitnessCore

final class MarkerLibraryFilterTests: XCTestCase {
    private let json = #"""
    {
      "markers": [
        {"id": "start-guide", "name": "Start Here Guide", "chapter": "Start Here", "units": []},
        {"id": "ferritin", "name": "Ferritin", "chapter": "Iron Panel", "units": [{"unit": "ng/mL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 60, "high": 140, "unit": "ng/mL"}]},
        {"id": "glucose", "name": "Glucose", "chapter": "Metabolic", "units": [{"unit": "mg/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 70, "high": 90, "unit": "mg/dL"}],
         "retest": [{"text": "6 months", "minMonths": 6, "maxMonths": 12, "after": "routine"}]},
        {"id": "apob", "name": "ApoB", "chapter": "Lipids", "units": [{"unit": "mg/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": null, "high": 80, "unit": "mg/dL"}]},
        {"id": "mpv", "name": "MPV", "chapter": "CBC", "units": [{"unit": "fL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 8.5, "high": 11.0, "unit": "fL"}]},
        {"id": "zinc", "name": "Zinc", "chapter": "Minerals", "units": [{"unit": "mcg/dL", "default": true}],
         "bands": [{"label": "Optimal", "kind": "optimal", "low": 80, "high": 120, "unit": "mcg/dL"}]}
      ],
      "panels": [
        {"id": "core-baseline", "name": "Core baseline", "markers": ["ferritin", "glucose", "apob"], "when": "first"}
      ]
    }
    """#

    private var db: Database!
    private var catalogue: LabCatalogue!
    private var draws: LabDrawService!

    override func setUpWithError() throws {
        db = try Database.inMemory()
        catalogue = try LabCatalogue(data: Data(json.utf8))
        draws = LabDrawService(db, catalogue: catalogue)

        let drawID = try draws.addDraw(LabDrawDraft(date: date("2026-01-10")))
        try draws.addResult(drawID: drawID, markerID: "ferritin", value: 40, unit: "ng/mL")
        try draws.addResult(drawID: drawID, markerID: "glucose", value: 82, unit: "mg/dL")
        try draws.addResult(drawID: drawID, markerID: "mpv", value: 12.1, unit: "fL")
    }

    private func ids(quick: MarkerQuickFilter = .all, custom: MarkerCustomFilter? = nil, search: String = "") throws -> [String] {
        let vm = try MarkerLibraryPresenter.build(
            catalogue: catalogue, draws: draws, preferences: LabPreferences(sex: .male),
            genotypes: [], today: date("2026-11-26"), search: search,
            quickFilter: quick, customFilter: custom)
        return vm.sections.flatMap { $0.rows.map(\.marker.id) }
    }

    func testQuickFiltersCoverCoreDoneNotDoneNonCoreAndReadingStatuses() throws {
        XCTAssertEqual(try ids(quick: .all), ["start-guide", "ferritin", "glucose", "apob", "mpv", "zinc"])
        XCTAssertEqual(try ids(quick: .core), ["ferritin", "glucose", "apob"])
        XCTAssertEqual(try ids(quick: .coreNotDone), ["apob"])
        XCTAssertEqual(try ids(quick: .coreDone), ["ferritin", "glucose"])
        XCTAssertEqual(try ids(quick: .nonCoreDone), ["mpv"])
        XCTAssertEqual(try ids(quick: .nonCoreNotDone), ["zinc"], "Overview articles are excluded from Not Done")
        XCTAssertEqual(try ids(quick: .optimal), ["glucose"])
        XCTAssertEqual(try ids(quick: .low), ["ferritin"])
        XCTAssertEqual(try ids(quick: .high), ["mpv"])
    }

    func testCustomFilterCombinesTierCompletionReadingRetestDueAndChapters() throws {
        let coreLow = MarkerCustomFilter(tier: .core, completion: .done, status: .low)
        XCTAssertEqual(try ids(custom: coreLow), ["ferritin"])
        XCTAssertEqual(coreLow.summaryText, "★ Core · Done · Low")

        let wrongChapter = MarkerCustomFilter(tier: .core, completion: .done, status: .low, chapters: ["Metabolic"])
        XCTAssertEqual(try ids(custom: wrongChapter), [])

        // Glucose tested 2026-01-10 has minMonths: 6 -> due by 2026-11-26
        let retestDueCore = MarkerCustomFilter(tier: .core, completion: .retestDue)
        XCTAssertEqual(try ids(custom: retestDueCore), ["glucose"])
    }
}
