Feature: Notes, times and quick add for extras
  As the lifter I eat extras at different times of day, often without a label.
  I want to note when and what each extra was, and log unlabelled food quickly by weight or by calories.

  Scenario: An extra keeps a time, a name and a note
    When I add 4 Oreo biscuits on 2026-11-19 at Evening with the note "office"
    Then the extra shows Evening and "office"
    And I can change it later to Night with no note

  Scenario: Extras are grouped by time of day
    Given extras on 2026-11-19 at Evening, Morning, with no time, and Noon
    Then they are listed Morning, Noon, Evening, then the ones with no time

  Scenario: Quick add by weight from a preset
    Given "Extra calorie batches" is 12.7 g carbs and 5.5 g fat per batch (70/30 by grams), and one batch stands for 20 g of food
    When I quick-add "Kaju katli", 30 g, at Evening
    Then the extra is named "Kaju katli", is 3 batches and counts 300.3 calories (100.1 per batch) with 23.1 g carbs and 23.1 g fat

  Scenario: Quick add by weight needs a preset
    When I quick-add 30 g using a food that does not say how many grams one unit stands for
    Then I am told "Oats is not set up for quick add by weight"

  Scenario: Quick add calories only
    When I quick-add "Pani puri" at 300 calories
    Then the extra is named "Pani puri" and counts 300 calories with no protein, carbs or fat

  Scenario: Upgrading turns the 91-calorie batch into a 100-calorie batch
    Given a version 10 database where "Extra calorie batches" is 7 g carbs and 7 g fat per unit
    When it is opened
    Then it is 7.7 g carbs and 7.7 g fat, one batch stands for 10 g, and every day it was used counts 100 per batch
    But a batch I had already changed to other values is left as it is

  # Changed 19 Nov 2026: outside snacks and sweets are mostly carbs
  Scenario: Upgrading makes the batch 70% carbs and 30% fat by grams
    Given a version 18 database where "Extra calorie batches" is 7.7 g carbs, 7.7 g fat and 10 g of food per unit
    When the app opens it
    Then a batch is 12.7 g carbs and 5.5 g fat (about 100 kcal) and stands for 20 g of food
    And every day it was logged on is recounted
    And a batch the owner changed by hand is left as it is
