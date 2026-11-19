Feature: More nutrients per food
  As the lifter I want amino acids, fat types, omega-3 and omega-6, alcohol, caffeine, vitamins and minerals per food,
  so the app can check rules like leucine per meal, trans fat and daily targets. Most of my diet is set up once.

  Scenario: A food keeps the extra nutrients it was given, and nothing else is required
    When I save "Soy chunks" per 100 g with 52 g protein, leucine 4.0 g and trans fat 0 g
    Then it has leucine 4.0 g and trans 0 g per 100 g
    And every other extra nutrient is unknown, not 0

  Scenario: Amounts follow the quantity and recipes add up their ingredients
    Given "Soy chunks" has leucine 4.0 g per 100 g and "Oats" has leucine 1.0 g per 100 g
    And the recipe "Bowl" makes 2 pieces from 50 g soy chunks and 100 g oats
    Then one piece of "Bowl" has leucine 1.5 g
    And when one ingredient has no leucine value, the recipe's leucine is marked incomplete

  Scenario: Alcohol counts 7 calories a gram
    When I save "Beer" per 100 ml with 4 g carbs and 3.9 g alcohol and no label calories
    Then 100 ml of "Beer" is 43.3 calories

  Scenario: The omega-3 form is kept for oils
    When I save "Algae oil" with EPA 150 mg, DHA 300 mg and form algae
    Then it shows form algae

  Scenario: Daily targets for the tracked nutrients
    Then leucine has a daily target of 2.9 g, fiber 28 g, vitamin D 20 mcg and omega-6 17 g

  Scenario: Approved values are applied from a file, by food name
    Given a values file with "Soy chunks,leucine,4.0" and "Soy chunks,omega3_form,algae" and "Unknown food,leucine,1"
    When I apply it
    Then "Soy chunks" has leucine 4.0 and omega-3 form algae, and existing values of other nutrients are kept
    And I am told 2 values were applied and "Unknown food" was not found

  Scenario: The day's nutrients against their daily targets
    Given today 100 g of "Soy chunks" (leucine 4.0 g, iron 9 mg) was eaten and its vitamin D is unknown
    Then leucine is 4.0 of 2.9 g, met
    And iron is 9 of 18 mg, 50 percent
    And vitamin D is unknown rather than 0
