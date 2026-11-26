import Foundation

public enum WhoopConnPhase: String, Equatable, Sendable {
    case idle, scanning, connecting, discovering, subscribing, settingUp, listening, reconnecting, error

    public var uiStateString: String {
        switch self {
        case .idle, .error: return "disconnected"
        case .scanning: return "scanning"
        case .connecting, .discovering, .subscribing, .settingUp, .reconnecting: return "connecting"
        case .listening: return "connected"
        }
    }
}

/// Non-colliding sequence allocator: sync ACKs use `0x05..0xFF` (wrapping to `0x05`), live commands use `0xA0..0xFF` (wrapping to `0xA0`).
public struct WhoopSeqAllocator: Equatable, Sendable {
    public static let liveFloor: UInt8 = 0xA0
    public static let syncFloor: UInt8 = 0x05

    private var live: Int = Int(Self.liveFloor)
    private var sync: Int = Int(Self.syncFloor)

    public init() {}

    public mutating func nextLive() -> UInt8 {
        let out = UInt8(live & 0xFF)
        live = (live + 1) & 0xFF
        if live < Int(Self.liveFloor) { live = Int(Self.liveFloor) }
        return out
    }

    public mutating func nextSync() -> UInt8 {
        let out = UInt8(sync & 0xFF)
        sync = (sync + 1) & 0xFF
        if sync < Int(Self.syncFloor) { sync = Int(Self.syncFloor) }
        return out
    }

    public mutating func reset() {
        live = Int(Self.liveFloor)
        sync = Int(Self.syncFloor)
    }
}

public enum WhoopFrameRoute: Equatable, Sendable {
    case serializedQueue
    case immediate
    case immediateAndCount
}

public enum WhoopFrameRoutePolicy {
    public static let inlineBurstTrafficTypes: Set<UInt8> = [
        WhoopPacketType.event,
        WhoopPacketType.consoleLogs,
        WhoopPacketType.relativePuffinEvents,
        WhoopPacketType.puffinEventsFromStrap,
        WhoopPacketType.relativeBatteryPackConsoleLogs,
    ]

    public static func route(packetType: UInt8, isDataRole: Bool, offloadActive: Bool) -> WhoopFrameRoute {
        if packetType == WhoopPacketType.metadata {
            return .serializedQueue
        }
        if packetType == WhoopPacketType.historicalData && isDataRole {
            return .serializedQueue
        }
        if offloadActive && inlineBurstTrafficTypes.contains(packetType) {
            return .immediateAndCount
        }
        return .immediate
    }
}

public struct WhoopBurstStats: Equatable, Sendable {
    public private(set) var dataPackets = 0
    public private(set) var inlineTrafficPackets = 0
    public private(set) var consecutiveFailedValidations = 0

    public var totalTrafficPacketCount: Int { dataPackets + inlineTrafficPackets }

    public init() {}

    public mutating func beginBurst() {
        dataPackets = 0
        inlineTrafficPackets = 0
    }

    public mutating func recordDataPacket() {
        dataPackets += 1
    }

    public mutating func recordInlineTrafficMember() {
        inlineTrafficPackets += 1
    }

    public mutating func noteValidationFailure() {
        consecutiveFailedValidations += 1
    }

    public mutating func noteValidationSuccess() {
        consecutiveFailedValidations = 0
    }

    public func passesGen5CountGate(expectedPacketCount: Int, droppedThisBurst: Int) -> Bool {
        let actual = totalTrafficPacketCount + droppedThisBurst
        let slack = consecutiveFailedValidations >= 3 ? 2 : 0
        return (expectedPacketCount - slack) <= actual
    }
}

public struct WhoopBurstTrimGuard: Equatable, Sendable {
    public private(set) var discarded = false
    public private(set) var poisonedBursts = 0

    public init() {}

    public mutating func beginBurst() {
        discarded = false
    }

    public mutating func discardOpenChunk() {
        guard !discarded else { return }
        discarded = true
        poisonedBursts += 1
    }
}

