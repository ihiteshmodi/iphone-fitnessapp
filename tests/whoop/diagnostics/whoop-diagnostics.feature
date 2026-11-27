Feature: WHOOP Hardware Diagnostic Telemetry, SQLite Row Inspector, and WAL-Checkpointed Export

  As the iPhone owner verifying real WHOOP strap connectivity inside LiveContainer
  I want a single diagnostic screen showing handshake metadata, live 0x28 HR/RR & burst/CRC/0x17 counters, and the latest SQLite rows with a WAL-checkpointed DB export
  So I can confirm byte-exact BLE hardware sync on my phone and inspect the resulting SQLite file on my Mac before Part 3 analytics are built.

  Scenario: Gen5 0x91 GET_HELLO, live 0x28 HR/RR, CRC errors, and 0x17 ACK/NACK verdicts update diagnostic telemetry
    Given a Gen5 WhoopSessionCoordinator connected to an in-memory WhoopStore
    When a 104-byte Maverick GET_HELLO (0x91) response arrives with firmware 50.32.2.0 and battery 84.5% charging
    And a live 0x28 packet arrives with HR 64 bpm and RR intervals [912, 948] ms
    And 1 corrupted frame (bad CRC32) arrives followed by a valid 1-packet v18 burst and HISTORY_END(expected=1)
    Then handshake telemetry reports generation "Gen5 / MG (Maverick)", firmware "50.32.2.0", battery 84.5%, charging true
    And burst telemetry reports live HR 64 bpm, live RR [912, 948] ms, rolling CRC error count 1, expectedPacketCount 1, actualPacketCount 1, and last 0x17 verdict "send"
    When a subsequent burst ends with HISTORY_END(expected=4) after 0 packets
    Then burst telemetry reports expectedPacketCount 4, actualPacketCount 0, last 0x17 verdict "blockedPacketCountMismatch", and nackCount 1

  Scenario: SQLite inspector returns latest 5 decoded_onehz and decoded_rr rows and exports a WAL-checkpointed database
    Given a file-backed WAL WhoopStore with 7 committed Gen5 v18 seconds and RR beats
    When inspect(limit: 5) is queried on the store
    Then latestOneHzRows returns the 5 newest rows ordered by ts_ms descending with ts_ms, ts_subsec, hr, ax/ay/az, skin_temp_c, and skin_temp_raw populated
    And latestRrRows returns the 5 newest RR beats ordered by ts_ms and beat_index descending with rr_ms and beat_ts_ms populated
    When exportCheckpointedSnapshot runs PRAGMA wal_checkpoint(TRUNCATE)
    Then the WAL file is truncated to 0 bytes and the exported SQLite file contains all 7 decoded_onehz rows and passes PRAGMA integrity_check
