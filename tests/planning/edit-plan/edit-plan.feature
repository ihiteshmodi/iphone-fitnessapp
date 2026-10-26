Feature: Edit the plan: days and their exercises
  As the lifter I want to add days and build workouts on the phone
  so that I can improve my plan without touching the spreadsheet.

  Scenario: Add a new training day
    Given my plan has Day 1, Day 2 and Day 3
    When I add a day
    Then I have Day 4, empty, available in the day picker

  Scenario: Build a workout from the library
    Given "Cable Crunch" is in the exercise library
    When I add "Cable Crunch" to Day 4 with 3 sets and reps 12 to 20
    Then it appears last on Day 4

  Scenario: Create a new exercise while building a workout
    When I add a new exercise "Landmine Press" to Day 4 with muscle "Shoulders" and instructions "Stand split stance, press up and across"
    Then "Landmine Press" is added to the library
    And it appears on Day 4 with those instructions

  Scenario Outline: Name days by number or by weekday
    Given Day 1 is assigned to Monday, Day 2 to Wednesday and Day 3 to Friday
    When I choose to name days by "<mode>"
    Then the day picker shows "<labels>"

    Examples:
      | mode    | labels             |
      | numbers | Day 1, Day 2, Day 3 |
      | weekday | Mon, Wed, Fri      |

  Scenario: A weekday name needs a weekday assigned
    Given Day 4 has no weekday
    When I choose to name days by "weekday"
    Then Day 4 still shows as "Day 4"

  Scenario: The weekday can be set without opening the day
    Given I name days by "weekday" and Day 1 has no weekday yet
    When I open Edit plan
    Then Day 1 shows a "Set a weekday" menu in its header area, and choosing Monday renames it "Mon"

  Scenario: Change sets and rep range of a planned exercise
    Given Day 2 contains "Lat Pulldown" with 3 sets and reps 6 to 10
    When I change it to 4 sets and reps 8 to 12
    Then Day 2 shows "Lat Pulldown" with 4 sets and reps 8 to 12

  Scenario: Reorder the exercises in a day
    Given Day 2 lists "Lat Pulldown" first and "Preacher Curls" second
    When I move "Preacher Curls" to the top
    Then Day 2 lists "Preacher Curls" first

  Scenario: Remove an exercise from a day keeps its history
    Given "Preacher Curls" is on Day 3 and has logged sets
    When I remove it from Day 3
    Then Day 3 no longer shows it
    And its logged sets are still available for charts

  Scenario: Remove a day keeps all history
    Given Day 4 has 5 exercises
    When I delete Day 4
    Then Day 4 and its plan entries are gone
    And no logged sets are removed

  Scenario: Reject an invalid rep range
    When I set minimum reps 12 and maximum reps 8
    Then the change is rejected with "Min reps cannot exceed max reps"

  Scenario: The same exercise cannot be on one day twice
    Given "Lat Pulldown" is on Day 2
    When I add "Lat Pulldown" to Day 2
    Then it is rejected with "Already on this day"