public struct WhoopRecordGate: Equatable, Sendable {
    public static let minPlausibleUnix = 1_700_000_000
    public static let futureMarginSec = 86_400
    public static let sessionRangeMarginSec = 7 * 86_400

    public var frontierTs: Int
    public private(set) var dropped = 0
    public private(set) var droppedBelowFloor = 0

    public init(frontierTs: Int = 0) {
        self.frontierTs = frontierTs
    }

    public var timeBaseNotWallClock: Bool {
        dropped > 0 && dropped == droppedBelowFloor
    }

    public static func isPlausibleUnix(_ ts: Int, wallNow: Int, sessionOldestUnix: Int? = nil, sessionNewestUnix: Int? = nil) -> Bool {
        if ts < minPlausibleUnix || ts > wallNow + futureMarginSec { return false }
        if let oldest = sessionOldestUnix, let newest = sessionNewestUnix,
           oldest >= minPlausibleUnix, newest >= oldest {
            return ts >= oldest - sessionRangeMarginSec && ts <= newest + sessionRangeMarginSec
        }
        return true
    }

    public mutating func admit(_ tsEpoch: Int?, wallNow: Int, sessionOldestUnix: Int? = nil, sessionNewestUnix: Int? = nil) -> Bool {
        guard let tsEpoch, tsEpoch > 0 else { return true }
        guard Self.isPlausibleUnix(tsEpoch, wallNow: wallNow, sessionOldestUnix: sessionOldestUnix, sessionNewestUnix: sessionNewestUnix) else {
            dropped += 1
            if tsEpoch < Self.minPlausibleUnix { droppedBelowFloor += 1 }
            return false
        }
        if tsEpoch > frontierTs { frontierTs = tsEpoch }
        return true
    }
}

public enum WhoopTrimAckVerdict: Equatable, Sendable {
    case send
    case blockedStaleSession
    case blockedDiscardedBurst
    case blockedCommitFailed
    case blockedNoDurableProgress
    case blockedBurstShortfall
}

public enum WhoopTrimAckPolicy {
    public static func evaluate(sessionCurrent: Bool, burstDiscarded: Bool, commitDurable: Bool,
                                hadDurableRows: Bool = true, droppedThisBurst: Int = 0,
                                droppedBelowFloorThisBurst: Int = 0, gateDropArchives: Int = 0,
                                shortfallRetry: Bool = false) -> WhoopTrimAckVerdict {
        if !sessionCurrent { return .blockedStaleSession }
        if burstDiscarded { return .blockedDiscardedBurst }
        if !commitDurable { return .blockedCommitFailed }
        if !hadDurableRows && droppedThisBurst > 0 {
            let floorOnly = (droppedBelowFloorThisBurst == droppedThisBurst)
            let allArchived = (gateDropArchives >= droppedThisBurst)
            if !floorOnly || !allArchived {
                return .blockedNoDurableProgress
            }
        }
        if shortfallRetry { return .blockedBurstShortfall }
        return .send
    }
}

public struct WhoopAckRetryPolicy: Equatable, Sendable {
    public let maxAttempts: Int
    public let baseDelayMs: Int

    public init(maxAttempts: Int = 3, baseDelayMs: Int = 200) {
        self.maxAttempts = maxAttempts
        self.baseDelayMs = baseDelayMs
    }

    public func shouldRetry(failedAttempts: Int) -> Bool {
        failedAttempts < maxAttempts
    }

    public func delayMs(forAttempt attempt: Int) -> Int {
        max(1, attempt) * baseDelayMs
    }
}

public struct WhoopChunkFailureLedger: Equatable, Sendable {
    public let quarantineThreshold: Int
    private var failures: [String: Int] = [:]

    public init(quarantineThreshold: Int = 3) {
        self.quarantineThreshold = quarantineThreshold
    }

    @discardableResult
    public mutating func recordFailure(tokenHex: String) -> Int {
        let next = (failures[tokenHex] ?? 0) + 1
        failures[tokenHex] = next
        return next
    }

