Feature: Calories per day come from the diet
  As the lifter I want the calorie target to use what the diet says I ate, with my typed days and my old default still working.

  Scenario: A day with a plan counts what is ticked
    Given a plan from 2026-10-26 worth 2800 calories and a default of 2500 from 2026-10-01
    When I tick the whole plan on 2026-10-27 and ask what it counts as
    Then it counts 2800 from the plan

  Scenario: A plan day with nothing ticked counts zero, not the default
    Given the same plan and default
    Then 2026-10-27, with nothing ticked, counts 0 from the plan with 0 of 2 items ticked

  Scenario: A day typed by hand wins over the diet
    Given the same plan and default, the plan ticked on 2026-10-27, and 2026-10-27 typed as 3100
    Then 2026-10-27 counts 3100 as typed
    And clearing it makes the day count the diet again

  Scenario: A day before any plan keeps the default
    Given the same plan and default
    Then 2026-10-25 counts 2500 from the default

  Scenario: Only ticked items and extras count, and the day shows how many
    Given the same plan, with only the item worth 400 ticked on 2026-10-28 and extras worth 150 added
    Then 2026-10-28 counts 550 from the plan with 1 of 2 items ticked and 1 extra

  Scenario: Extras are added to a default day too
    Given extras worth 150 on 2026-10-25, a day before the plan, with the default 2500
    Then 2026-10-25 counts 2650 from the default plus 1 extra

  Scenario: A future day counts what is ticked, with items that are off their cycle left out
    Given the plan from 2026-10-26 and the meal ticked on the future day

  Scenario: The weekly average and the calorie target use the diet days
    Given weights averaging 64 kg this week and 64.2 kg last week ending 2026-10-29
    And the plan from 2026-10-26 worth 2800 calories, ticked on 2026-10-26 to 2026-10-29, and a default of 2500
    When I average the 7 days ending 2026-10-29
    Then it counts 4 plan days at 2800 and 3 default days at 2500, which averages 2671.43
    And the calorie target uses the 7 days ending the day before the latest weigh-in, 2026-10-22 to 2026-10-28,
    which is 3 plan days at 2800 and 4 default days at 2500, 2628.57 calories eaten per day

  Scenario: Food counts up to yesterday, so a morning weigh-in does not pull in today's empty day
    Given weigh-ins every day up to 2026-11-01
    And the plan worth 2800 ticked on 2026-10-26 to 2026-10-31, the default 2500 before it, and nothing ticked yet on 2026-11-01
    When I ask for the calorie target
    Then it uses 2026-10-25 to 2026-10-31: 1 default day at 2500 and 6 plan days at 2800, 2757.14 calories eaten per day
    And today's empty day is not counted as 0

  Scenario: A past diet day with nothing ticked and no extras is left out, not counted as 0
    Given the plan ticked on 2026-10-26, 2026-10-27 and 2026-10-29 but not on 2026-10-28
    When I average the 4 days ending 2026-10-29
    Then the average is 2800 from the 3 logged days

  Scenario: A diet day with only extras still counts
    Given the plan ticked on 2026-10-26, 2026-10-27 and 2026-10-29, and only extras worth 150 on 2026-10-28
    When I average the 4 days ending 2026-10-29
    Then the average is 2137.5

  Scenario: A day with neither a plan, a default nor a typed value has no calories
    Given no plan and no default
    Then the day has no calories
