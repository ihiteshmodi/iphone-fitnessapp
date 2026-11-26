Feature: WHOOP BLE state machine, burst packet-count validation, pre-ACK trim gate, and CoreBluetooth fault isolation
  As the owner syncing a WHOOP 4.0 or 5.0/MG strap continuously in foreground and background
  I want burst traffic accounting, pre-ACK safety checks, reconnect standing-connect scheduling, and bond/radio fault isolation
  So that flash pages are never trimmed before durable commit and BLE edge cases never spin the radio

  Scenario: FrameRoutePolicy and BurstStats count data and inline event/console/puffin traffic accurately for Gen5 expectedPacketCount gate
    Given a Gen5 burst between HISTORY_START and HISTORY_END expecting 5 packets
    When 3 historical 0x2F records and 1 inline 0x30 event arrive (actual = 4 < 5) on attempt 1
    Then BurstStats reports shortfall and TrimAckPolicy returns blockedBurstShortfall so a Negative 0x17 ACK ([0x00, 0x00]) is sent
    When consecutiveFailedValidations reaches 3
    Then slack widens to 2 and 4 of 5 packets passes

  Scenario: TrimAckPolicy blocks stale sessions, discarded bursts, failed commits, and unarchived drop-only bursts
    When evaluating TrimAckPolicy across stale session, idle-watchdog discarded burst, failed commit, and future-dropped-only burst
    Then each returns its exact blocked verdict and only returns .send when all rows or below-floor archives are durably committed

  Scenario: StandingConnect reconnect step, Whoop4BondAck, ClientHelloOutcome, HelloSuppression, and radio/bond loop detectors isolate faults
    When involuntary disconnect occurs >= 2s after standing connect
    Then ReconnectStep immediately issues a passive standing connect, and throttles to 30s only on < 2s hot-loop failures
    And ClientHelloOutcome requires both fd4b0002 and helloOutstanding to prove a Gen5 bond
    And BondRefusalGiveUp pauses after 5 auth refusals (with 30-min cooldown) while suppressing 0x91 after 3 unanswered Gen5 hellos
