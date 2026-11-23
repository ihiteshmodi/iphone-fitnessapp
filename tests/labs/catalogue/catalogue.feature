Feature: Clinical bloodwork catalogue
  As the app owner
  I want the bundled clinical catalogue to carry unified units, demographic strata, validity rules, co-tests, interventions, escalations, and pattern engines
  So that every bloodwork workflow runs off verified data with no course numbers hardcoded in Swift

  Scenario: Markers resolve by both slug and 02.XX.YY lesson ID and exclude panel overviews from logging
    Given the compiled labs catalogue
    When I look up a marker by its slug or its 02.XX.YY lesson ID
    Then both return the same marker
    And panel overview entries are marked isOverview with empty bands

  Scenario: Multiplicative, metric-scale, and affine unit conversions work out to default units
    Given a marker with an affine unit conversion (slope and offset)
    When I convert a value from that secondary unit to the default unit and back
    Then both conversions match the linear formula

  Scenario: Cholesterol, albumin, hormone, BUN, and mineral markers carry exact molecular or metric unit conversions
    Given the compiled labs catalogue
    When I convert HDL cholesterol from 1.55 mmol/L to mg/dL
    And I convert albumin from 45 g/L to g/dL
    And I convert free testosterone, DHEA-S, reverse T3, BUN, magnesium, zinc, and selenium from their molar units
    Then each converts to the marker's default unit using its exact molecular or metric factor

  Scenario: Markers with isoform-variable secondary units like Lp(a) read directly against native bands in that unit
    Given Lp(a) has native bands in both nmol/L and mg/dL without a fixed conversion factor
    When I read 28 mg/dL on Lp(a)
    Then it evaluates as optimal directly against the mg/dL bands without applying a multiplier
    And 40 mg/dL evaluates as high in the borderline elevated mg/dL band

  Scenario: Baseline panels, global protocols, and the 6 pattern engines decode completely
    Given the compiled labs catalogue
    Then baseline panels separate core, male, female, and conditional upgrades with per-marker draw notes
    And global protocols include draw-day checklists, fasting exemptions, emergency symptoms, BP, and CAC rules
    And all 6 multi-marker pattern engines decode with normalized ratio scales, phenotypes, stages, and what-not-to-do guardrails
