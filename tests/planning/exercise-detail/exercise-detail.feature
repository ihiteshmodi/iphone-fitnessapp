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
    And my last sessions of "Chest Dips Machine" had a best set of 54 kg × 9 on 2026-10-18 and 54 kg × 8 on 2026-10-23
    When I tap "Chest Dips Machine"
    Then the screen shows, in this order:
      | section        | content                                                                                                      |
      | do today       | working weight 54 kg; the aim as a pill ("Increase reps") with a hint ("Beat 8 reps at 54 kg"); warm-ups labelled "75% 40.5 kg" and "90% 48.6 kg" |
      | best set       | line chart: kg on the line (weight above each point), and the date with "× reps" under each point; the newest point is the brightest |
      | how to         | the instruction "handle inner, squeeze very hard ..."                                                         |
      | muscles worked | a small card (see muscle-anatomy.feature)                                                                      |
      | log sets       | today's sets and an "Add set" button, always the last thing on the screen                                     |
    And there is no separate "Last session", "Aim" or "History" box, because the chart already shows weight and reps per session

  Scenario Outline: The aim sits inside the "Do today" card
    Given the heaviest set is <weight> kg × <reps> and the plan is <min> to <max> reps
    When I open the exercise
    Then the "Do today" card shows the pill "<pill>" and the hint "<hint>"

    Examples:
      | weight | reps | min | max | pill           | hint                |
      | 45     | 10   | 6   | 10  | Increase weight |                     |
      | 54     | 8    | 6   | 10  | Increase reps  | Beat 8 reps at 54 kg |
      | 54     | 5    | 6   | 10  | Maintain       | Reach 6 reps at 54 kg |

  Scenario: The chart shows the last six sessions
    Given "Triceps Pushdown" has 8 sessions of best sets
    When I open it
    Then the chart shows the 6 newest sessions, oldest on the left
    And the newest point is the brightest

  Scenario: The chart with a single session
    Given "Squats" has one session of history
    When I open it
    Then the chart shows one point and the trend badge says "Not enough data"

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
