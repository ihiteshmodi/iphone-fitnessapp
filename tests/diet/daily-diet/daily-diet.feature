Feature: What I ate on a day
  As the lifter I want each day added up from my plan and from the extras I had, and compared with my protein and fat rules.

  Background:
    Given a plan from 2026-10-01 with Oats 50 g (200 calories, protein 7, carbs 30, fat 4), Shake 1 unit (800 calories, protein 60, carbs 90, fat 12) and a Supplement 1 capsule (0 calories)

  Scenario: The plan counts as eaten
    When I look at 2026-10-05
    Then the day has 1000 calories, protein 67, carbs 120, fat 16
    And every item is eaten

  Scenario: Unticking an item removes it for that day only
    When I untick Shake on 2026-10-05
    Then 2026-10-05 has 200 calories
    And 2026-10-06 still has 1000
    And ticking it again brings 2026-10-05 back to 1000

  Scenario: An item that is off its cycle is left out without a tick
    Given the Supplement is 1 week on and 1 week off from Monday 2026-10-05
    When I look at 2026-10-12
    Then the Supplement is off and is back on 2026-10-19
    And it adds nothing to the calories or the cost

  Scenario: Extras are added on top of the plan
    Given "Tea biscuits" is a 250 g pack of 35 pieces, 480 calories per 100 g
    When I add 4 pieces on 2026-10-05
    Then the day has 1137.1 calories
    And the extras are listed with their amount and nutrition

  Scenario: An extra can be changed or removed
    Given 4 pieces of "Tea biscuits" were added on 2026-10-05
    When I change it to 2 pieces
    Then the extra is 14.29 g
    And removing it takes the day back to 1000

  Scenario: Cost adds up the eaten items and the extras
    Given Oats cost 5 for 50 g, Shake 60 a unit, the Supplement 2 a capsule and the extra 3
    Then 2026-10-05 costs 70 with the extra, and 67 without it

  Scenario: Editing a food recalculates the days that used it
    Given 2026-10-05 was 1000 calories
    When the calories of Oats are corrected to 300 per 50 g
    Then 2026-10-05 has 1100 calories

  Scenario: Protein is a minimum
    Given the protein minimum is 60 g
    Then a day with protein 67 meets it
    And unticking Shake leaves protein 7 which is under it

  Scenario: The fat limit is the smaller of a share of the calories and the weight cap
    Given the fat share is 20 percent and the weight cap is 0.4 g per lb
    And the 7-day average weight is 64 kg
    Then the cap is 56.3 g (64 x 2.2 x 0.4)
    And for 1000 calories the share is 22.2 g so the limit is 22.2 g
    And for 3000 calories the share is 66.7 g so the limit is the cap, 56.3 g

  Scenario: Fat over the limit is flagged
    Given the limit is 20 g
    Then fat 16 is within it and fat 24 is over it

  Scenario: With no weigh-ins there is only the share of calories
    Given no weight has been logged
    Then the fat limit is the share of the day's calories

  Scenario: Days with no plan can still have extras
    When I add 4 pieces of "Tea biscuits" on 2026-09-20, before the plan
    Then 2026-09-20 has no plan items and its extras add 137.1 calories

  Scenario: Extras over a week
    Given extras on 2026-10-05 of 137 calories costing 3 and on 2026-10-07 of 100 calories costing 2
    When I total the extras for the 7 days ending 2026-10-08
    Then it is 2 days, 237 calories, cost 5

  Scenario: A food with no price shows an unknown cost, not zero
    Given a food has no price
    Then the day's cost is shown as incomplete
