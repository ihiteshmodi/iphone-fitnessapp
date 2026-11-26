import XCTest
@testable import FitnessCore

final class WhoopSessionCoordinatorTests: XCTestCase {
    func testGen5BootstrapConfiguresR22SyncsClockAndCommitsPreAckBurstBeforeEmitting0x17Ok() throws {
        let store = try WhoopStore.inMemory()
        var coordinator = WhoopSessionCoordinator(profile: .gen5, deviceID: "maverick-01")
        let phoneNowSec = 1_795_700_000

        // 1. Link ready -> sends Gen5 GET_HELLO (0x91) + GET_CLOCK (0x0B)
        let bootFrames = coordinator.onLinkReady()
        XCTAssertEqual(bootFrames.count, 2)
        let helloReq = try XCTUnwrap(WhoopFraming.parseFrame(bootFrames[0], profile: .gen5))
        XCTAssertEqual(helloReq.opcode, WhoopCmd.getHello)

        // 2. Band responds with Maverick 104B GET_HELLO -> coordinator emits 65B 0x78 R22 enable + GET_DATA_RANGE (0x22)
        var helloBody = [UInt8](repeating: 0, count: 104)
        helloBody[0] = 1 // helloRevision == 1 && opticalDiscriminator < 38 -> Maverick!
        helloBody[1] = 200; helloBody[2] = 3 // 96.8%
        helloBody[5] = 1 // charging
        // tsSeconds = 1_795_699_900 (100s behind phone -> triggers SET_CLOCK 0x0A)
        let strapClock: UInt32 = 1_795_699_900
        helloBody[6] = UInt8(strapClock & 0xFF)
        helloBody[7] = UInt8((strapClock >> 8) & 0xFF)
        helloBody[8] = UInt8((strapClock >> 16) & 0xFF)
        helloBody[9] = UInt8((strapClock >> 24) & 0xFF)
        let serialBytes = Array("MAV12345".utf8)
        helloBody.replaceSubrange(14..<(14 + serialBytes.count), with: serialBytes)
        helloBody[87] = 20 // opticalDiscriminator < 38 -> Maverick
        helloBody[102] = 1 // wrist_on
        let helloRespRaw = WhoopFraming.buildFrame(
            [WhoopPacketType.commandResponse, 0x01, WhoopCmd.getHello, helloReq.seq > 0 ? UInt8(helloReq.seq) : 1, 0x01] + helloBody,
            profile: .gen5)

        let postHelloOut = try coordinator.receiveRawDataFromStrap(helloRespRaw, store: store, nowMs: Int64(phoneNowSec) * 1000)
        let parsedPostHello = postHelloOut.txFrames.compactMap { WhoopFraming.parseFrame($0, profile: .gen5) }
        // 3B inner header + 65B R22 payload = 68B padded to 4-byte boundary -> 68B inner
        XCTAssertTrue(parsedPostHello.contains { $0.opcode == WhoopCmd.setFfValue && $0.inner.count == 68 })
        XCTAssertTrue(parsedPostHello.contains { $0.opcode == WhoopCmd.setClock })
        XCTAssertTrue(parsedPostHello.contains { $0.opcode == WhoopCmd.getDataRange })
        XCTAssertTrue(coordinator.isMaverick)
        XCTAssertEqual(coordinator.serialNumber, "MAV12345")

        // 3. Start drain -> HISTORY_START -> 1 valid v18 packet -> HISTORY_END(expectedCount=1, token=8 bytes)
        let startMetaRaw = WhoopFraming.buildFrame([WhoopPacketType.metadata, 0x01, WhoopMetaSubType.historyStart.rawValue], profile: .gen5)
        _ = try coordinator.receiveRawDataFromStrap(startMetaRaw, store: store, nowMs: Int64(phoneNowSec) * 1000)

        var v18Inner = [UInt8](repeating: 0, count: 112)
        v18Inner[0] = WhoopPacketType.historicalData
        v18Inner[1] = 18
        v18Inner[3] = 42 // counter
        let recTs: UInt32 = 1_795_699_950
        v18Inner[7] = UInt8(recTs & 0xFF)
        v18Inner[8] = UInt8((recTs >> 8) & 0xFF)
        v18Inner[9] = UInt8((recTs >> 16) & 0xFF)
        v18Inner[10] = UInt8((recTs >> 24) & 0xFF)
        v18Inner[11] = 0x00; v18Inner[12] = 0x40 // 0.5s subsec
        v18Inner[14] = 58 // HR
        v18Inner[15] = 1  // 1 RR
        v18Inner[16] = 0xE8; v18Inner[17] = 0x03 // 1000 ms
        let histRaw = WhoopFraming.buildFrame(v18Inner, profile: .gen5)
        _ = try coordinator.receiveRawDataFromStrap(histRaw, store: store, nowMs: Int64(phoneNowSec) * 1000)

        let token: [UInt8] = [0xAA, 0xBB, 0xCC, 0xDD, 0x01, 0x02, 0x03, 0x04]
        var endMetaInner: [UInt8] = [WhoopPacketType.metadata, 0x02, WhoopMetaSubType.historyEnd.rawValue]
        endMetaInner += [0, 0, 0, 0, 0, 0] // bytes 3..8 clock
        endMetaInner += [1, 0, 0, 0]       // bytes 9..12 expectedCount = 1
        endMetaInner += token              // bytes 13..20 token
        let endMetaRaw = WhoopFraming.buildFrame(endMetaInner, profile: .gen5)

        let endOut = try coordinator.receiveRawDataFromStrap(endMetaRaw, store: store, nowMs: Int64(phoneNowSec) * 1000)
        // Verify SQLite committed BEFORE 0x17 ACK was returned!
        XCTAssertEqual(try store.count("decoded_onehz"), 1)
        XCTAssertEqual(try store.count("decoded_rr"), 1)
        XCTAssertEqual(try store.cursorValue("strap_trim"), "aabbccdd01020304")

        let ackFrame = try XCTUnwrap(endOut.txFrames.compactMap { WhoopFraming.parseFrame($0, profile: .gen5) }.first)
        XCTAssertEqual(ackFrame.opcode, WhoopCmd.historicalDataResult)
        XCTAssertEqual(Array(ackFrame.body.prefix(1 + token.count)), [0x01] + token)
    }

