Feature: Export my bloodwork for an AI review
  As the owner
  I want every draw, reading and open item in one file
  So that an agent that knows the vault can review my labs and suggest what the app misses

  Scenario: Each draw lists its results read against the vault
    Given a 3 May 2026 draw, fasted 12 h, with ferritin 40 ng/mL (lab range 30-400) and A 10, B 4 giving C 6
    Then the export has "## 3 May 2026", "fasted 12 h", "Ferritin: 40 ng/mL, low (lab range 30–400)" and "C: 6 u (calculated)"

  Scenario: Biological age and open items
    Given my date of birth is set and no draw has hs-CRP
    Then the export says which PhenoAge inputs are missing
    And lists the open lab items by title
