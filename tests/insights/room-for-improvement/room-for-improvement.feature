Feature: Room for improvement
  As the lifter I want one place that tells me what to fix today, how often things go wrong over time,
  what to change once in my plan, and lets me put away what does not apply to me.

  Background:
    Given a daily rule "Trans fat" that fires on days with trans fat
    And a setup rule "Two protein meals" that fires while the diet has 2 protein meals
    And today is 2026-11-19

  Scenario: Today lists what fired yesterday and today
    Given trans fat on 2026-11-18
    Then Today shows "Trans fat" for 2026-11-18
    And the Room for improvement badge counts 2 (one today item, one setup item)

  Scenario: Dismissing hides it from Today but Trends still count it
    When I dismiss "Trans fat" for 2026-11-18
    Then Today no longer shows it
    And Trends show "Trans fat" fired on 1 of the last 7 days

  Scenario: Trends mark each day fired, fine or without data
    Given trans fat on 2026-11-13 and 2026-11-18, and no data on 2026-11-15
    Then the 7-day strip for "Trans fat" from 2026-11-12 reads ok, fired, ok, no data, ok, ok, fired

  Scenario: Accepting a setup item moves it to Archived, still tracked
    When I accept "Two protein meals" with the note "I know"
    Then Setup no longer shows it and Archived lists it as accepted with "I know"
    And restoring it brings it back to Setup

  Scenario: Not applicable stops the rule
    When I mark "Trans fat" as not applying to me
    Then it is gone from Today and Trends and listed in Archived as not applicable
