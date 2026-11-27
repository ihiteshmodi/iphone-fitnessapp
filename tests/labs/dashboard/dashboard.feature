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

  Scenario: With no complete draw, the closest one is shown
    Given a 3 May draw with every PhenoAge input but hs-CRP, and a newer 1 Oct draw with only glucose
    Then the card names the 3 May draw and says only hs-CRP is missing

  Scenario: Tested markers dashboard uses strictly the latest value per marker across split draws and ignores superseded values
    Given Draw 1 (2025-09-27) had MPV 7.2 fL and Platelets 140000 per uL
    And Draw 2 (2026-05-03) updated MPV to 8.8 fL and Platelets to 203000 per uL
    And Draw 3 (2026-10-02, Lab A) logged Total Testosterone 445 ng/dL and Free Testosterone 10.5 pg/mL
    And Draw 4 (2026-10-02, Lab B) logged SHBG 58 nmol/L
    When the latest-per-marker snapshot and dashboard build
    Then older Draw 1 MPV/Platelets are ignored so "Low MPV + low platelets" does NOT fire
    And MPV + Platelets reports a clean companion check using the 2026-05-03 values
    And "High SHBG masking low Free Testosterone" fires across split Draws 3 and 4
    And every tested marker row carries its Core flag, exact range classification, latest date, and linked interpretations

  Scenario: Dashboard hub groups tested markers into compact system summaries with attention, optimal, and Core counts for drill-down
    Given tested markers across CBC (2 optimal) and Hormones (Total Testosterone in-lab-below-optimal, Free Testosterone low, SHBG high)
    When LabDashboardHubSummary builds from the latest snapshot
    Then totalTested is 5, optimalCount is 2, inLabSuboptimalCount is 1, outOfRangeCount is 2, and activeInterpretationCount >= 1
    And chapterSummaries orders chapters with attention items first ("Hormones" before "CBC") with exact per-chapter counts and rows for drill-down
