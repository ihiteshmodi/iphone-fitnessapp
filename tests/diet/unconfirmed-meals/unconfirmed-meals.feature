Feature: Meals I forgot to tick
  As the lifter I sometimes go to bed without ticking dinner, and some days I really skip a meal.
  I want the app to ask about past meals left unticked, so each one is either eaten or knowingly skipped.

  Background:
    Given the plan from 2026-11-10 has Brunch and Dinner
    And today is 2026-11-19

  Scenario: Unticked meals of the last 7 days are listed, newest first
    Given Brunch and Dinner were ticked every day except Dinner on 2026-11-18 and both meals on 2026-11-16
    Then I am asked about 2026-11-18 Dinner, then 2026-11-16 Brunch and Dinner in meal order
    And today's meals are not asked about

  Scenario: Ate it ticks the meal
    When I answer "Ate it" for 2026-11-18 Dinner
    Then Dinner is ticked on 2026-11-18 and I am not asked about it again

  Scenario: Skipped stops the question without ticking anything
    When I answer "Skipped" for 2026-11-18 Dinner
    Then nothing is ticked on 2026-11-18 Dinner and I am not asked about it again

  Scenario: Some days are never asked about
    Given a break on 2026-11-17, calories typed by hand on 2026-11-15, and Brunch half ticked on 2026-11-14
    Then none of those days is asked about
    And days older than 7 days are not asked about
