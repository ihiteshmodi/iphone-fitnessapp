Feature: Add a lab draw
  As the owner following the Meridian bloodwork volume
  I want to type in each blood draw with the state I was in and every result
  So that every later reading, alert and retest knows exactly what was measured and how

  Background:
    Given the catalogue knows "Ferritin" in ng/mL (also µg/L, factor 1) and "Glucose" in mg/dL (also mmol/L, factor 18)

  Scenario: A draw keeps its prep state
    When I add a draw on 2 Dec 2026 at 08:10, fasted 11 hours, hard training in the last 72 hours, biotin stopped
    Then the draw is saved with those answers

  Scenario: Results are stored as typed and in the marker's default unit
    Given a draw on 2 Dec 2026
    When I enter glucose 5.0 mmol/L
    Then the result shows 5.0 mmol/L as typed and 90 mg/dL in the default unit

  Scenario: A unit the catalogue does not list is refused
    When I enter ferritin 48 in "pmol/L"
    Then I am told that unit is not known for ferritin

  Scenario: History is per marker, newest first, and an optional lab range is kept
    Given ferritin 40 on 1 Jun 2026 and 48 on 2 Dec 2026 with the lab's range 30-400
    Then ferritin history lists 2 Dec then 1 Jun, and the 2 Dec result keeps 30-400

  Scenario: Deleting a draw removes its results
    Given a draw with two results
    When I delete the draw
    Then no results remain

  Scenario: Smart unit scaler shows expected unit and flags a 10x unit mismatch
    Given Free T3 expects pg/mL (typical 2.3-4.2) and also knows ng/dL (factor 10)
    When I check a typed value of 0.31 in pg/mL
    Then the scaler warns of a ~10x mismatch and suggests switching the unit to ng/dL (= 3.1 pg/mL)

  Scenario: An unlisted lab unit is accepted when a custom conversion multiplier is supplied
    Given a draw on 2 Dec 2026
    When I enter ferritin 0.048 in "mg/L" with custom multiplier 1000 to ng/mL
    Then the result keeps 0.048 mg/L as typed and converts to 48 ng/mL in the default unit

  Scenario: Qualitative dipsticks, titers, below-detection-limit values, and paired blood pressure are stored
    Given a draw on 2 Dec 2026
    When I enter Urine Nitrites "Negative", ANA titer "1:80", hs-CRP "< 0.3" mg/L, and Blood Pressure 126 / 84 mmHg
    Then Urine Nitrites keeps "Negative", ANA keeps "1:80" with numeric titer 80, hs-CRP feeds PhenoAge as LOD/root-2, and Blood Pressure keeps systolic 126 and diastolic 84

  Scenario: Editing an existing draw updates its lab name, date, and prep state without losing its results
    Given a draw on 27 Sep 2025 at "Vardhaman jain trust" with ferritin 48 ng/mL and glucose 86 mg/dL
    When I edit that draw to lab "Sthanak Lab (Vardhman Jain Trust)", fasted 12 hours, biotin stopped, and note "Morning CBC"
    Then the draw reflects the updated metadata and still keeps ferritin 48 ng/mL and glucose 86 mg/dL

  Scenario: Saved lab names return unique trimmed names newest first
    Given draws at "Tata 1mg Labs", "  tata 1mg labs ", "Healthians Labs", and a blank lab name
    When I ask for saved lab names
    Then I get "Healthians Labs" followed by the newest casing of Tata 1mg Labs with no duplicates or blanks

  Scenario: Editing an existing result updates its value, unit, and lab range while leaving other results untouched
    Given a draw on 27 Sep 2025 with glucose 86 mg/dL and ferritin 40 ng/mL
    When I edit the glucose result to 5.0 mmol/L with lab range 3.9-5.6
    Then glucose reads 5.0 mmol/L (90 mg/dL in default unit) with lab range 3.9-5.6 and ferritin remains 40 ng/mL

  Scenario: Editing a result refuses an unknown unit without a positive custom multiplier
    Given a draw on 27 Sep 2025 with ferritin 48 ng/mL
    When I edit the ferritin result to 50 in "pmol/L" without a custom multiplier
    Then the edit is refused and ferritin stays 48 ng/mL

