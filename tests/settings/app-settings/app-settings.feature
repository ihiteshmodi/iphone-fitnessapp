Feature: App settings
  As the lifter I want each setting to do exactly one job
  so that changing deload does not change my progress history, and the other way round.

  Scenario: Deload settings only affect workout targets
    Given deload is on with weight multiplier 1 and reps multiplier 0.75
    When I change the reps multiplier to 0.6
    Then the minimum reps on every day change
    And progress charts and the calorie target are unchanged

  Scenario: History start date is separate and affects every progress view
    Given the history start date is 2026-08-31
    When I change it to 2026-06-01
    Then working weights, trends, volume charts and recommendations include sets from 2026-06-01
    And deload settings are unchanged

  Scenario: Invalid history start date
    When I set the history start date to 2027-02-30
    Then it is rejected with "Date is not valid"

  Scenario: Switch deload on and off
    When I toggle deload on
    Then Day screens show deload targets without recommendations
    When I toggle deload off
    Then Day screens show normal targets with recommendations
