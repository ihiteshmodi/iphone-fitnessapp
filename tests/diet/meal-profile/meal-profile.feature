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
