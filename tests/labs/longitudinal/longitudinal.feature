Feature: Longitudinal biomarker deltas, velocity, and lab-switch baseline reset
  As the owner tracking biomarkers over months and years
  I want deltas from baseline and previous draws, annualized velocity alerts, 2-draw persistence checks, and automatic baseline resets when switching commercial labs
  So that true trajectories stand out while cross-lab instrument shifts are never misread as biological drift

  Scenario: Rising Cortisol:DHEA-S, PSA velocity, rapid eGFR drop, and sustained hs-CRP fire drift flags
    Given two draws at the same lab 6 months apart
    When Cortisol:DHEA-S rises from 4.0 to 9.0, PSA rises from 1.0 to 1.4, eGFR drops from 88 to 78, and unconfounded hs-CRP stays above 1.0 mg/L on both draws
    Then Cortisol:DHEA-S flags rising stress-to-recovery ratio, PSA flags velocity >= 0.35/yr, eGFR flags rapid decline, and hs-CRP flags sustained elevation

  Scenario: Switching commercial laboratories resets the longitudinal baseline
    Given Draw 1 at "Thyrocare" had Ferritin 60 ng/mL and Draw 2 at "Quest" had Ferritin 95 ng/mL
    When longitudinal summary is computed for Ferritin
    Then switchedLab is true and Draw 2 is treated as a fresh baseline for Quest with nil velocity across the lab switch
