Feature: Daily calories with a default that starts on a date
  As the lifter I eat about the same each day, but some days differ, and I change my baseline from time to time.
  I want a default per day that applies from a date onward, a way to change single days, and the weekly maths to use what I really ate.

  Scenario: A new default applies from its start date onward and never rewrites earlier days
    Given the default was 2900 from 2026-10-01
    When I set the default to 3000 starting 2026-10-26
    Then 2026-10-25 counts as 2900 from the default
    And 2026-10-26 counts as 3000 from the default
    And 2026-10-30, a future day, counts as 3000 from the default
    And 2026-09-30, before any default, has no calories

  Scenario: The new default can start in the past
    Given the default was 2900 from 2026-10-01
    When I set the default to 3000 starting 2026-10-25
    Then 2026-10-24 counts as 2900 and 2026-10-25 counts as 3000

  Scenario: A day I changed by hand wins over the default
    Given the default is 2400 from 2026-10-01
    When I set 2026-10-21 to 3000
    Then 2026-10-21 counts as 3000 as a manual day
    And clearing it makes 2026-10-21 count as 2400 from the default again

  Scenario: The last 7 days with where each value comes from
    Given the default is 2400 from 2026-10-01 and 2026-10-24 is set to 1800
    When I ask for the 7 days ending 2026-10-26
    Then I get 2026-10-26 down to 2026-10-20, newest first, with 2026-10-24 manual at 1800 and the rest 2400 from the default

  Scenario: The weekly average mixes the old and new default day by day
    Given the default was 2900 until 2026-10-22 and is 3000 from 2026-10-23
    When I average the 7 days ending 2026-10-26
    Then the average is 2957.14

  Scenario: Manual days are part of the weekly average
    Given the default is 2400, 2026-10-21 is 3000 and 2026-10-24 is 1800
    When I average the 7 days ending 2026-10-26
    Then the average is 2400

  Scenario: Days with no calories at all are left out of the average
    Given only 2026-10-25 has calories, 2948.5
    When I average the 7 days ending 2026-10-26
    Then the average is 2948.5
    And with no calories on any of the 7 days there is no average

  Scenario: The calorie target uses the week's average, not a single day
    Given weights average 63.86 kg this week and 63.94 kg last week, ending 2026-10-23
    And the default is 3000 from 2026-10-01 with 2026-10-20 set to 2400
    When I ask for the calorie target
    Then it uses 2914.29 calories eaten per day

  Scenario: A first default that starts today still gives a target right away
    Given weights ending 2026-10-23 and no calories on any of those 7 days
    And the default is 2948.5 starting 2026-10-26
    When I ask for the calorie target
    Then it uses 2948.5 calories eaten per day

  Scenario Outline: A default must be valid
    When I set the default to <calories> with multiplier <multiplier> starting <date>
    Then it is rejected with "<message>"

    Examples:
      | calories | multiplier | date       | message                    |
      | 0        | 1          | 2026-10-26 | Calories must be above 0   |
      | 3000     | 0          | 2026-10-26 | Multiplier must be above 0 |
      | 3000     | 1          | 2026-02-30 | Date is not valid          |

  Scenario: What my weight says, against what I planned
    Given the weight averaged 82.0 kg this week and 82.5 kg the week before
    When I look at the balance
    Then I am actually in a deficit of 551 calories a day

  Scenario Outline: Within 100 calories a day counts as maintenance
    Given the weight changed by <change> kg between the two weeks
    Then the balance is "<balance>"

    Examples:
      | change | balance     |
      | -0.5   | deficit     |
      | -0.05  | maintenance |
      | 0      | maintenance |
      | 0.05   | maintenance |
      | 0.5    | surplus     |

  Scenario Outline: The planned mode comes from the multiplier
    Given the multiplier is <multiplier>
    Then the planned mode is "<mode>"

    Examples:
      | multiplier | mode     |
      | 0.85       | cut      |
      | 1          | maintain |
      | 1.1        | bulk     |
