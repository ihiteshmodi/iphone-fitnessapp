Feature: Nutrition settings and corrections
  As the lifter I want to change the macro rules and fix wrong entries
  so that the calorie advice matches how I eat.

  Scenario: Change the protein rule
    Given protein is 1.2 g per lb of body weight
    When I set protein to 1.0 g per lb
    Then cutting macros at 63.86 kg use 140.49 g protein

  Scenario: Change the fat share
    Given fat is 25% of calories
    When I set fat to 30%
    Then cutting macros at 2429 calories use 80.97 g fat

  Scenario: Protein and fat must leave room for carbs
    When I set fat to 95%
    Then it is rejected with "Fat share must be between 10% and 60%"

  Scenario: Correct a typo in body weight
    Given 2022-09-22 was logged as 6.95 kg
    When I edit that entry to 69.5 kg
    Then the entry shows 69.5 kg

  Scenario: Delete a wrong weigh-in
    When I delete the weigh-in
    Then the 7-day averages are recalculated without it

  Scenario: Edit calories eaten for a day
    Given I logged 2948.5 calories on 2026-10-23
    When I change it to 3100
    Then the calorie target uses 3100