    public func failureCount(tokenHex: String) -> Int {
        failures[tokenHex] ?? 0
    }

    public func shouldQuarantine(tokenHex: String) -> Bool {
        (failures[tokenHex] ?? 0) >= quarantineThreshold
    }

    public mutating func recordSuccess(tokenHex: String) {
        failures.removeValue(forKey: tokenHex)
    }
}

public struct WhoopNoDurableProgressEscalation: Equatable, Sendable {
    public private(set) var consecutiveRefusals = 0
    public private(set) var failedRemedies = 0

    public init() {}

    public enum Remedy: Equatable, Sendable {
        case none
        case setClockAndReconnect
        case surfaceFaultAndBackoff(multiplier: Int)
    }

    public mutating func noteNoDurableProgress() -> Remedy {
        consecutiveRefusals += 1
        guard consecutiveRefusals >= 3 else { return .none }
        consecutiveRefusals = 0
        failedRemedies += 1
        if failedRemedies < 3 {
            return .setClockAndReconnect
        }
        let mult = 1 << min(6, failedRemedies - 2)
        return .surfaceFaultAndBackoff(multiplier: mult)
    }

    public mutating func noteDurableProgress() {
        consecutiveRefusals = 0
        failedRemedies = 0
    }
}

/// Standing-Connect passive reconnect scheduler (`noop-main/Strand/BLE/BLEManager.swift`).
public enum WhoopReconnectStep: Equatable, Sendable {
    public static let fastFailureSeconds: TimeInterval = 2.0
    public static let retryFloorSeconds: TimeInterval = 30.0

    case standingConnect
    case standingConnectAfter(delay: TimeInterval)

    public static func decide(secondsSinceStandingConnect: TimeInterval?) -> WhoopReconnectStep {
        guard let since = secondsSinceStandingConnect, since >= 0, since < fastFailureSeconds else {
            return .standingConnect
        }
        return .standingConnectAfter(delay: retryFloorSeconds - since)
    }
}

public enum Whoop4BondAck: Equatable, Sendable {
    case firstBond
    case reprove
    case alreadyProven

    public static func classify(didBond: Bool, encryptedBond: Bool, samePeripheralAsBond: Bool) -> Whoop4BondAck {
        if !didBond || !samePeripheralAsBond { return .firstBond }
        return encryptedBond ? .alreadyProven : .reprove
    }
}

public enum WhoopClientHelloOutcome {
    public static let minPlausibleAttRoundTripMs = 8

    public enum HelloAck: Equatable, Sendable {
        case firstBond
        case reprove
        case alreadyProven
        case notAnAck
    }

    public static func classify(isHelloChar: Bool, helloOutstanding: Bool, alreadyBonded: Bool,
                                encryptedBond: Bool, samePeripheralAsBond: Bool, isWhoop5: Bool) -> HelloAck {
        guard isWhoop5, isHelloChar, helloOutstanding else { return .notAnAck }
        if !alreadyBonded || !samePeripheralAsBond { return .firstBond }
        return encryptedBond ? .alreadyProven : .reprove
    }
}

public enum WhoopHelloSuppression {
    public static let unansweredGiveUpThreshold = 3

    public static func shouldSendClientHello(suppressedForDevice: Bool, userInitiated: Bool) -> Bool {
        !suppressedForDevice || userInitiated
    }

    public static func giveUpThresholdFor(authRefusal: Bool, pauseThreshold: Int = 5) -> Int {
        authRefusal ? pauseThreshold : unansweredGiveUpThreshold
    }

    public static func giveUpSuppressesHello(authRefusal: Bool) -> Bool {
        !authRefusal
    }

    public static func prefKey(for peripheralID: String?) -> String? {
        guard let raw = peripheralID?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return "noop.helloUnanswered.\(raw.lowercased())"
    }

