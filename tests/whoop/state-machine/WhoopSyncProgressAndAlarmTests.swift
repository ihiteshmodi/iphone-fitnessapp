import XCTest
@testable import FitnessCore

final class WhoopSyncProgressAndAlarmTests: XCTestCase {
    func testSyncProgressStateComputesClampedFractionAndFormattedStatusStrings() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!

        // 1. Checking backlog (isSyncing == true, syncedUpToTs == nil)
        let checking = WhoopSyncProgressState(
            isSyncing: true,
            windowStartTs: 1_795_700_000,
            windowEndTs: 1_795_710_000,
            syncedUpToTs: nil,
            frontierTs: 1_795_700_000,
            rangeNewestTs: 1_795_710_000,
            recordsSyncedThisSession: 0,
            burstPacketsReceived: 0,
            burstPacketsExpected: nil
        )
        XCTAssertEqual(checking.progress, 0.0, accuracy: 1e-6)
        XCTAssertEqual(checking.statusText(calendar: cal), "Checking strap flash backlog…")

        // 2. Mid-sync 74%
        let midSync = WhoopSyncProgressState(
            isSyncing: true,
            windowStartTs: 1_795_700_000,
            windowEndTs: 1_795_710_000,
            syncedUpToTs: 1_795_707_400,
            frontierTs: 1_795_705_000,
            rangeNewestTs: 1_795_710_000,
            recordsSyncedThisSession: 7400,
            burstPacketsReceived: 120,
            burstPacketsExpected: 200
        )
        XCTAssertEqual(midSync.progress, 0.74, accuracy: 1e-6)
        let midText = midSync.statusText(calendar: cal)
        XCTAssertTrue(midText.hasPrefix("Syncing · Up to "), "Got: \(midText)")
        XCTAssertTrue(midText.hasSuffix("(74%)"), "Got: \(midText)")

        // 3. Idle with pending hours on strap (`rangeNewest - frontier > 300`)
        let idlePending = WhoopSyncProgressState(
            isSyncing: false,
            windowStartTs: nil,
            windowEndTs: nil,
            syncedUpToTs: nil,
            frontierTs: 1_795_700_000,
            rangeNewestTs: 1_795_707_200, // 2h ahead
            recordsSyncedThisSession: 500,
            burstPacketsReceived: 0,
            burstPacketsExpected: nil
        )
        let idleText = idlePending.statusText(calendar: cal)
        XCTAssertTrue(idleText.hasPrefix("Synced up to "), "Got: \(idleText)")
        XCTAssertTrue(idleText.contains("2.0h pending on strap"), "Got: \(idleText)")
    }

    func testAlarmSupportsBothNormalExactAndSmartWakeModesPlusReadDisableBuzzAndRestart() throws {
        let exact = WhoopAlarmDaySchedule(weekday: 1, hour: 6, minute: 45, enabled: true, mode: .exact, smartWindowMinutes: 0)
        XCTAssertEqual(exact.mode, .exact)
        XCTAssertEqual(exact.smartWindowMinutes, 0)

        let smart = WhoopAlarmDaySchedule(weekday: 2, hour: 7, minute: 15, enabled: true, mode: .smart, smartWindowMinutes: 20)
        XCTAssertEqual(smart.mode, .smart)
        XCTAssertEqual(smart.smartWindowMinutes, 20)
        XCTAssertNotNil(try WhoopSilentAlarmCommands.buildSmartWakePollFrame(smartWindowMinutes: 20, profile: .gen5))

        // Gen5 GET_ALARM_TIME (0x43) uses [0x04, id=1] per Spec §2.4
        let getFrame = WhoopSilentAlarmCommands.buildGetAlarmFrame(seq: 5, slot: 1, profile: .gen5)
        let unwrapped = try XCTUnwrap(WhoopFraming.parseFrame(getFrame, profile: .gen5))
        XCTAssertTrue(unwrapped.valid)
        XCTAssertEqual(Array(unwrapped.inner.prefix(5)), [WhoopPacketType.command, 5, WhoopCmd.getAlarmTime, 0x04, 0x01])

        // Restart Band (0x1D) blocked without allowDangerous, allowed with explicit user confirmation
        XCTAssertThrowsError(try WhoopCommands.guardedCommand(seq: 1, opcode: WhoopCmd.rebootStrap, payload: [0x00], profile: .gen5, allowDangerous: false))
        let rebootFrame = try WhoopCommands.cmdRestartStrap(seq: 9, profile: .gen5, userConfirmed: true)
        let unwrappedReboot = try XCTUnwrap(WhoopFraming.parseFrame(rebootFrame, profile: .gen5))
        XCTAssertEqual(unwrappedReboot.inner[2], WhoopCmd.rebootStrap)
    }

    func testBatteryHistoryQueryAndWakeAutoDerivationPopulateMetricsAutomatically() throws {
        let store = try WhoopStore.inMemory()
        var batch = WhoopSyncBatch(capturedAtMs: 1_795_750_000_000)
        batch.batteryRows = [
            WhoopBatteryRow(ts: 1_795_700_000, batteryPct: 88.0, charging: false, wristOn: true, millivolts: 4050, chargeUnits: nil, source: "band_event"),
            WhoopBatteryRow(ts: 1_795_720_000, batteryPct: 84.5, charging: false, wristOn: true, millivolts: 4010, chargeUnits: nil, source: "band_event"),
            WhoopBatteryRow(ts: 1_795_740_000, batteryPct: 96.0, charging: true, wristOn: true, millivolts: 4180, chargeUnits: nil, source: "band_event"),
        ]
        try store.commitSyncBatch(batch)

        let history = try store.batteryHistory(limit: 10)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.first?.batteryPct, 88.0)
        XCTAssertEqual(history.last?.charging, true)
    }
}
