Feature: PR highlighting
  As the lifter I watch the line chart. I want a session where I reached the top of the rep range with clean form to look
  different, and the screen to tell me loudly what to do next: take the heavier weight.

  Background:
    Given "Leg Extensions" is planned for 8 to 16 reps
    And a PR is: the top of the rep range (16) reached in a session, with clean form confirmed

  Scenario: Last session was a PR
    Given on 2026-10-21 I did 60 kg × 16 and answered Yes
    When I open the exercise on 2026-10-26
    Then the banner says "Increase weight to 72.5 kg" and the working weight is 72.5 kg
    And the 2026-10-21 dot on the chart is a PR dot
    And the workout list chip says "Go to 72.5"

  Scenario: Top reps but the form was not clean
    Given on 2026-10-21 I did 60 kg × 16 and answered No
    When I open the exercise on 2026-10-26
    Then the banner says "Stay at 60 kg" and aim for clean reps
    And the dot is hollow, not a PR dot
    And the working weight stays 60 kg

  Scenario: Older sessions from before the question existed count as clean
    Given on 2026-10-21 I did 60 kg × 16 and was never asked
    Then that session is a PR

  Scenario: A heavier session today removes the banner
    Given the last session was a PR at 60 kg
    When today I log 72.5 kg × 9
    Then there is no banner and no PR dot for today

  Scenario: Logging a lighter set today does not remove the banner
    Given the last session was a PR at 60 kg
    When today I log 60 kg × 12
    Then the banner is still shown

  Scenario: Today's own PR
    When today I log 60 kg × 16 and answer Yes
    Then the banner says it is a PR today with next time 72.5 kg and today's dot is a PR dot
    And the working weight today stays 60 kg

  Scenario: Today's top reps are pending until answered
    When today I log 60 kg × 16 and have not answered
    Then today's dot is a normal dot

  Scenario: Deload weeks have no PR banner
    Given deload mode is on
    Then there is no banner
