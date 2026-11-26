import XCTest
@testable import FitnessCore

final class WhoopStateMachineTests: XCTestCase {
    func testSeqAllocatorKeepsSyncAndLiveRangesNonOverlapping() {
        var seq = WhoopSeqAllocator()
        XCTAssertEqual(seq.nextSync(), 5)
        XCTAssertEqual(seq.nextLive(), 0xA0)
        for _ in 0..<250 { _ = seq.nextSync() }
        XCTAssertEqual(seq.nextSync(), 5, "Sync wraps from 0xFF back to 5")
        for _ in 0..<95 { _ = seq.nextLive() }
        XCTAssertEqual(seq.nextLive(), 0xA0, "Live wraps from 0xFF back to 0xA0")
    }

    func testFrameRouteBurstStatsAndGen5PacketCountSlackGate() {
        // Metadata & historical 0x2F route to serialized queue; events/console/puffin 0x30/0x32/0x35..0x37 route immediateAndCount
        XCTAssertEqual(WhoopFrameRoutePolicy.route(packetType: WhoopPacketType.metadata, isDataRole: false, offloadActive: true), .serializedQueue)
        XCTAssertEqual(WhoopFrameRoutePolicy.route(packetType: WhoopPacketType.historicalData, isDataRole: true, offloadActive: true), .serializedQueue)
        XCTAssertEqual(WhoopFrameRoutePolicy.route(packetType: WhoopPacketType.event, isDataRole: false, offloadActive: true), .immediateAndCount)
        XCTAssertEqual(WhoopFrameRoutePolicy.route(packetType: WhoopPacketType.relativePuffinEvents, isDataRole: false, offloadActive: true), .immediateAndCount)
        XCTAssertEqual(WhoopFrameRoutePolicy.route(packetType: WhoopPacketType.event, isDataRole: false, offloadActive: false), .immediate)

        var stats = WhoopBurstStats()
        stats.beginBurst()
        stats.recordDataPacket()
        stats.recordDataPacket()
        stats.recordDataPacket()
        stats.recordInlineTrafficMember() // e.g. 0x30 event inside burst
        XCTAssertEqual(stats.totalTrafficPacketCount, 4)

        // Expected 5, actual 4, consecutiveFailedValidations = 0 -> shortfall!
        XCTAssertFalse(stats.passesGen5CountGate(expectedPacketCount: 5, droppedThisBurst: 0))
        stats.noteValidationFailure()
        stats.noteValidationFailure()
        XCTAssertFalse(stats.passesGen5CountGate(expectedPacketCount: 5, droppedThisBurst: 0))
        // After 3rd consecutive failure, slack = 2 -> 5 - 2 <= 4 passes!
        stats.noteValidationFailure()
        XCTAssertTrue(stats.passesGen5CountGate(expectedPacketCount: 5, droppedThisBurst: 0))
    }

    func testTrimAckPolicyBlocksEveryUnsafeConditionAndAllowsBelowFloorArchiveTrim() {
        XCTAssertEqual(
            WhoopTrimAckPolicy.evaluate(sessionCurrent: false, burstDiscarded: false, commitDurable: true),
            .blockedStaleSession)
        XCTAssertEqual(
            WhoopTrimAckPolicy.evaluate(sessionCurrent: true, burstDiscarded: true, commitDurable: true),
            .blockedDiscardedBurst)
        XCTAssertEqual(
            WhoopTrimAckPolicy.evaluate(sessionCurrent: true, burstDiscarded: false, commitDurable: false),
            .blockedCommitFailed)
        // Future-dropped records with 0 durable rows -> blockedNoDurableProgress
        XCTAssertEqual(
            WhoopTrimAckPolicy.evaluate(sessionCurrent: true, burstDiscarded: false, commitDurable: true,
                                        hadDurableRows: false, droppedThisBurst: 3, droppedBelowFloorThisBurst: 0, gateDropArchives: 3),
            .blockedNoDurableProgress)
        // Below-floor-only records all archived -> safe to trim (.send)
        XCTAssertEqual(
            WhoopTrimAckPolicy.evaluate(sessionCurrent: true, burstDiscarded: false, commitDurable: true,
                                        hadDurableRows: false, droppedThisBurst: 3, droppedBelowFloorThisBurst: 3, gateDropArchives: 3),
            .send)
        // Burst shortfall after durable commit -> blockedBurstShortfall (send 0x17 NACK)
        XCTAssertEqual(
            WhoopTrimAckPolicy.evaluate(sessionCurrent: true, burstDiscarded: false, commitDurable: true,
                                        hadDurableRows: true, shortfallRetry: true),
            .blockedBurstShortfall)
    }

