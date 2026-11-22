Feature: Read a result the vault's way
  As the owner
  I want each result placed on the vault's bands, with its doctor lines checked
  So that I see where I stand without the app inventing a single number

  Background:
    Given a fixture marker "Ferritin" in ng/mL with:
      | band    | kind    | low | high | sex    | dispute |
      | Lab     | lab     | 30  | 400  | any    |         |
      | Optimal | optimal | 60  | 140  | male   | C900    |
      | Optimal | optimal | 80  | 150  | male   | C900    |
      | Women   | optimal | 40  | 100  | female |         |
    And doctor lines "above 900 soon" and "above 1500 same day"

  Scenario: Inside every optimal band
    When I read 100 ng/mL for a man
    Then it is optimal

  Scenario: In the gap between two disputed bands (D1)
    When I read 70 ng/mL for a man
    Then it is disputed, with both bands and their dispute ID, and no flag

  Scenario: Outside the optimal bands
    When I read 50 ng/mL for a man
    Then it is low; at 160 it is high

  Scenario: On a shared edge (D3)
    Given bands "Watch 20-25" and "Flag 25-40" on another marker
    When I read exactly 25
    Then both band names are shown

  Scenario: Doctor lines, most urgent first (D2)
    When I read 1600 ng/mL
    Then both doctor lines are crossed and "Same day" comes first

  Scenario: Other units convert only by the catalogue's factor
    When I read 100 µg/L (factor 1)
    Then it reads like 100 ng/mL
    And a band with no unit is never compared (D4)

  Scenario: Female bands are ignored for a man
    When I read 45 ng/mL for a man
    Then the women's band is not used

  Scenario: Adjacent undisputed optimal sub-bands union cleanly without false disputed flags
    Given ALT has undisputed optimal bands "< 17 U/L (Excellent)" and "17-25 U/L (Normal-optimal)"
    When I read 14 U/L and 21 U/L
    Then both read as optimal rather than disputed

  Scenario: Demographic stratum selector picks matching age bracket and assay
    Given a marker with age-bracketed strata (20-29, 30-39, 40-49) and an LC-MS/MS stratum
    When a 34-year-old man reads a result on draw day
    Then the 30-39 stratum is selected with its optimal bounds and severity tier

  Scenario: Qualitative dipsticks, titers, lab ULN multiples, paired blood pressure, and conditional doctor lines
    When Urine Nitrites is "Negative" and "Positive", ANA is "1:80", RF is 45 with lab high 14, and Blood Pressure is 124 / 84 mmHg
    Then Nitrites reads optimal then high, ANA reads watchHigh, RF reads high (> 3x ULN), and BP reads Stage 1 hypertension (from diastolic 84)

  Scenario: Visual range bar maps numeric bands and pin position across two-sided and one-sided markers
    When Ferritin (lab 30-400, optimal 60-150 ng/mL) is read at 92 ng/mL and ApoB (optimal <= 70 mg/dL) is read at 95 mg/dL
    Then Ferritin builds a 5-segment range bar (Low, Normal, Optimal, Normal, High) with the You pin inside the Optimal segment
    And ApoB builds a zero-floored range bar starting with Optimal <= 70 mg/dL and places the You pin in the elevated zone
    And qualitative dipstick markers return no numeric range bar

