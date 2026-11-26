Feature: WHOOP 4.0 / 5.0 / MG wire framing, commands, byte-exact decoders, and beat timestamp reconstruction
  As the owner pairing a WHOOP 4.0, 5.0, or MG band on-device
  I want byte-exact Gen4 (CRC8 + CRC32) and Gen5 (CRC16-Modbus + CRC32) framing, command builders, historical/live/control decoders, and sub-second beat timing
  So that every packet decodes identically to OpenStrap/edge with zero protocol bugs

  Scenario: Gen5 CLIENT_HELLO frame and Gen4/Gen5 FrameReassembler resync safely across fragmented notifications and embedded 0xAA bytes
    Given the canonical Gen5 CLIENT_HELLO command (seq = 1, opcode = 0x91, payload = [0x01])
    When built with BandProfile.gen5
    Then the wire bytes equal "aa0108000001e67123019101363e5c8d"
    And FrameReassembler reassembles fragmented chunks containing 0xAA inside sensor payloads while advancing 1 byte past corrupt headers

  Scenario: Command builders enforce 65-byte 0x78 R22 flags, Gen5 2-zero NACK, 8-byte SET_CLOCK, HighFreqSync bounds, and dangerous opcode guard
    When building kGen5R22EnableFlags via cmdSetConfigGen5
    Then each payload is 65 bytes with ASCII '1' (0x31) for enable_r22_* and ASCII '2' (0x32) for disable_pip_r26_packets
    And buildHistoryResultFail emits [0x23, seq, 0x17, 0x00, 0x00] on Gen5 and [0x23, seq, 0x17, 0x00] on Gen4
    And dangerous opcodes (forgetBonds, forceTrim, rebootStrap, setClockMaverick) are rejected unless explicitly authorized

  Scenario: Gen4 R24/v12/v7/v9/v18/v25 and R10 historical decoders read exact byte offsets and refuse v25 pseudo-gravity
    Given a Gen4 v24 record with counter, tsEpoch, tsSubsec, HR, 3 RR beats, 3x f32 accelG, spo2Red/Ir, skinTempRaw, and ambientRaw, plus an 88-byte v12 record and a 76-byte v25 PPG burst
    When decoded by FirmwareAwareR24Decoder
    Then v24 and 88-byte v12 preserve every offset including tsSubsec and ambientRaw, out-of-range RR beats are dropped, and v25 returns HR = 0 and empty accelG so it routes to raw_archive_frames

  Scenario: Gen5 v18 decoder preserves signed sub-zero skinTempC, -5000 unavailable sentinel without dropping aux temps, 0..16g dynAccel, and sleepState nibble
    Given a Gen5 v18 record with signed skinTemp raw -5000 (-50.00 C sentinel), aux temps 32.9 C and 33.2 C, dynAccel 11.5 g, step counter 31904, and sleepStateByte 0x20
    When decoded by Gen5V18Decoder
    Then skinTempCOrNull is nil while tempAux1C = 32.9 and tempAux2C = 33.2 survive, dynamicAccelerationG = 11.5, stepMotionCounter = 31904, and sleepState = .sleep

  Scenario: Event 3 BATTERY_LEVEL charging offset fix, Event 63 charge_units, 0x24 Gen5HelloInfo/DataRange, 0x31 HISTORY_END, 0x28 RR cap, and 0x33/0x2B IMU frames decode accurately
    Given real Event 3 hex "30050300fc40ff6a3d4a1400029b010000e80e00000000101105000901000000" and an Event 3 with body[9] = 1
    When parseEvent runs
    Then battery_pct = 41.1, battery_mv = 3816, and charging reads body[9] (inner[21]), never body[10]
    And 0x28 realtime HR caps rr_count at 4 so wearing at inner[18] is never read as an RR beat

  Scenario: beatTimesMs reconstructs backward beat-end timestamps matching real OpenStrap export DB and monotonizeBeatAxis clamps seam inversions
    Given recTs = 1795113155, tsSubsec = 27197, and rrIntervalsMs = [839, 876] from the real export database
    When beatTimesMs runs
    Then beat 1 sits at 1795113155829 ms and beat 0 sits at 1795113154953 ms
    And monotonizeBeatAxis clamps any backward seam step without altering interval values
