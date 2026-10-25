Feature: Deload mode
  As the lifter I want a lighter week so that I can recover.
  The notebook defaults are weight multiplier 1 and reps multiplier 0.75 (applied to minimum reps).

  Scenario: Deload applies the multipliers and hides the recommendation
    Given deload mode is on with weight multiplier 0.8 and reps multiplier 0.75
    And "Chest Dips Machine" is planned with reps 6 to 10
    And the heaviest set is 54 kg for 8 reps
    When I open Day 3
    Then the working weight is 43.2 kg
    And warm-ups are 32.4 kg (75%) and 38.88 kg (90%)
    And the reps range is 4.5 to 10
    And no recommendation is shown

  Scenario: Default deload keeps weight and lowers minimum reps
    Given deload mode is on with the default multipliers
    When I open Day 3
    Then the working weight is the heaviest set weight
    And minimum reps are 75% of planned

  Scenario: Switching deload off restores normal targets without altering the plan
    Given deload mode was on
    When I switch deload off
    Then the planned minimum reps are the stored values again
    And the recommendation is shown

  Scenario: Sets logged during deload are remembered as deload sets
    Given deload is on
    When I log 40 kg × 6
    Then the set is saved as a deload set
    And switching deload off later does not change that

  Scenario: "Ignore deload sessions" on: deload sets do not count for progress
    Given "Ignore deload sessions" is on
    And "Chest Dips Machine" has normal sessions 60, 62, 64 (estimated 1RM) and a deload session of 40
    Then the trend is "Improving"
    And the working weight, last session, aim, mini trend line and volume chart ignore the deload session

  Scenario: "Ignore deload sessions" off: deload sets count like any other set
    Given "Ignore deload sessions" is off
    And the same sessions
    Then the deload session is part of the trend, which becomes "Declining"
    And last session shows the deload session

  Scenario: Deload sets are always visible
    Given "Ignore deload sessions" is on
    When I log a set during deload
    Then it appears in today's sets and counts toward the card's "1/3"
    And it appears in the history list marked "Deload"

  Scenario: The switch has a safe default
    Given a database that never had the switch
    Then "Ignore deload sessions" is on

  Scenario: Deload only changes what is shown, never what is logged
    Given "Chest Dips Machine" is normally 100 kg
    And deload is on with weight multiplier 0.7
    When I open the exercise
    Then the working weight shown is 70 kg
    When I log 70 kg × 6
    Then the set is stored as 70 kg
    And the working weight shown is still 70 kg, not 49 kg

  Scenario: The week after deload returns to the normal weight
    Given I logged 70 kg × 6 during deload week
    When I switch deload off
    Then the working weight is 100 kg again

  Scenario: Editing the plan during deload shows and saves the stored values
    Given "Chest Dips Machine" is planned with minimum reps 6 and deload is on
    When I open the plan editor
    Then the minimum reps shown are 6, not 4.5

  Scenario: A multiplier must be positive
    When I set the deload reps multiplier to 0
    Then the setting is rejected with "Multiplier must be greater than 0"
