Feature: Look up and correct everything logged on one past day
  As the lifter I sometimes notice a wrong number from weeks ago. I want to pick that date and see, in one place,
  the sets, weigh-in, calories and measurements of that day so I can fix them.

  Scenario: Everything logged on a day
    Given on 2026-10-10 I logged "Leg Extension" 55 kg × 10, "Leg Curl" 40 kg × 12, a weigh-in of 82.3 kg and a Waist reading of 30.2 in
    And on 2026-10-11 I logged a weigh-in of 82.0 kg
    When I open 2026-10-10
    Then I see both sets, the 82.3 kg weigh-in and the Waist reading, and nothing from 2026-10-11

  Scenario: A day with nothing logged
    When I open 2026-10-12
    Then there are no sets, weigh-ins or readings, and calories come from the default if one applies

  Scenario: Two weigh-ins on the same day are both listed
    Given I logged 82.3 kg and 82.1 kg on 2026-10-10
    When I open 2026-10-10
    Then both weigh-ins are listed so either can be fixed
