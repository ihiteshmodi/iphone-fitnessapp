import XCTest
@testable import FitnessCore

final class LabSettingsTests: XCTestCase {
    func testDefaultsAreMaleNoBirthDateAndDrugNotesHidden() throws {
        let settings = LabSettings(try Database.inMemory())

        let loaded = try settings.load()

        XCTAssertEqual(loaded.sex, .male)
        XCTAssertFalse(loaded.isSexConfirmed)
        XCTAssertNil(loaded.birthDate)
        XCTAssertFalse(loaded.showDrugNotes)
    }

    func testChangesAreKept() throws {
        let db = try Database.inMemory()
        let settings = LabSettings(db)

        try settings.setBirthDate(date("1990-01-15"))
        try settings.setShowDrugNotes(true)
        try settings.setSex(.female)
        try settings.setReproductiveStatus(.premenopausal)
        try settings.setEnduranceAthlete(true)

        let loaded = try LabSettings(db).load()
        XCTAssertEqual(loaded.birthDate, date("1990-01-15"))
        XCTAssertTrue(loaded.showDrugNotes)
        XCTAssertEqual(loaded.sex, .female)
        XCTAssertTrue(loaded.isSexConfirmed)
        XCTAssertEqual(loaded.reproductiveStatus, .premenopausal)
        XCTAssertTrue(loaded.isEnduranceAthlete)

        try settings.setSex(.male)
        XCTAssertNil(try LabSettings(db).load().reproductiveStatus)
    }

    func testStrictSexFilteringShowsOnlyMatchingSexAndAllAdultsEverywhere() throws {
        let json = #"""
        {
          "markers": [
            {"id": "estradiol", "name": "Estradiol", "units": [{"unit": "pg/mL", "default": true}],
             "bands": [
               {"label": "Male opt", "kind": "optimal", "low": 20, "high": 40, "unit": "pg/mL", "sex": "male"},
               {"label": "Female luteal", "kind": "optimal", "low": 50, "high": 250, "unit": "pg/mL", "sex": "female"},
               {"label": "Shared note", "kind": "watch", "low": 0, "high": 10, "unit": "pg/mL", "sex": "any"}
             ],
             "whatToDo": [
               {"text": "General sleep step"},
               {"text": "Track cycle day", "tag": "female"},
               {"text": "Check testicular exam", "tag": "male"},
               {"text": "TRT dosing note", "tag": "drug"}
             ]},
            {"id": "psa", "name": "PSA", "units": [{"unit": "ng/mL", "default": true}],
             "bands": [{"label": "Male 40s", "kind": "lab", "low": 0, "high": 2.5, "unit": "ng/mL", "sex": "male"}]},
            {"id": "amh", "name": "AMH", "units": [{"unit": "ng/mL", "default": true}],
             "bands": [{"label": "Ovarian reserve", "kind": "optimal", "low": 1.5, "high": 4.0, "unit": "ng/mL", "sex": "female"}]}
          ],
          "panels": [
            {"id": "core", "name": "Core", "markers": ["estradiol"], "when": "first"},
            {"id": "male-h", "name": "Male hormones", "markers": ["psa"], "when": "first", "tag": "male"},
            {"id": "female-h", "name": "Female hormones", "markers": ["amh"], "when": "first", "tag": "female"}
          ],
          "prep": [
            {"id": "fast", "text": "Fast 10-12h", "hoursBefore": 12},
            {"id": "cycle", "text": "Record cycle day", "hoursBefore": 0, "tag": "female"},
            {"id": "trt-hold", "text": "Draw before T injection", "hoursBefore": 0, "tag": "drug"}
          ]
        }
        """#
        let cat = try LabCatalogue(data: Data(json.utf8))
        let db = try Database.inMemory()
        let draws = LabDrawService(db, catalogue: cat)
        let e2 = try XCTUnwrap(cat.marker("estradiol"))

        XCTAssertEqual(cat.visibleMarkers(for: .male).map(\.id), ["estradiol", "psa"])
        XCTAssertEqual(e2.visibleBands(for: .male).map(\.label), ["Male opt", "Shared note"])
        XCTAssertEqual(e2.visibleText(e2.whatToDo, sex: .male, showDrugNotes: false).map(\.text),
                       ["General sleep step", "Check testicular exam"])
        let malePlanner = DrawPlanner(catalogue: cat, draws: draws, sex: .male, showDrugNotes: false)
        XCTAssertEqual(try malePlanner.order().map(\.panel.id), ["core", "male-h"])
        XCTAssertEqual(malePlanner.prepTimeline(drawDate: date("2026-12-10"), drawHour: 8, ordered: ["estradiol"]).map(\.step.id),
                       ["fast"])

        XCTAssertEqual(cat.visibleMarkers(for: .female).map(\.id), ["estradiol", "amh"])
        XCTAssertEqual(e2.visibleBands(for: .female).map(\.label), ["Female luteal", "Shared note"])
        XCTAssertEqual(e2.visibleText(e2.whatToDo, sex: .female, showDrugNotes: false).map(\.text),
                       ["General sleep step", "Track cycle day"])
        let femalePlanner = DrawPlanner(catalogue: cat, draws: draws, sex: .female, showDrugNotes: false)
        XCTAssertEqual(try femalePlanner.order().map(\.panel.id), ["core", "female-h"])
        XCTAssertEqual(femalePlanner.prepTimeline(drawDate: date("2026-12-10"), drawHour: 8, ordered: ["estradiol"]).map(\.step.id),
                       ["fast", "cycle"])
    }
}
