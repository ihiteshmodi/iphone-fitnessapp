Feature: Exercise library
  As the lifter I want to keep my own exercise list with muscles and how-to instructions
  so that I can pick exercises when I build a workout.

  Scenario: Add an exercise to the library
    When I add "Landmine Press" with muscle "Shoulders" and instructions "Stand split stance, press up and across"
    Then it appears in the library and in the exercise picker

  Scenario: Edit instructions
    Given "Chest Dips Machine" has the instruction "handle inner, squeeze very hard ..."
    When I change its instructions to "handle inner, pause at the bottom"
    Then the exercise detail screen and every day that uses it show the new instructions

  Scenario: Search the library while picking
    When I search the picker for "pull"
    Then I see "Lat Pulldown", "Reverse Lat Pulldown" and "Weighted Pull Ups"

  Scenario: Names are unique ignoring case and spaces
    Given "Lat Pulldown" is in the library
    When I add " lat pulldown "
    Then it is rejected with "Exercise already exists"

  Scenario: A name is required
    When I add an exercise with an empty name
    Then it is rejected with "Name is required"

  Scenario: Rename keeps history
    Given "Tricep Pushdown" has logged sets
    When I rename it to "Triceps Pushdown"
    Then the history is still attached to the exercise

  Scenario: Exercises with history cannot be deleted
    Given "Squats" has logged sets
    When I delete it
    Then it is rejected with "This exercise has history. Remove it from days instead"
