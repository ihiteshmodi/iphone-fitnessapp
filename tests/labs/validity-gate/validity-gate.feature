Feature: Pre-analytic validity gate
  As the owner reviewing lab numbers
  I want draw collection timing, fasting, washouts, assay choice, and urine concentration checked before interpreting a result
  So that confounded draws trigger redraw warnings instead of false biological alarms

  Scenario: Late-afternoon unfasted testosterone triggers circadian and fasting validity warnings
    Given a draw at 15:45 after 3 hours fasted
    When I check Total Testosterone 285 ng/dL
    Then circadian timing and fasting warnings fire with redraw guidance

  Scenario: Fasting-exempt markers pass an unfasted draw cleanly
    Given Vitamin D is listed as fasting-exempt in global protocols
    When I check Vitamin D 58 ng/mL from a draw after 1 hour fasted
    Then no fasting warning fires

  Scenario: Unstopped biotin flags immunoassay thyroid results unless LC-MS/MS was used
    Given a draw where biotinStopped is false
    When I check TSH with standard immunoassay
    Then a biotin interference warning fires
    When I check Cortisol assayed by LC-MS/MS
    Then no biotin interference warning fires

  Scenario: Hard training, recent illness, and male estradiol immunoassay fire targeted warnings
    Given a draw with hard training in 72h and recent illness
    When I check AST and hs-CRP, and Male Estradiol measured by standard immunoassay
    Then AST flags training washout, hs-CRP flags both training and illness, and Male Estradiol flags assay pitfall

  Scenario: Dilute, concentrated, and squamous-contaminated urine samples gate urinalysis interpretation
    Given one draw with Urine Specific Gravity 1.003 and Urine Protein "Negative"
    Then Urine Protein warns of dilute sample false-negative masking
    Given another draw with Urine Specific Gravity 1.034, Squamous Cells 12/HPF, and Urine Protein "Trace"
    Then Urine Protein warns of both concentrated trace-protein artifact and squamous contamination
