Feature: Log body weight and body measurements
  As the lifter I want to record body weight and measurements so that calories and progress stay current.

  Scenario: Log body weight
    When I log body weight 63.9 kg on 2026-10-23
    Then the entry is stored and used by the calorie target

  Scenario: Log a measurement for a body site
    When I log "Waist" 30.2 inches on 2026-10-23
    Then the entry is stored for "Waist"

  Scenario: Set a target measurement
    When I set the target for "Left Calf" to 15.31 inches
    Then progress for "Left Calf" is measured against 15.31 inches

  Scenario Outline: Reject invalid entries
    When I log <kind> <value> on 2026-10-23
    Then it is rejected with "<message>"

    Examples:
      | kind        | value | message                          |
      | body weight | 0     | Body weight must be above 0      |
      | measurement | -1    | Measurement must be above 0      |
