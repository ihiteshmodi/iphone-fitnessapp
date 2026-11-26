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

  Scenario: Nutrient-swap genes flag logged synthetic folic acid or iron supplements and stay quiet when diet is clean
    Given the user saved MTHFR C677T TT and HFE C282Y/H63D Compound Heterozygous
    When their active diet plan includes a Folic Acid supplement and an Iron supplement
    Then LabInsightsRule flags swapping folic acid to L-5-MTHF and stopping supplemental iron
    When those supplements are removed from the diet plan and homocysteine is optimal
    Then no nutrient-swap supplement collision alerts fire

  Scenario: Change-nothing genes stay silent on clean diets but flag forbidden genotype-chasing stacks
    Given the user saved VDR FokI FF, ACTN3 XX, and GSTM1 Null
    When their diet plan has no forbidden detox or megadose Vitamin D supplements
    Then LabInsightsRule emits zero genotype-driven supplement or training alerts for those change-nothing genes
    When they add an NAC detox supplement to their diet plan
    Then LabInsightsRule flags the GSTM1 Change-Nothing Mandate guardrail against detox stacks

  Scenario: Priority-shift and marker-shift genes flag caffeine, lactose, and APOE e4 ApoB or referral rules
    Given the user saved CYP1A2 rs762551 CC slow metabolizer, LCT/MCM6 CC, and APOE e3/e4
    When their diet plan has 300 mg daily caffeine and Whey Concentrate plus ApoB 72 mg/dL
    Then LabInsightsRule flags the CYP1A2 200 mg morning caffeine cap, LCT lactose swap, APOE e4 ApoB high, and APOE genetic-counselor note

  Scenario: Hard contraindication genes surface G6PD, Factor V + TRT, and CYP2D6/2C19 medication stop-lines and export to markdown
    Given the user saved G6PD Class II/III Deficiency, Factor V Leiden Heterozygous on TRT, and CYP2D6 Ultrarapid on SSRIs with St John's Wort
    When LabInsightsRule and LabsReviewService run
    Then LabInsightsRule surfaces fix-level red-line alerts for G6PD, Factor V on TRT, and CYP2D6 Rx/St John's Wort collision
    And the exported labs-review markdown includes Active genetic modifiers, clinical context, and genotype-adjusted draw readings

  Scenario: GeneticsPresenter builds 5 clinical category groups, TRT/Rx context summary, and rich GeneDetailViewModel sections
    Given a catalogue with genes across all 5 action categories and unconfirmed clinical context
    When GeneticsPresenter builds the screen view model
    Then needsContextPrompt is true and the 5 category sections appear in clinical priority order
    When the user confirms TRT on and CPIC medication active and picks Factor V Leiden Heterozygous and HLA-DQ2.5 Positive
    Then needsContextPrompt is false, contextSummary shows TRT/HRT On and CYP2D6/CYP2C19 medication, and GeneDetailViewModel exposes external verifiers, form swaps, and safety stop-lines

  Scenario: All 7 dynamic reverse triggers recommend conditional genetic tests when unlogged and stay silent when clean, logged, or toggled off
    Given Reverse Genetics is enabled by default and zero genotypes are logged
    When iron overload labs (Ferritin 340, TSAT 48%, hs-CRP 0.8), masked B12 labs (B12 650, MMA 0.35), malabsorption labs (Ferritin 18, B12 240, Folate 3.1), TRT with Hematocrit 51.5%, CPIC Rx, oxidative therapy, and post-rechallenge lactose symptoms are present
    Then Reverse Genetics recommends HFE, FUT2, HLA-DQ2/DQ8 (with gluten guardrail), Factor V/F2, CYP2D6/2C19, G6PD (with 2-3 month hemolysis assay delay warning), and LCT/MCM6
    And G6PD, CYP2D6/2C19, Factor V/F2, and HLA-DQ2/DQ8 carry Clinical-Grade vs DTC microarray warnings
    And labs-review markdown exports "# Conditional Genetic Tests Warranted"
    When HFE is logged or Reverse Genetics is switched OFF
    Then the corresponding reverse recommendation disappears immediately

  Scenario: Zero reverse triggers ever fire for 07.04.* change-nothing genes and Tier 1 badges warn Do Not Buy
    Given unlogged 07.04.* genes (VDR, LPA gene, ACTN3/ACE, GSTM1/GSTT1, SOD2, Salt Sensitivity)
    When bloodwork has low 25(OH)D (14 ng/mL), high Lp(a) (210 nmol/L), and elevated ALT (88 U/L)
    Then zero reverse genetic recommendations fire for any 07.04.* gene
    And GeneticsPresenter badges all 07.04.* genes as "Skip / Do Not Buy — Test Phenotype Directly"

  Scenario: Marker detail range bar shifts optimal bounds and shows Standard vs Gene-Adjusted target for MTHFR and APOE e4
    Given MTHFR C677T TT and APOE e3/e4 are logged
    When LabRangeBarModel builds for Homocysteine (standard <= 8 umol/L) and ApoB (standard <= 80 mg/dL)
    Then Homocysteine shows Standard optimal <= 8 -> MTHFR target < 7 umol/L and ApoB shows Standard optimal <= 80 -> APOE e4 target <= 60 mg/dL