    func testStandingConnectBondAckHelloSuppressionAndRadioFaultDetectors() {
        // ReconnectStep passive standing connect vs < 2s hot-loop 30s floor
        XCTAssertEqual(WhoopReconnectStep.decide(secondsSinceStandingConnect: nil), .standingConnect)
        XCTAssertEqual(WhoopReconnectStep.decide(secondsSinceStandingConnect: 4.5), .standingConnect)
        if case .standingConnectAfter(let delay) = WhoopReconnectStep.decide(secondsSinceStandingConnect: 0.5) {
            XCTAssertEqual(delay, 29.5, accuracy: 1e-6)
        } else {
            XCTFail("Expected hot-loop 30s floor")
        }

        // Gen4 & Gen5 Bond Ack proof
        XCTAssertEqual(Whoop4BondAck.classify(didBond: false, encryptedBond: false, samePeripheralAsBond: false), .firstBond)
        XCTAssertEqual(Whoop4BondAck.classify(didBond: true, encryptedBond: false, samePeripheralAsBond: true), .reprove)
        XCTAssertEqual(WhoopClientHelloOutcome.classify(
            isHelloChar: true, helloOutstanding: false, alreadyBonded: false,
            encryptedBond: false, samePeripheralAsBond: false, isWhoop5: true), .notAnAck)
        XCTAssertEqual(WhoopClientHelloOutcome.classify(
            isHelloChar: true, helloOutstanding: true, alreadyBonded: false,
            encryptedBond: false, samePeripheralAsBond: false, isWhoop5: true), .firstBond)

        // BondRefusalGiveUp: 5 auth refusals pause (with 30-min cooldown), 3 unanswered suppress hello
        var giveUp = WhoopBondRefusalGiveUp(giveUpThreshold: 5, cooldownSeconds: 1800)
        let t0 = Date(timeIntervalSince1970: 1_795_700_000)
        for _ in 0..<4 { XCTAssertFalse(giveUp.recordRefusal(authRefusal: true, now: t0)) }
        XCTAssertTrue(giveUp.recordRefusal(authRefusal: true, now: t0))
        XCTAssertTrue(giveUp.stillPaused(now: t0.addingTimeInterval(600)))
        XCTAssertFalse(giveUp.stillPaused(now: t0.addingTimeInterval(1801)), "30-min cooldown re-arms reconnect")

        var helloGiveUp = WhoopBondRefusalGiveUp(giveUpThreshold: 5, cooldownSeconds: 1800)
        XCTAssertFalse(helloGiveUp.recordRefusal(authRefusal: false, now: t0))
        XCTAssertFalse(helloGiveUp.recordRefusal(authRefusal: false, now: t0))
        XCTAssertTrue(helloGiveUp.recordRefusal(authRefusal: false, now: t0), "Unanswered hello latches at 3")
        XCTAssertTrue(WhoopHelloSuppression.giveUpSuppressesHello(authRefusal: false))
        XCTAssertFalse(WhoopHelloSuppression.shouldSendClientHello(suppressedForDevice: true, userInitiated: false))
        XCTAssertTrue(WhoopHelloSuppression.shouldSendClientHello(suppressedForDevice: true, userInitiated: true))

        // FrameCorruptionDetector (>= 20% invalid over >= 20 samples) & PostBondTimeoutLoopDetector
        var corr = WhoopFrameCorruptionDetector(windowSize: 50, rateThreshold: 0.20, minSamples: 20)
        for i in 0..<19 { _ = corr.feed(valid: i >= 4) } // 4 invalid in 19 (< minSamples)
        XCTAssertFalse(corr.tripped)
        XCTAssertTrue(corr.feed(valid: true)) // 20th sample -> 4/20 = 20% -> trips!

        var loop = WhoopPostBondTimeoutLoopDetector(tripThreshold: 2, quickTimeoutWindow: 8.0)
        XCTAssertFalse(loop.connectionEnded(wasBonded: true, secondsSinceBond: 1.5, timedOut: true))
        XCTAssertTrue(loop.connectionEnded(wasBonded: true, secondsSinceBond: 2.0, timedOut: true))

        // ClockPolicy suspect phone clock guard
        XCTAssertTrue(WhoopClockPolicy.phoneClockSuspect(deviceClock: 1_795_800_000, wallNow: 1_795_700_000))
        XCTAssertTrue(WhoopClockPolicy.shouldSetClock(deviceClock: 100_000, wallNow: 1_795_700_000))
    }
}
