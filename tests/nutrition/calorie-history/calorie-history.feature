Feature: Calorie history
  As the lifter I want to open any past day and see what the calorie maths said on that day
  so that I can check whether I was in a surplus or deficit, and what my cutting calories were, back then.

  Background:
    Given weigh-ins every day from 2026-11-01 to 2026-11-20
    And they are 65.0 kg up to 2026-11-10 and 64.8 kg from 2026-11-11
    And a default of 2600 calories with multiplier 1 from 2026-10-01

  Scenario: A past day uses only the data up to that day
    When I look at 2026-11-17
    Then the latest weigh-in it uses is 2026-11-17
    And the averages are 64.8 kg for 2026-11-11 to 2026-11-17 and 65.0 kg for 2026-11-04 to 2026-11-10
    And calories eaten are the 7 days ending 2026-11-16
    And weigh-ins and calories after 2026-11-17 are ignored

  Scenario: Food typed after that day does not change it
    Given 2026-11-18 is set to 4000 calories
    When I look at 2026-11-17
    Then calories eaten are 2600 per day

  Scenario: The goal multiplier is the one in force on that day
    Given the default changes to 2400 with multiplier 0.8 from 2026-11-19
    When I look at 2026-11-17
    Then the multiplier is 1 and there are no cutting macros
    And looking at 2026-11-20 uses multiplier 0.8

  Scenario: A day with no weigh-in uses the latest weigh-in before it
    Given there is no weigh-in on 2026-11-20
    When I look at 2026-11-21
    Then the latest weigh-in it uses is 2026-11-19

  Scenario: Too far back to have two weeks of weigh-ins
    When I look at 2026-11-05
    Then I am told "Log body weight for both of the last two weeks"
