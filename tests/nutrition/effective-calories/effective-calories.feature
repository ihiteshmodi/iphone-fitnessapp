Feature: Effective calories
  As the lifter on a protein-heavy diet I know digestion uses part of what I eat (protein 20-30 %, carbs 5-10 %, fat 0-3 %).
  I want to see total and effective calories side by side, and choose which one my targets use.

  Background:
    Given digestion costs 25 % of protein calories, 7.5 % of carb calories, 1.5 % of fat calories and 0 % of alcohol calories

  Scenario: Digestion cost of a day, by macro
    Given a day of 207 g protein, 392 g carbs, 49 g fat and no alcohol
    Then digestion costs 207 for protein, 117.6 for carbs, 6.6 for fat and 0 for alcohol, 331.2 in all
    And 2839 calories are 2507.8 effective

  Scenario: The weekly average of effective calories uses each day's own macros
    Given two diet days, one of 2800 calories from 200 g protein and one of 2400 calories from carbs only
    Then the effective average is the mean of each day's effective calories

  Scenario: Days with only a typed total use the share of the days with macros
    Given one diet day that is 12 % digestion and one typed day of 3000 calories
    Then the typed day counts 2640 effective

  Scenario: Targets can follow effective calories
    When I choose effective calories for targets
    Then the choice is kept, and maintenance and the new target are shown in effective calories
