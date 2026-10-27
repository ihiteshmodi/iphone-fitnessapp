Feature: Log sets on another day, and correct sets already logged
  As the lifter I forget to log some days and sometimes log a wrong number, so I want to add a set for an earlier day
  and fix any set I logged before, without deleting and retyping it.

  Scenario: Log a set for yesterday
    Given today is 2026-10-25
    When I log "Leg Extension" 55 kg × 10 on 2026-10-24
    Then the set is stored on 2026-10-24 and not on 2026-10-25

  Scenario: A set cannot be dated in the future
    Given today is 2026-10-25
    When I log "Leg Extension" 55 kg × 10 on 2026-10-26
    Then it is rejected with "Pick today or an earlier date"
    And nothing is stored

  Scenario: Correct a wrong set in place
    Given I logged "Leg Extension" 55 kg × 10 on 2026-10-24
    When I change it to 52.5 kg × 12
    Then the same set now reads 52.5 kg × 12
    And no second set exists

  Scenario: Move a set to the day it really happened
    Given I logged "Leg Extension" 55 kg × 10 on 2026-10-25 by mistake
    When I change its date to 2026-10-24
    Then it is on 2026-10-24 and no longer on 2026-10-25

  Scenario Outline: A correction must be valid too
    When I change a logged set to <weight> kg × <reps> on <date>
    Then it is rejected with "<message>" and the set is unchanged

    Examples:
      | weight | reps | date       | message                       |
      | -5     | 10   | 2026-10-24 | Weight cannot be negative     |
      | 55     | 0    | 2026-10-24 | Reps must be at least 1       |
      | 55     | 10   | 2026-10-26 | Pick today or an earlier date |

  Scenario: Earlier sessions of one exercise, newest first
    Given "Leg Extension" was logged on 2026-10-18, 2026-10-21, 2026-10-24 and today
    When I ask for the earlier sessions, leaving out today
    Then I get 2026-10-24, 2026-10-21, 2026-10-18 with their sets
