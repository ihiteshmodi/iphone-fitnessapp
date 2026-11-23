Feature: Routines
  As the lifter I want ready groups of exercises (like recipes for food) that I can browse by muscle
  and pull into a workout day, from coach presets or my own.

  Scenario: Make a routine from a workout day
    Given Day 1 "Push" has Bench press 3 x 6-10 and Fly 2 x 10-15
    When I save Day 1 as the routine "Chest finisher"
    Then "Chest finisher" has Bench press 3 x 6-10 then Fly 2 x 10-15

  Scenario: Pull a routine into a day
    Given the routine "Chest finisher" and Day 2 that already has Fly
    When I add "Chest finisher" to Day 2
    Then Day 2 gets Bench press 3 x 6-10 after its own exercises, and Fly is not added twice
    And changing the routine later does not change Day 2

  Scenario: Browse routines by muscle
    Given "Chest finisher" trains Chest and "Leg day" trains Quads
    When I look at routines for Chest
    Then only "Chest finisher" is listed

  Scenario: Multi-muscle preset routines appear under every primary muscle chip even when exercises have no muscle column
    Given "Meridian · Back + Shoulders" has "Lat Pulldowns (Cable)" and "Shoulder Press (Machine)" with no muscle column set
    And "Meridian · Chest + Arms" has "Incline Bench Press (Dumbbell)", "Preacher Curl (Machine)" and "Tricep Pushdown (Cable)" with no muscle column set
    Then filtering routines by "Back" or "Shoulders" returns "Meridian · Back + Shoulders"
    And filtering routines by "Chest" or "Arms" returns "Meridian · Chest + Arms"

  Scenario: Create, edit, duplicate, rename and delete routines including presets
    When I create a routine "Arms Specialization" with Preacher Curl 3 x 8-12 and Tricep Pushdown 3 x 10-15
    Then it is saved with those 2 exercises
    And creating a routine with an empty exercise list is rejected
    And preset routines can be duplicated, edited, renamed and deleted directly

  Scenario: Coach presets are loaded once from the presets file
    Given a presets file with the routine "Push" (Chest Press (Machine) 4 x 10, Stretching (Upper) 1 x 10 min)
    And the workout "4-Day Upper/Lower" with Monday "Upper" (Chest Press (Machine) 4 x 10)
    When I load the presets
    Then "Push" is a preset routine with Chest Press (Machine) 4 x 10-10, created in the exercise library if missing
    And timed stretching is left out because it is not a set and rep exercise
    And "4-Day Upper/Lower" is a preset workout
    And loading them again adds nothing
