Feature: Filter markers in the bloodwork catalogue
  As the owner browsing 80+ markers across chapters
  I want quick filter chips and a custom multi-criteria filter
  So that I can immediately see pending Core tests, completed Core or non-Core markers, or markers by Optimal/High/Low status

  Background:
    Given Core markers "Ferritin" (logged 40 ng/mL, Low), "Glucose" (logged 82 mg/dL, Optimal), and "ApoB" (never tested)
    And Non-Core markers "MPV" (logged 12.1 fL, High), "Zinc" (never tested), and an overview article "Start Here Guide"

  Scenario: Quick filter chips narrow markers accurately with counts
    When I select "★ Core · Not done"
    Then only "ApoB" is shown
    When I select "★ Core · Done"
    Then "Ferritin" and "Glucose" are shown
    When I select "Non-Core · Done"
    Then only "MPV" is shown
    When I select "Non-Core · Not done"
    Then only "Zinc" is shown (excluding non-testable overview articles)
    When I select "Optimal", "Low", or "High"
    Then only "Glucose", "Ferritin", or "MPV" is shown respectively

  Scenario: Custom filter combines Tier, Completion, Reading Status, and Chapter
    When I apply a custom filter with Tier = Core and Reading = Low
    Then only "Ferritin" matches and empty chapters are hidden
    When I also restrict Chapter to "Metabolic"
    Then 0 markers match