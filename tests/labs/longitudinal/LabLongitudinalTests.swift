import XCTest
@testable import FitnessCore

final class LabLongitudinalTests: XCTestCase {
    private let json = #"""
    {"markers": [
      {"id": "cortisol-dhea-ratio", "name": "Cortisol / DHEA-S ratio", "computed": true, "units": [{"unit": "ratio", "default": true}]},
      {"id": "psa", "name": "PSA", "units": [{"unit": "ng/mL", "default": true}]},
      {"id": "egfr", "name": "eGFR", "units": [{"unit": "mL/min/1.73 m²", "default": true}]},
      {"id": "hs-crp", "name": "hs-CRP", "units": [{"unit": "mg/L", "default": true}]},
      {"id": "ferritin", "name": "Ferritin", "units": [{"unit": "ng/mL", "default": true}]}
    ]}
    """#
    private var catalogue: LabCatalogue!

    override func setUpWithError() throws {
        catalogue = try LabCatalogue(data: Data(json.utf8))
    }

    private func res(_ drawID: Int, _ day: String, _ marker: String, _ val: Double, _ unit: String) -> LabResult {
        LabResult(id: drawID * 10, drawID: drawID, date: date(day), markerID: marker, value: val, unit: unit, defaultValue: val, defaultUnit: unit)
    }

    func testVelocityPersistenceAndCortisolDHEARisingFlagsWithinSameLab() throws {
        let draws: [Int: LabDrawDraft] = [
            1: LabDrawDraft(date: date("2026-04-01"), lab: "Quest"),
            2: LabDrawDraft(date: date("2026-10-01"), lab: "Quest"),
        ]

        let cdr = try XCTUnwrap(LabLongitudinalTracker.summarize(
            marker: catalogue.marker("cortisol-dhea-ratio")!,
            history: [res(2, "2026-10-01", "cortisol-dhea-ratio", 9.0, "ratio"), res(1, "2026-04-01", "cortisol-dhea-ratio", 4.0, "ratio")],
            drawsByID: draws))
        XCTAssertEqual(cdr.deltaFromBaseline ?? 0, 5.0, accuracy: 1e-6)
        XCTAssertEqual(cdr.percentFromBaseline ?? 0, 125.0, accuracy: 1e-4)
        XCTAssertTrue(cdr.driftFlags.contains { $0.kind == .cortisolDHEARising })

        let psa = try XCTUnwrap(LabLongitudinalTracker.summarize(
            marker: catalogue.marker("psa")!,
            history: [res(2, "2026-10-01", "psa", 1.4, "ng/mL"), res(1, "2026-04-01", "psa", 1.0, "ng/mL")],
            drawsByID: draws))
        XCTAssertGreaterThan(psa.annualizedVelocity ?? 0, 0.7)
        XCTAssertTrue(psa.driftFlags.contains { $0.kind == .psaVelocityHigh })

        let egfr = try XCTUnwrap(LabLongitudinalTracker.summarize(
            marker: catalogue.marker("egfr")!,
            history: [res(2, "2026-10-01", "egfr", 78, "mL/min/1.73 m²"), res(1, "2026-04-01", "egfr", 88, "mL/min/1.73 m²")],
            drawsByID: draws))
        XCTAssertTrue(egfr.driftFlags.contains { $0.kind == .egfrRapidDecline })

        let crp = try XCTUnwrap(LabLongitudinalTracker.summarize(
            marker: catalogue.marker("hs-crp")!,
            history: [res(2, "2026-10-01", "hs-crp", 2.4, "mg/L"), res(1, "2026-04-01", "hs-crp", 1.8, "mg/L")],
            drawsByID: draws))
        XCTAssertTrue(crp.driftFlags.contains { $0.kind == .sustainedElevation })
    }

    func testSwitchingLaboratoriesResetsBaselineAndSuppressesCrossLabVelocity() throws {
        let draws: [Int: LabDrawDraft] = [
            1: LabDrawDraft(date: date("2026-04-01"), lab: "Thyrocare"),
            2: LabDrawDraft(date: date("2026-10-01"), lab: "Quest"),
        ]
        let summary = try XCTUnwrap(LabLongitudinalTracker.summarize(
            marker: catalogue.marker("ferritin")!,
            history: [res(2, "2026-10-01", "ferritin", 95, "ng/mL"), res(1, "2026-04-01", "ferritin", 60, "ng/mL")],
            drawsByID: draws))

        XCTAssertTrue(summary.switchedLab)
        XCTAssertEqual(summary.activeLab, "Quest")
        XCTAssertNil(summary.previousValue)
        XCTAssertNil(summary.annualizedVelocity)
        XCTAssertTrue(summary.driftFlags.contains { $0.kind == .labBaselineReset })
    }
}
