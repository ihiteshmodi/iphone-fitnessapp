Feature: Measurement progress
  As the lifter I want to see how far each body measurement is from its target, in the right direction.

  Scenario: Growth goal shows inches left to gain
    Given the latest "Left Calf" is 14.00 inches and the target is 15.31
    When I open Progress
    Then "Left Calf" shows 1.31 inches to gain

  Scenario: Shrink goal shows inches left to lose, not a negative gain
    Given the latest "Waist" is 30.20 inches and the target is 28.00
    When I open Progress
    Then "Waist" shows 2.20 inches to lose

  Scenario: Target reached
    Given the latest "Neck" is 13.80 inches and the target is 13.80
    When I open Progress
    Then "Neck" shows "At target"

  Scenario: Only the newest reading per site counts
    Given "Chest" was logged as 39.0 on 2026-09-01 and 39.8 on 2026-10-01
    When I open Progress
    Then "Chest" current is 39.8

  Scenario: A site with a target but no reading
    Given "Neck" has a target but no readings
    When I open Progress
    Then "Neck" shows "No reading yet"

  Scenario: Change a target from the measurement screen
    Given I opened "Left Calf" with current 14.00 and target 15.31
    When I set the target to 15.5
    Then "Left Calf" shows 1.50 inches to gain

  Scenario: Add a reading from the measurement screen
    Given I opened "Left Calf"
    When I log 14.3 inches on 2026-10-25
    Then current is 14.30 and the history chart gains a point

  Scenario: Correct or delete a wrong reading
    Given "Left Calf" has a reading 41.0 by mistake
    When I edit it to 14.1
    Then current uses 14.1

  Scenario: Add a new site to track
    When I add the site "Left Shin" with a first reading 11.0 and a target 11.5
    Then "Left Shin" appears on Progress with 0.50 inches to gain

  Scenario Outline: Being past the target is fine for sites that should grow and not for sites that should shrink
    Given "<site>" is a "<direction>" site with target <target> and current <current>
    Then Progress shows "<status>"

    Examples:
      | site      | direction | target | current | status                    |
      | Left Calf | grow      | 15.31  | 14.0    | 1.31 to gain              |
      | Shoulders | grow      | 45.3   | 46.0    | 0.70 ahead of target      |
      | Waist     | reduce    | 28.0   | 30.2    | 2.20 to lose              |
      | Waist     | reduce    | 28.0   | 27.0    | 1.00 ahead of target      |

  Scenario: Change which way a site should go
    Given "Hips" has a target of 36.0 and a reading of 38.0 and is a grow site
    When I set "Hips" to reduce
    Then Progress shows "2.00 to lose"

  Scenario: Sites that still need work come before sites that are ahead
    Given "Shoulders" is 0.7 ahead of its target and "Left Calf" has 0.31 to gain
    Then "Left Calf" is listed before "Shoulders"

  Scenario: A new site starts as reduce when its target is below its first reading
    When I add "Hips" with a first reading 38 and a target 36
    Then "Hips" is a reduce site
