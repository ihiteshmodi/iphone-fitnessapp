Feature: Saved workouts
  As the lifter I change my workout plan now and then and sometimes want an old one back.
  I want to keep whole workouts under a name and switch between them, without losing any logged history.

  Background:
    Given a plan with Day 1 "Push" (Bench press 3 x 6-10) on Monday and Day 2 "Pull" (Row 3 x 8-12) on Wednesday

  Scenario: Save the current workout under a name
    When I save the workout as "PPL Nov 2026"
    Then "PPL Nov 2026" is listed with 2 days and 2 exercises and marked as the current workout

  Scenario: Switch to a saved workout and back, history kept
    Given "PPL Nov 2026" is saved and I logged Bench press 60 kg x 8
    When I switch to a saved workout "Full body" with one day "Full" (Squat 3 x 5-8)
    Then the plan has one day "Full" with Squat
    And my Bench press set is still logged
    When I switch back to "PPL Nov 2026"
    Then the plan has "Push" on Monday and "Pull" on Wednesday again

  Scenario: Presets are read-only
    Given "Meridian · Upper/Lower" is a preset
    Then renaming or deleting it says "Presets cannot be changed; use it or copy it"
    And copying it as "My Upper/Lower" gives a saved workout I can change

  Scenario: Names are unique
    Given "PPL Nov 2026" is saved
    When I save another as "ppl nov 2026"
    Then I am told "A saved workout with that name already exists"
