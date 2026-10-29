Feature: A library of foods and recipes
  As the lifter I keep every food I use, with its nutrition and price, so the diet can be added up for me.

  Scenario: Nutrition is stored per a base quantity and scaled to what I eat
    Given "Rolled oats" is a food with nutrition per 100 g: protein 12, carbs 68, fat 8, fiber 10
    When I ask what 30 g of it gives
    Then it gives protein 3.6, carbs 20.4, fat 2.4, fiber 3 and 111.6 calories

  Scenario: Calories come from the label when typed, otherwise from the macros
    Given a food per 100 g with protein 10, carbs 60, fat 5
    Then its calories are 325 (4 x 10 + 4 x 60 + 9 x 5)
    And when the label says 340 calories, 340 is used instead

  Scenario: Cost comes from the pack price
    Given a food with a 500 g pack that costs 80
    When I ask what 30 g costs
    Then it costs 4.8
    And a food with no price costs nothing

  Scenario: A recipe is worked out from its ingredients
    Given the recipe "Flatbread" makes 2 pieces from 40 g of "Flour" and 10 g of "Seeds"
    And "Flour" is 350 calories and 10 in price per 100 g, "Seeds" is 500 calories and 30 in price per 100 g
    When I ask what 1 piece of "Flatbread" gives and costs
    Then it gives 95 calories and costs 3.5

  Scenario: Editing an ingredient changes every recipe that uses it
    Given the recipe above
    When the price of "Flour" goes from 10 to 20 per 100 g
    Then 1 piece of "Flatbread" costs 5.5

  Scenario: A recipe can be a whole batch measured in grams
    Given the recipe "House sauce" makes 1000 g from its ingredients, 500 calories in all
    When I ask what 40 g of it gives
    Then it gives 20 calories

  Scenario: A recipe cannot contain itself, directly or through another recipe
    When I add "Flatbread" as an ingredient of "Flatbread"
    Then it is rejected with "A recipe cannot contain itself"
    And adding a recipe that already contains "Flatbread" to "Flatbread" is rejected the same way

  Scenario: Names are unique, ignoring case
    Given a food "Rolled oats"
    When I add "rolled OATS"
    Then it is rejected with "A food with that name already exists"

  Scenario: A food used by a recipe, a plan or a logged day cannot be deleted
    Given "Flour" is an ingredient of "Flatbread"
    When I delete "Flour"
    Then it is rejected with "Flour is used by a recipe, a plan or a logged day"

  Scenario: Foods can be searched and filtered by kind
    Given foods of kinds food, supplement and recipe
    When I search for "oat"
    Then I get the matching foods, recipes included, in name order
    And filtering by the kind supplement returns only supplements

  Scenario Outline: A food must be valid
    When I save a food with <field> <value>
    Then it is rejected with "<message>"

    Examples:
      | field         | value | message                                  |
      | name          | empty | Give the food a name                     |
      | base quantity | 0     | Nutrition must be per a quantity above 0 |
      | protein       | -1    | Nutrition cannot be negative             |
      | price         | -5    | Price cannot be negative                 |
