Feature: Items that follow a cycle
  As the lifter I take some supplements for a few weeks, stop for a while and start again, so the plan must know which days an item is on.

  Scenario: An item with no cycle is on every day
    Then it is on 2026-10-26 and on 2027-03-01

  Scenario: Weeks on and weeks off count from the Monday the first on week begins
    Given the cycle is 2 weeks on and 1 week off, first on week starting Monday 2026-10-26
    Then 2026-10-26 to 2026-11-08 are on, day 1 to 14
    And 2026-11-09 to 2026-11-15 are off
    And 2026-11-16 to 2026-11-29 are on again
    And 2026-10-19 to 2026-10-25, the week before the start, is off because the cycle repeats backwards too

  Scenario: The day of the cycle and the next change are known
    Given the same cycle
    When I look at 2026-10-29
    Then it is on, day 4 of 14, and the item goes off on 2026-11-09
    And on 2026-11-12 it is off and comes back on 2026-11-16

  Scenario: Days on and days off count from any date
    Given the cycle is 5 days on and 2 days off starting 2026-10-26
    Then 2026-10-26 to 2026-10-30 are on and 2026-10-31 to 2026-11-01 are off
    And 2026-11-02 is on again

  Scenario: Chosen weekdays
    Given the item is on Monday, Wednesday and Friday
    Then 2026-10-26 is on and 2026-10-27 is off and 2026-10-30 is on

  Scenario Outline: Quick patterns are chosen weekdays
    Given the quick pattern <pattern>
    Then it is on for the weekdays <weekdays>

    Examples:
      | pattern     | weekdays             |
      | Weekdays    | Monday to Friday     |
      | Weekends    | Saturday and Sunday  |

  Scenario: Every other day is one day on and one day off
    Given the cycle is 1 day on and 1 day off starting 2026-10-26
    Then 2026-10-26 is on and 2026-10-27 is off and 2026-10-28 is on

  Scenario: Training days follow the weekdays of the workout plan
    Given the workout plan trains on Monday, Wednesday and Friday
    And the item is on training days
    Then 2026-10-26 is on and 2026-10-27 is off

  Scenario: Training days with no workout weekdays set are on every day
    Given no workout day has a weekday
    And the item is on training days
    Then every day is on

  Scenario Outline: A cycle must be valid
    When I save a cycle of <kind> with <detail>
    Then it is rejected with "<message>"

    Examples:
      | kind     | detail                          | message                              |
      | weeks    | 0 weeks on                      | Days or weeks on must be at least 1  |
      | weeks    | 1 week off starting a Tuesday   | A weekly cycle starts on a Monday    |
      | days     | 0 days off                      | Days or weeks off must be at least 1 |
      | weekdays | no day chosen                   | Choose at least one weekday          |

  Scenario Outline: A cycle is described in plain words
    Given the cycle <cycle>
    Then it reads "<summary>"

    Examples:
      | cycle                                | summary                  |
      | every day                            | Every day                |
      | 2 weeks on and 1 week off            | 2 weeks on · 1 week off  |
      | 1 week on and 1 week off             | 1 week on · 1 week off   |
      | 5 days on and 2 days off             | 5 days on · 2 days off   |
      | 1 day on and 1 day off               | Every other day          |
      | Monday, Wednesday and Friday         | Mon, Wed, Fri            |
      | Monday to Friday                     | Weekdays                 |
      | Saturday and Sunday                  | Weekends                 |
      | training days                        | Training days            |

  Scenario: Where the item is today in words
    Given the cycle is 2 weeks on and 1 week off, first on week starting Monday 2026-10-26
    Then on 2026-10-29 it reads "Day 4 of 14 · off from 9 Nov"
    And on 2026-11-12 it reads "Off · back on 16 Nov"

  Scenario: A calendar strip shows which days are on
    Given the same cycle
    When I draw 4 weeks from the week of 2026-10-26 with today 2026-10-29
    Then the rows start on Mondays, the third row is all off and 2026-10-29 is marked as today

  Scenario: Picking the cycle in the editor
    When I choose weeks on and off with the date 2026-10-28, a Wednesday
    Then the first on week starts on Monday 2026-10-26
    And the preset 2 on and 1 off fills in 2 weeks on and 1 week off
    And switching to weekdays and choosing none is rejected with "Choose at least one weekday"
