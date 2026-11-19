Feature: The Labs tab in Room for improvement
  As the owner
  I want my latest results turned into the vault's actions
  So that I know what to fix, what to work on and when to retest

  Scenario: A doctor line is a Fix item with the vault's urgency
    Given my latest ferritin is 1600 ng/mL and the vault's same-day line is above 1500
    Then the Labs tab shows "Same day: Ferritin" as Fix with the vault's text

  Scenario: Out of the optimal band shows the vault's actions for that direction
    Given my latest ferritin is 40 ng/mL (optimal 60-140)
    Then "Ferritin low" shows the low-side actions only
    And drug/TRT actions are hidden unless I switch them on (D5)

  Scenario: A pattern fires only when its numeric conditions hold
    Given the fixture pattern needs ferritin above 300 and TSAT above 45
    When ferritin is 350 and TSAT 50
    Then the pattern shows; with TSAT 30 it does not

  Scenario: Dismissing hides it until a newer result (D9)
    When I dismiss "Ferritin low"
    Then it is gone, and comes back after a new low result

  Scenario: Retest due
    Given my last glucose was 26 weeks ago and its routine retest is 26-52 weeks
    Then "Retest glucose" is a Tip
