Feature: Genotypes, read the vault's way
  As the owner (no genetic test yet)
  I want to pick each genotype from the vault's table once I test
  So that the vault's meaning, actions and extra blood tests follow, while the blood number still wins

  Scenario: Picking a genotype from the vault's table
    Given the vault's FUT2 table has "AA" (add MMA to the order)
    When I pick FUT2 AA
    Then FUT2 shows the vault's meaning and actions, and MMA is added to "From your genetics" in the order

  Scenario: Only genotypes from the table can be picked
    When I pick FUT2 "XY"
    Then I am told that genotype is not in the vault's table

  Scenario: A doctor-bucket genotype is a Fix item with its urgency
    Given G6PD deficient is "sameDay" in the vault
    When I pick it
    Then the Labs tab shows a Fix item with that urgency

  Scenario: Medical & lifestyle context (TRT/HRT, Rx classes, regular alcohol) starts unconfirmed, saves once, and stays editable
    Given a fresh database
    When I confirm my context as not on TRT today
    Then isContextConfirmed is true and onTRTOrHRT is false
    When I later start TRT and update onTRTOrHRT to true
    Then onTRTOrHRT is true

  Scenario: External specialty verifiers (HLA-DQ2/DQ8 tTG-IgA) order with nil markerID, while baseline/non-lab placeholders are skipped
    Given HLA-DQ2/DQ8 has external verifier "tTG-IgA / Total IgA" and ACTN3 has non-lab verifier "Actual Gym Performance"
    When I save HLA-DQ2.5 Positive and ACTN3 XX
    Then DrawPlanner orders "tTG-IgA / Total IgA" as an external test (never linking to tg-antibodies) and skips the non-lab gym verifier
    When I switch HLA to "HLA-DQ2 and HLA-DQ8 Negative"
    Then tTG-IgA is no longer ordered

  Scenario: FUT2 B12 marker shift, APOE e4 <=60 ApoB target, MTHFR/HFE/Factor V+TRT epistatic 2x2 rules
    Given FUT2 rs601338 AA, APOE e3/e4, MTHFR C677T TT, and Factor V Leiden Heterozygous
    When I read Serum B12 620 pg/mL, ApoB 72 mg/dL, Homocysteine 6.2 umol/L, and Hematocrit 53.5% with onTRTOrHRT = true
    Then Serum B12 carries the FUT2 false-reassurance shift note
    And ApoB 72 mg/dL is flagged high against the tightened <=60 mg/dL APOE e4 target
    And Homocysteine 6.2 umol/L notes that the MTHFR variant is phenotypically silent
    And Hematocrit 53.5% on TRT raises an urgent prescriber doctor line and epistatic thrombotic match