    public static func isSuppressed(_ peripheralID: String?, defaults: UserDefaults = .standard) -> Bool {
        guard let key = prefKey(for: peripheralID) else { return false }
        return defaults.bool(forKey: key)
    }

    public static func setSuppressed(_ peripheralID: String?, _ suppressed: Bool, defaults: UserDefaults = .standard) {
        guard let key = prefKey(for: peripheralID) else { return }
        if suppressed {
            defaults.set(true, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

public struct WhoopBondRefusalGiveUp: Equatable, Sendable {
    public let giveUpThreshold: Int
    public let cooldownSeconds: TimeInterval
    public private(set) var refusals = 0
    public private(set) var gaveUp = false
    public private(set) var gaveUpAt: Date?

    public init(giveUpThreshold: Int = 5, cooldownSeconds: TimeInterval = 1800) {
        self.giveUpThreshold = giveUpThreshold
        self.cooldownSeconds = cooldownSeconds
    }

    public mutating func recordRefusal(authRefusal: Bool, now: Date) -> Bool {
        refusals += 1
        let target = WhoopHelloSuppression.giveUpThresholdFor(authRefusal: authRefusal, pauseThreshold: giveUpThreshold)
        if !gaveUp && refusals >= target {
            gaveUp = true
            gaveUpAt = now
            return true
        }
        return false
    }

    public mutating func stillPaused(now: Date) -> Bool {
        guard gaveUp else { return false }
        if let since = gaveUpAt, now.timeIntervalSince(since) >= cooldownSeconds {
            reset()
            return false
        }
        return true
    }

    public mutating func reset() {
        refusals = 0
        gaveUp = false
        gaveUpAt = nil
    }
}

public struct WhoopMarginalRadioDetector: Equatable, Sendable {
    public let tripThreshold: Int
    public let quickTimeoutWindow: TimeInterval
    public private(set) var consecutiveArmTimeouts = 0
    public private(set) var tripped = false

    public init(tripThreshold: Int = 2, quickTimeoutWindow: TimeInterval = 20.0) {
        self.tripThreshold = tripThreshold
        self.quickTimeoutWindow = quickTimeoutWindow
    }

    public mutating func connectionEnded(wasArmed: Bool, secondsSinceArm: TimeInterval?, timedOut: Bool) -> Bool {
        let armTimeout = wasArmed && timedOut && (secondsSinceArm.map { $0 <= quickTimeoutWindow } ?? false)
        guard armTimeout else {
            consecutiveArmTimeouts = 0
            return false
        }
        consecutiveArmTimeouts += 1
        if !tripped && consecutiveArmTimeouts >= tripThreshold {
            tripped = true
            return true
        }
        return false
    }

    public mutating func reset() {
        consecutiveArmTimeouts = 0
        tripped = false
    }
}

public struct WhoopFrameCorruptionDetector: Equatable, Sendable {
    public let windowSize: Int
    public let rateThreshold: Double
    public let minSamples: Int
    private var window: [Bool] = []
    private var invalidInWindow = 0
    public private(set) var tripped = false

    public init(windowSize: Int = 50, rateThreshold: Double = 0.20, minSamples: Int = 20) {
        self.windowSize = windowSize
        self.rateThreshold = rateThreshold
        self.minSamples = minSamples
    }

    public mutating func feed(valid: Bool) -> Bool {
        window.append(valid)
        if !valid { invalidInWindow += 1 }
        if window.count > windowSize {
            let removed = window.removeFirst()
            if !removed { invalidInWindow -= 1 }
        }
        guard !tripped, window.count >= minSamples else { return false }
        let rate = Double(invalidInWindow) / Double(window.count)
        if rate >= rateThreshold {
            tripped = true
            return true
        }
        return false
    }

    public mutating func reset() {
        window.removeAll()
        invalidInWindow = 0
        tripped = false
    }
}

public struct WhoopPostBondTimeoutLoopDetector: Equatable, Sendable {
    public let tripThreshold: Int
    public let quickTimeoutWindow: TimeInterval
    public private(set) var consecutiveBondTimeouts = 0
    public private(set) var tripped = false

    public init(tripThreshold: Int = 2, quickTimeoutWindow: TimeInterval = 8.0) {
        self.tripThreshold = tripThreshold
        self.quickTimeoutWindow = quickTimeoutWindow
    }

    public mutating func connectionEnded(wasBonded: Bool, secondsSinceBond: TimeInterval?, timedOut: Bool) -> Bool {
        let quick = wasBonded && timedOut && (secondsSinceBond.map { $0 <= quickTimeoutWindow } ?? false)
        guard quick else {
            consecutiveBondTimeouts = 0
            return false
        }
        consecutiveBondTimeouts += 1
        if !tripped && consecutiveBondTimeouts >= tripThreshold {
            tripped = true
            return true
        }
        return false
    }

    public mutating func reset() {
        consecutiveBondTimeouts = 0
        tripped = false
    }
}

public enum WhoopClockPolicy {
    public static let suspectGraceSeconds: Double = 12.0 * 3600.0

    public static func acceptsClockRead(deviceClock: Int, wallNow: Int) -> Bool {
        deviceClock <= wallNow + WhoopRecordGate.futureMarginSec
    }

    public static func shouldSetClock(deviceClock: Int, wallNow: Int) -> Bool {
        abs(wallNow - deviceClock) > 86_400 || deviceClock < WhoopRecordGate.minPlausibleUnix
    }

    public static func phoneClockSuspect(deviceClock: Int, wallNow: Int) -> Bool {
        deviceClock >= WhoopRecordGate.minPlausibleUnix && deviceClock > wallNow + WhoopRecordGate.futureMarginSec
    }
}

public enum WhoopBackfillTrigger: Equatable, Sendable {
    case periodic, connect, foreground, manual, strap, autoContinue
}

public enum WhoopBackfillPolicy {
    public static let periodicFloorSeconds: Double = 900.0
    public static let periodicSlackSeconds: Double = 30.0
    public static let eventFloorSeconds: Double = 90.0
    public static let emptyBackoffThreshold = 3
    public static let maxEmptyBackoff: Double = 4.0

    public static func shouldRun(trigger: WhoopBackfillTrigger, now: Double, lastBackfillAt: Double?, emptyStreak: Int) -> Bool {
        guard let lastBackfillAt else { return true }
        let elapsed = now - lastBackfillAt
        if elapsed < 0 { return true }
        let backoff: Double = emptyStreak >= emptyBackoffThreshold
            ? min(maxEmptyBackoff, pow(2.0, Double(emptyStreak - emptyBackoffThreshold + 1)))
            : 1.0
        switch trigger {
        case .manual, .autoContinue:
            return true
        case .connect, .foreground:
            return elapsed >= eventFloorSeconds
        case .strap:
            return elapsed >= eventFloorSeconds * backoff
        case .periodic:
            return elapsed >= periodicFloorSeconds * backoff - periodicSlackSeconds
        }
    }
}

public enum WhoopBackfillContinuation {
    public static let defaultMaxAutoContinues = 6
    public static let defaultBehindGapSeconds = 300
    public static let defaultMaxAutoContinueSeconds: Double = 600.0

    public static func shouldAutoContinue(stillConnected: Bool, strapNewestTs: Int?, ourFrontierTs: Int?,
                                          rowsPersistedThisSession: Int, lastTrimAdvanced: Bool,
                                          consecutiveUnproductiveCount: Int, elapsedSeconds: Double = 0) -> Bool {
        guard stillConnected,
              elapsedSeconds < defaultMaxAutoContinueSeconds,
              consecutiveUnproductiveCount < defaultMaxAutoContinues,
              lastTrimAdvanced else { return false }
        if let strapNewestTs, let ourFrontierTs, (strapNewestTs - ourFrontierTs) > defaultBehindGapSeconds {
            return true
        }
        return rowsPersistedThisSession > 0
    }
}