    func testPacketLossMismatchEmitsGen5TwoZeroByteNegativeAckWithoutAdvancingTrimCursor() throws {
        let store = try WhoopStore.inMemory()
        var coordinator = WhoopSessionCoordinator(profile: .gen5, deviceID: "maverick-01")
        _ = coordinator.onLinkReady()

        let startRaw = WhoopFraming.buildFrame([WhoopPacketType.metadata, 0x01, WhoopMetaSubType.historyStart.rawValue], profile: .gen5)
        _ = try coordinator.receiveRawDataFromStrap(startRaw, store: store, nowMs: 1_795_700_000_000)

        // HISTORY_END declares expectedCount = 3, but 0 historical packets arrived!
        let token: [UInt8] = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
        var endInner: [UInt8] = [WhoopPacketType.metadata, 0x02, WhoopMetaSubType.historyEnd.rawValue]
        endInner += [0, 0, 0, 0, 0, 0]
        endInner += [3, 0, 0, 0] // expected 3!
        endInner += token
        let endRaw = WhoopFraming.buildFrame(endInner, profile: .gen5)

        let out = try coordinator.receiveRawDataFromStrap(endRaw, store: store, nowMs: 1_795_700_000_000)
        XCTAssertNil(try store.cursorValue("strap_trim"), "Negative ACK must NEVER advance strap_trim")

        let nackRaw = try XCTUnwrap(out.txFrames.first)
        // Exact unpaddedGen4 fail frame vs Gen5 fail frame check:
        XCTAssertEqual(nackRaw, WhoopCommands.buildHistoryResultFail(seq: WhoopSeqAllocator.syncFloor, profile: .gen5))
        let nackFrame = try XCTUnwrap(WhoopFraming.parseFrame(nackRaw, profile: .gen5))
        XCTAssertEqual(nackFrame.opcode, WhoopCmd.historicalDataResult)
        XCTAssertEqual(Array(nackFrame.body.prefix(2)), [0x00, 0x00], "Gen5 negative 0x17 ACK must carry TWO zero bytes")
    }
}
