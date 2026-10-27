Feature: View workout for a training day
  As the lifter I want Day 1, 2 or 3 of my plan with a working weight and a recommendation
  so that I can train without opening a spreadsheet.

  Background:
    Given the baseline date is 2026-08-31
    And deload mode is off

  Scenario: Heaviest logged set becomes the working weight and warm-ups
    Given "Triceps Pushdown" is planned for Day 3 with reps 6 to 10
    And the heaviest set since the baseline is 45 kg for 10 reps
    When I open Day 3
    Then "Triceps Pushdown" shows working weight 45 kg
    And warm-ups 33.75 kg (75%) and 40.5 kg (90%)
    And the recommendation is "Increase Weight"

  Scenario Outline: Recommendation compares reps at the heaviest weight with the plan range
    Given "<exercise>" is planned with reps <min> to <max>
    And the heaviest set is <weight> kg for <reps> reps
    When I open its day
    Then the recommendation is "<recommendation>"

    Examples:
      | exercise         | min | max | weight | reps | recommendation       |
      | Triceps Pushdown | 6   | 10  | 45     | 10   | Increase Weight      |
      | Triceps Press    | 6   | 10  | 45     | 8    | Increase Reps        |
      | Triceps Press    | 6   | 10  | 45     | 5    | Bring to maintenance |

  Scenario: A planned exercise with no history since the baseline
    Given "Squats" is planned for Day 1
    And no "Squats" set is logged on or after 2026-08-31
    When I open Day 1
    Then "Squats" has no working weight, no warm-ups
    And the recommendation is "No history"

  Scenario: Heaviest set ties are resolved by the heaviest weight, then most reps
    Given "Lat Pulldown" has sets 36 kg × 8 and 36 kg × 10 and 30 kg × 15
    When I open its day
    Then the working weight is 36 kg and the reps at that weight are 10

  Scenario: Instructions and muscle come from the exercise library
    Given "Chest Dips Machine" has the library instruction "handle inner, squeeze very hard ..."
    When I open Day 3
    Then I see that instruction and muscle "Chest" on the exercise

  Scenario: An exercise is done when all its main sets are logged today
    Given "Leg Extensions" has 1 main set and "Seated Cable Row" has 2 main sets
    And today I logged 1 set of each
    Then "Leg Extensions" is done and "Seated Cable Row" is not

  Scenario: Remaining hides the finished exercises
    Given 4 of the 6 exercises on the day are done
    When I choose "Remaining"
    Then I see only the 2 exercises that are not done, in their normal order
    And "All" shows all 6 again

  Scenario: Remaining with everything done
    Given every exercise on the day is done
    When I choose "Remaining"
    Then I see "All done" and a way back to "All"

  Scenario: The app always opens on All, and keeps the choice while it is open
    Given I chose "Remaining" on Day 2
    When I switch to Day 3 without closing the app
    Then Day 3 is also on "Remaining"
    When I close the app and open it again
    Then the day opens on "All"
