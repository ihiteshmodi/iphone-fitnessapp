Feature: Multi-marker ratios, clinical composites, discordance alerts, and 6 pattern engines
  As the owner reading a blood draw as a connected biological system
  I want same-draw ratios, CAC/BP composites, discordance rules, qualitative mini-patterns, and the 6 clinical pattern engines evaluated with my logged diet/training context
  So that root-cause phenotypes, stages, look-alikes, and masked findings surface accurately without mixing stale draws

  Scenario: ANC/ALC derive from WBC + %, feeding NLR, and Cortisol:DHEA-S calculates automatically
    Given a draw with WBC 6.0 x10^3/uL, Neutrophil % 60, Lymphocyte % 30, Cortisol 18 ug/dL, and DHEA-S 200 ug/dL
    When LabDrawService reads the draw's results
    Then NLR calculates as 2.0 and Cortisol:DHEA-S calculates as 9.0

  Scenario: Thyroid Conversion pattern engine matches signature, Nutrient-Deficient phenotype, and calorie-cut context
    Given a draw on a day in a logged calorie cut (multiplier 0.8) with TSH 1.7, Free T4 1.2, Free T3 2.5 pg/mL, Reverse T3 25 ng/dL, and Ferritin 42 ng/mL
    When LabPatternEvaluator evaluates that draw against the real or fixture pattern engine
    Then Thyroid Conversion matches with FT3:rT3 = 10.0, identifies Nutrient-Deficient Conversion Impairment, and attaches the calorie-cut context note

  Scenario: Same-draw discordance rules catch ApoB > LDL-C, Cystatin C vs Creatinine, and SHBG masking Free T
    Given a draw with LDL-C 92 mg/dL and ApoB 105 mg/dL, Creatinine 1.32 mg/dL and Cystatin C 0.72 mg/L, and Total T 550 ng/dL with SHBG 62 nmol/L and Free T 9.5 pg/mL
    When discordances are evaluated for that draw
    Then all three masking/discordance alerts are returned

  Scenario: Cross-marker rules combine the latest value of each marker across split draws while ignoring older superseded values
    Given Draw 1 in 2025 had CK 420 U/L, Draw 2 in May 2026 had CK 110 U/L, and Draw 3 in Nov 2026 had AST 44 U/L and ALT 19 U/L
    When LabInsightsRule evaluates patterns
    Then "Muscle, not liver" does NOT fire because latest CK is 110 U/L (superseding 2025 CK 420)
    And when a newer Draw 4 logs CK 380 U/L alone, "Muscle, not liver" fires by combining latest CK (Draw 4) with latest AST and ALT (Draw 3)
