import XCTest
@testable import FitnessCore

final class WhoopBreathingAndCircadianTests: XCTestCase {
    func testCatalogContainsPhysiologicalSighFourSevenEightBoxResonanceAndFullNoopEdgeSet() {
        let all = WhoopBreathProtocolCatalog.all
        XCTAssertGreaterThanOrEqual(all.count, 22)
        XCTAssertNotNil(all.first { $0.id == "physiological_sigh" })
        XCTAssertNotNil(all.first { $0.id == "four_seven_eight" })
        XCTAssertNotNil(all.first { $0.id == "box_4_4_4_4" })
        XCTAssertNotNil(all.first { $0.id == "coherence_5_5" })

        let box = all.first { $0.id == "box_4_4_4_4" }!
        XCTAssertEqual(box.cycleDurationMs, 16_000)
        let snap0 = box.phaseAt(elapsedMs: 1_000)
        XCTAssertEqual(snap0.kind, .inhale)
        XCTAssertEqual(snap0.hapticLoops, 1)
        let snapHold = box.phaseAt(elapsedMs: 5_000)
        XCTAssertEqual(snapHold.kind, .holdIn)
        XCTAssertEqual(snapHold.hapticLoops, 0)
        let snapEx = box.phaseAt(elapsedMs: 9_000)
        XCTAssertEqual(snapEx.kind, .exhale)
        XCTAssertEqual(snapEx.hapticLoops, 2)
    }

    func testMcCratySpectralCardiacCoherenceScoresEntrainedSineRsaHigh() {
        // Simulate 90 seconds of beats oscillating cleanly at 0.10 Hz (6 breaths/min, Resonance)
        var rrMs: [Double] = []
        var rrTsMs: [Int64] = []
        var tMs: Double = 0
        while tMs < 90_000 {
            let phase = 2.0 * Double.pi * 0.10 * (tMs / 1000.0)
            let rr = 900.0 + 110.0 * sin(phase)
            tMs += rr
            rrMs.append(rr)
            rrTsMs.append(Int64(tMs.rounded()))
        }
        let res = WhoopCardiacCoherenceEngine.compute(rrMs: rrMs, rrTsMs: rrTsMs, pacedHz: 0.10)
        XCTAssertNotNil(res)
        XCTAssertGreaterThan(res?.score ?? 0, 55.0)
        XCTAssertEqual(res?.onPace, true)
    }

    func testHrDownPacerRampsDeltaAndThreeProcessAlertnessFindsAfternoonTrough() {
        XCTAssertEqual(WhoopHrDownPacer.targetBpm(currentHr: 84, elapsedSec: 0), 81.0, accuracy: 0.01)
        XCTAssertEqual(WhoopHrDownPacer.targetBpm(currentHr: 84, elapsedSec: 120), 76.0, accuracy: 0.01)

        let forecast = WhoopAlertnessForecastEngine.compute(wakeLocalHour: 7.0, sleepDurationHours: 7.5)
        XCTAssertNotNil(forecast)
        XCTAssertGreaterThan(forecast!.points.count, 30)
        // Shape is strictly unitless [0, 1]
        XCTAssertEqual(forecast!.points.map(\.value).min() ?? -1, 0.0, accuracy: 1e-6)
        XCTAssertEqual(forecast!.points.map(\.value).max() ?? -1, 1.0, accuracy: 1e-6)
        XCTAssertFalse(forecast!.troughLabel.isEmpty)
    }

    func testBaevskyStressWakeConsistencyNapComplianceAndTemperatureConversion() {
        // High variability sleep beats -> low Baevsky stress; tight sympathetic beats -> higher stress
        let calmBeats = (0..<60).map { i in 1000.0 + Double((i % 5) * 35) }
        let tenseBeats = (0..<60).map { i in 620.0 + Double(i % 2) * 4.0 }
        let calmStress = WhoopStressCurveEngine.baevskyStressScore(rrMs: calmBeats) ?? 100
        let tenseStress = WhoopStressCurveEngine.baevskyStressScore(rrMs: tenseBeats) ?? 0
        XCTAssertLessThan(calmStress, tenseStress)

        // Wake consistency: weekday 07:00 (420m) vs weekend 09:30 (570m) -> >= 120m jet lag flagged
        let wakes: [(isWeekend: Bool, wakeMinuteOfDay: Int)] = [
            (false, 420), (false, 425), (false, 415), (false, 420), (false, 422),
            (true, 565), (true, 575),
        ]
        let wakeEval = WhoopWakeAndNapComplianceEngine.evaluateWakeConsistency(wakes)
        XCTAssertTrue(wakeEval.weekendJetLagFlagged)
        XCTAssertGreaterThanOrEqual(wakeEval.weekendDriftMinutes, 140)

        // Nap compliance: 18 min at 13:00 on normal sleep -> compliant; 45 min at 16:30 -> non-compliant
        let goodPowerNap = WhoopWakeAndNapComplianceEngine.evaluateNap(durationMin: 18, startMinuteOfDay: 13 * 60, sleepDeprived: false)
        XCTAssertTrue(goodPowerNap.compliant)
        let badLateNap = WhoopWakeAndNapComplianceEngine.evaluateNap(durationMin: 45, startMinuteOfDay: 16 * 60 + 30, sleepDeprived: false)
        XCTAssertFalse(badLateNap.compliant)
        let recoveryNap = WhoopWakeAndNapComplianceEngine.evaluateNap(durationMin: 90, startMinuteOfDay: 11 * 60, sleepDeprived: true)
        XCTAssertTrue(recoveryNap.compliant)

        // Skin temperature unit formatting (°C and °F)
        XCTAssertEqual(TemperatureUnitPreference.celsius.format(celsius: 36.5), "36.5 °C")
        XCTAssertEqual(TemperatureUnitPreference.fahrenheit.format(celsius: 36.5), "97.7 °F")
    }
}
