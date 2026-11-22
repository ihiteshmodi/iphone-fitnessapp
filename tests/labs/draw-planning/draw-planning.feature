Feature: Plan a draw and know when to retest
  As the owner
  I want the vault's order list, prep timeline and retest timing worked out for me
  So that I order the right tests, arrive prepared, and retest on time

  Scenario: The first order is the full baseline, every test named
    Given I have no results yet
    When I plan my first draw
    Then the order lists every test in the "first" panels by name, with what to ask for

  Scenario: A result triggers a conditional add-on
    Given my last ferritin was outside its optimal band
    When I plan a draw
    Then the "If ferritin is off" panel is added with its reason

  Scenario: The prep timeline counts back from the draw
    Given a draw on 10 Dec 2026 at 08:00
    Then "Stop biotin" is on 7 Dec (72 h before) and "Stop iron pills" on 6 Dec (96 h before)
    And steps for tests I am not ordering are left out

  Scenario: Retest timing
    Given ferritin was low on 1 Sep 2026 and its out-of-band rule is 8-12 weeks
    Then ferritin is due between 27 Oct and 24 Nov 2026
    And an optimal glucose with a routine rule of 26-52 weeks is due from 2 Mar 2027
    And a first-panel marker never tested shows as "baseline: not tested yet"

  Scenario: Per-marker draw notes, reflex co-tests for untested companions, Tier 2/3 upgrades, and male-only checklist
    Given Free T3 has co-tests "reverse-t3" and "ferritin", and my last draw had low Free T3 with optimal Ferritin and no Reverse T3
    When I plan my next draw as a Male
    Then each baseline test carries its draw note
    And a "Follow-up co-tests" item adds "Reverse T3" (skipping Ferritin because it was already in that draw)
    And Tier 2/3 upgrades exclude female-only markers like AMH, and the draw-day checklist omits female menstrual bullets for a Male

