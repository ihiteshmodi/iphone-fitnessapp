Feature: Cook a recipe for a different amount, and make a recipe from another one
  As the lifter I keep recipes in the app and cook them in real life, sometimes for more or fewer pieces,
  and some recipes are a variation of another (a soybean shake is part of the maintenance shake).

  Scenario: Cook for a different number of pieces, view only
    Given "Kokki" makes 11 pieces from 550 g wheat flour and 99 g onion
    When I cook it for 5 pieces
    Then it needs 250 g wheat flour and 45 g onion
    And the saved recipe still makes 11 pieces from 550 g and 99 g

  Scenario: Cook for must be above 0
    When I cook it for 0 pieces
    Then I am told "Cook for an amount above 0"

  Scenario: Duplicate a recipe as a new one
    Given "Maintenance shake" has soybeans, ashwagandha, gokhru, brahmi and milk powder
    When I duplicate it as "Soybean shake"
    Then "Soybean shake" has the same ingredients, amounts and makes
    And removing milk powder from "Soybean shake" leaves "Maintenance shake" unchanged

  Scenario: The copy needs a name of its own
    When I duplicate it as "maintenance shake"
    Then I am told "A food with that name already exists"
