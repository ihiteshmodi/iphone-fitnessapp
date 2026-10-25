Feature: Muscle volume progression
  As the lifter I want volume (weight × reps) over time per muscle so that I can see what is growing.

  Scenario: One line per exercise within a muscle
    Given "Triceps Pushdown" and "Triceps Press" are mapped to "Triceps"
    When I open Progress and choose "Triceps"
    Then I see a volume line for each exercise over time since the baseline

  Scenario: Volume is the sum of weight × reps for the session
    Given on 2026-10-16 I did "Triceps Pushdown" 45 × 10 and 40 × 12
    When I open the "Triceps" chart
    Then the 2026-10-16 point for "Triceps Pushdown" is 930

  Scenario: Muscles come from the exercise library, not from old log labels
    Given "Squats" is "Quads" in the library but older rows say "Legs"
    When I open Progress
    Then "Squats" appears under "Quads" only

  Scenario: A muscle with no data since the baseline is not listed
    Given no "Shins" sets since 2026-08-31
    When I open Progress
    Then "Shins" is not in the muscle list
