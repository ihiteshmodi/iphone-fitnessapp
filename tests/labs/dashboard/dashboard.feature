Feature: Bloodwork dashboard
  As the owner
  I want one screen that sums up every system, heart risk, hormones and biological age
  So that I see how my results are doing without opening each marker

  Scenario: One tile per chapter with my results
    Given ferritin low and glucose optimal on my latest draws
    Then the Iron tile shows 1 outside and the Metabolic tile 1 optimal
    And each tile names its key marker with its trend

  Scenario: Heart risk shows the vault's heart markers I have
    Given an ApoB result
    Then the heart card lists ApoB with its reading, and Lp(a) as "not tested"

  Scenario: Hormones over time
    Given testosterone on three dates
    Then the hormone series lists those three values oldest first

  Scenario: Biological age from the latest complete draw
    Given my date of birth and a draw missing hs-CRP
    Then the card says hs-CRP is missing
