Feature: Refeeds and diet breaks while cutting
  As the lifter on a cut I want to pick my own refeed days, see what a refeed is on those days, mark whether I did it,
  and be told when a diet break is due.

  Background:
    Given I am cutting: the default is 2400 calories with multiplier 0.85 from 2026-10-01

  Scenario: Refeed days are chosen by weekday or by date
    When I choose Sundays and also 2026-11-26
    Then 2026-11-22 (a Sunday) and 2026-11-26 are refeed days and 2026-11-23 is not

  Scenario: On a refeed day the target is maintenance
    Given maintenance is 2890 calories
    Then on a refeed day the target is 2890 calories, extra mostly from carbs, protein and fat unchanged
    And when I am not cutting there are no refeed days

  Scenario: Marking the day
    When I mark 2026-11-22 as Refeed done
    Then 2026-11-22 shows Refeed done
    And marking it Normal or Skipped replaces that

  Scenario: Diet break after 6 to 12 weeks of cutting
    Given the cut started 2026-10-01
    Then on 2026-11-19, 7 weeks in, Setup has "Diet break" (Tip) saying 1-2 weeks at maintenance every 6-12 weeks
    And on 2026-12-24, 12 weeks in, it is Improve

  Scenario: The scale jump after a refeed is ignored
    Given I marked 2026-11-17 as Refeed done
    Then for 3 days after it the cut-rate check says nothing
