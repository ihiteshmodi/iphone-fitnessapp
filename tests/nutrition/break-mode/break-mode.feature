Feature: Break mode
  As the lifter I sometimes take a break (a trip, a holiday) when I don't log food, workouts or weight.
  I want to mark those days so the calorie maths ignores them, recalibrates after, and still shows where I stood before.

  Background:
    Given weigh-ins every day from 2026-11-01 to 2026-11-30 except during the break
    And a default of 2600 calories a day

  Scenario: A break with dates is left out of the maths
    Given a break from 2026-11-15 to 2026-11-21
    Then 2026-11-15 to 2026-11-21 are break days and 2026-11-14 and 2026-11-22 are not

  Scenario: An open break lasts until it is ended
    Given I start a break on 2026-11-15
    Then I am on a break on 2026-11-20
    When I end the break on 2026-11-21
    Then the break covers 2026-11-15 to 2026-11-21

  Scenario: Breaks cannot overlap and must end on or after they start
    Given a break from 2026-11-15 to 2026-11-21
    When I add a break from 2026-11-20 to 2026-11-25
    Then I am told "That overlaps another break"
    And adding a break from 2026-11-25 to 2026-11-24 says "A break ends on or after the day it starts"

  Scenario: After a break the maths recalibrates until two clean weeks exist
    Given a break from 2026-11-10 to 2026-11-16 and weigh-ins again from 2026-11-17
    When the latest weigh-in is 2026-11-25
    Then I am told "Recalibrating after your break: 9 of 14 days"
    And once weigh-ins reach 2026-11-30 the target is worked out from 2026-11-17 onwards only

  Scenario: Break days never count toward calories eaten
    Given a break from 2026-11-15 to 2026-11-16 with 9000 calories typed on 2026-11-15
    Then the average of the 7 days ending 2026-11-16 is 2600

  Scenario: Where I stood before the break
    Given a break from 2026-11-17 to 2026-11-23
    Then "before your break" is the calorie maths as of 2026-11-16
    And the weight across the break is from the last weigh-in before it to the first one after it
