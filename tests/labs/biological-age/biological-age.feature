Feature: Biological age (PhenoAge) from one draw
  As the owner
  I want a blood-based biological age from a routine panel
  So that I see a summary next to the markers that drive it
  (Formula: Levine 2018, from the owner's research agent; labelled "Research (owner-approved)". The vault lists the
  inputs and says to keep the panel itself as the main tool.)

  Scenario: The research agent's worked example
    Given age 45, albumin 4.5 g/dL, creatinine 0.90 mg/dL, glucose 90 mg/dL, hs-CRP 1.0 mg/L, lymphocytes 30%,
      MCV 90 fL, RDW-CV 13%, ALP 70 U/L, WBC 6.0 x10^3/µL
    Then PhenoAge is 37.4 years and the 10-year mortality score is 1.50%

  Scenario: Only when all inputs come from the same draw
    Given a draw with everything except hs-CRP
    Then no PhenoAge is given, and hs-CRP is listed as missing

  Scenario: hs-CRP below the detection limit
    Given hs-CRP reported as "<0.3" mg/L
    Then 0.3/√2 mg/L is used and the result is marked as an estimate

  Scenario: Which markers pulled it up
    Then the dashboard lists each input with its own vault reading (the vault: "look at which markers pulled it up")
