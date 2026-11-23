Feature: Meal glycemic load, per-meal amino acid profile, and food contributor drill-down
  As the lifter eating two main protein meals (Brunch and Dinner) plus supplement-only slots (Morning and During workout)
  I want amino acids and glycemic load checked per real meal — with food-level contributors sorted highest to lowest — and excluded from whole-day targets
  So that I can see whether each meal hits its amino acid thresholds, what drives its glycemic load, and which foods supply each nutrient

  Scenario: Glycemic index on foods and recipes calculates glycemic load from net digestible carbs
    Given Rolled Oats (GI 55, carbs 68.5 g, fiber 10 g per 100 g) and Maltodextrin (GI 105, carbs 95 g, fiber 0 g per 100 g)
    And a Shake recipe using 30 g Rolled Oats and 30 g Maltodextrin
    When Glycemic Load is calculated for 1 Shake
    Then Rolled Oats contributes 9.6525 GL and Maltodextrin contributes 29.925 GL (total 39.5775 GL, High)

  Scenario: Real meals show Meal Profile while supplement/electrolyte slots do not, and Daily Targets omits amino acids
    Given Morning has only Psyllium Husk (supplement) and During workout has Himalayan Salt + Potassium Chloride
    And Brunch has 1 Shake plus Soy Chunks
    When viewing the day's meals and Daily Targets
    Then Morning and During workout have isRealMeal = false while Brunch has isRealMeal = true
    And DailyTargetReport.dailyRows excludes amino acids and shows 0 instead of nil for missing vitamins/minerals

  Scenario: Tapping an amino acid or glycemic load inside a meal lists contributing foods sorted descending with grams and percent share
    Given Brunch has 1 Shake (containing 150 g Soy Chunks and 30 g Rolled Oats) plus 2.5 g DL-Methionine
    When I inspect Leucine and Glycemic Load contributors for Brunch
    Then Leucine contributors are sorted highest to lowest with exact grams and percentages summing to ~100%
    And Glycemic Load contributors list Maltodextrin first and Rolled Oats second with GL points and percentages

  Scenario: Tapping any nutrient or fiber on Daily Targets lists meal and extra contributors sorted descending with dual Vitamin D units
    Given Brunch has Becadexamine (10 mcg Vitamin D) and Nutrija D3+K2 (5000 IU Vitamin D3) plus 1 Shake, and an Extra adds 50 g Rolled Oats
    When I inspect whole-day Daily Targets contributors
    Then Vitamin D totals 135 mcg (5,400 IU) with Nutrija D3+K2 listed first (125 mcg, 5,000 IU) and Becadexamine second (10 mcg, 400 IU)
    And Fiber contributors include Soy Chunks, Extra Rolled Oats, and Brunch Rolled Oats in descending order

  Scenario: Inspecting a recipe shows its Glycemic Load, per-meal Amino Acids, and Daily Target nutrients with ingredient contributors
    Given Maintenance Shake combines 150 g Soy Chunks, 30 g Rolled Oats, and 30 g Maltodextrin
    When I evaluate the recipe profile for 1 unit
    Then it reports 44.0775 GL, per-meal amino acid rows, and daily target rows with ingredient contributors sorted descending

  Scenario: Diet Plan evaluates planned whole-day targets and full planned meal profiles even when only part of today was ticked
    Given Brunch plans 1 Shake and 2.5 g DL-Methionine, and Dinner plans 100 g Soy Chunks, while only DL-Methionine is ticked so far today
    When I inspect Planned Daily Targets and Brunch's planned Meal Profile in Diet Plan
    Then Planned Daily Targets sums both Brunch and Dinner active items
    And Brunch's planned Meal Profile includes both the Shake and DL-Methionine rather than only the ticked item
