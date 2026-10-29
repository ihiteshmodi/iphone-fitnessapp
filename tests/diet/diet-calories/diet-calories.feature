Feature: Calories per day come from the diet
  As the lifter I want the calorie target to use what the diet says I ate, with my typed days and my old default still working.

  Scenario: A day with a plan counts the diet
    Given a plan from 2026-10-26 worth 2800 calories and a default of 2500 from 2026-10-01
    When I ask what 2026-10-27 counts as
    Then it counts 2800 from the plan

  Scenario: A day typed by hand wins over the diet
    Given the same plan and default, and 2026-10-27 typed as 3100
    Then 2026-10-27 counts 3100 as typed
    And clearing it makes the day count the diet again

  Scenario: A day before any plan keeps the default
    Given the same plan and default
    Then 2026-10-25 counts 2500 from the default

  Scenario: Skipped items and extras change the day and are shown
    Given the same plan, with items worth 400 unticked on 2026-10-28 and extras worth 150 added
    Then 2026-10-28 counts 2550 from the plan with 1 item skipped and 1 extra

  Scenario: Extras are added to a default day too
    Given extras worth 150 on 2026-10-25, a day before the plan, with the default 2500
    Then 2026-10-25 counts 2650 from the default plus 1 extra

  Scenario: A future day counts the plan
    Given the plan from 2026-10-26
    Then 2026-11-10 counts the plan, with items that are off their cycle left out

  Scenario: The weekly average and the calorie target use the diet days
    Given weights averaging 64 kg this week and 64.2 kg last week ending 2026-10-29
    And the plan from 2026-10-26 worth 2800 calories and a default of 2500
    When I average the 7 days ending 2026-10-29
    Then it counts 4 plan days at 2800 and 3 default days at 2500, which averages 2671.43
    And the calorie target uses 2671.43 calories eaten per day

  Scenario: A day with neither a plan, a default nor a typed value has no calories
    Given no plan and no default
    Then the day has no calories
