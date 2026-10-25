Feature: Exercise detail with progress trend and inline logging
  As the lifter I want to tap an exercise and see its details, my recent progress and log my sets there
  so that I train and record in one place (Whoop/Bevel-style flow: day → list → detail).

  Background:
    Given the baseline date is 2026-08-31

  Scenario: Pick a day and see its exercises
    Given Day 3 has 16 planned exercises
    When I choose Day 3
    Then I see a card per exercise in plan order
    And each card shows the muscle, sets × rep range, working weight, recommendation and a mini trend line
    And each card shows how many of its sets I have logged today, for example "1/3"

  Scenario: Open an exercise and see everything needed to train, top to bottom
    Given I chose Day 3
    And my last session of "Chest Dips Machine" on 2026-10-18 was 54 kg × 9, 54 kg × 8, 54 kg × 8
    When I tap "Chest Dips Machine"
    Then the first screen shows, in this order:
      | section      | content                                                                    |
      | target       | working weight 54 kg, warm-ups 40.5 kg and 48.6 kg, reps 6 to 10, 3 sets   |
      | last session | date 2026-10-18 and its sets                                               |
      | today's aim  | the recommendation, for example "Increase reps: beat 9 reps at 54 kg"      |
      | how to       | the instruction "handle inner, squeeze very hard ..."                      |
      | progress     | chart of the last sessions (top-set weight and reps) and the trend badge   |
      | history      | recent sessions, newest first                                              |
      | log sets     | today's sets, an "Add set" button (bottom of the screen)                   |

  Scenario: Edit the instructions from the exercise screen
    Given I am on "Chest Dips Machine"
    When I tap "Edit how-to" and save "handle inner, pause at the bottom"
    Then the how-to section shows the new text everywhere the exercise is used

  Scenario Outline: Trend is judged on the estimated 1-rep-max of each session's best set (Epley: weight × (1 + reps / 30))
    Given the last sessions' best-set estimates, oldest to newest, are <series>
    When I open the exercise
    Then the trend is "<trend>"

    Examples:
      | series                    | trend           |
      | 60, 62, 64, 66            | Improving       |
      | 60, 60.5, 59.8, 60.2      | Flat            |
      | 66, 64, 62, 60            | Declining       |
      | 60                        | Not enough data |
      | (no sessions)             | Not enough data |

  Scenario: Log my sets from inside the exercise
    Given I am on "Chest Dips Machine" with working weight 54 kg and target 3 sets
    When I add a set with 54 kg × 9
    Then the set is saved for today
    And the card shows "1/3"
    And the chart gains a point for today's best set

  Scenario: The set form is prefilled from the target
    When I open the "Add set" form for "Chest Dips Machine"
    Then weight is prefilled with 54 and reps with the maximum reps 10

  Scenario: Correct a mistaken set
    Given I logged 540 kg × 9 today by mistake
    When I delete that set
    Then the card and the chart no longer include it

  Scenario: An exercise with no history
    Given "Squats" has no sets since the baseline
    When I open it
    Then I see "No history yet", the trend is "Not enough data", and I can still log a first set
