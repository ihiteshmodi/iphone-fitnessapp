Feature: Calculated markers from the same draw
  As the owner
  I want the ratios and formulas the vault quotes worked out from my results
  So that I see HOMA-IR, TG:HDL, globulin and the rest without doing the sums

  Scenario: A formula is worked out from one draw
    Given a draw with A 10 and B 4, and C defined as "{a} - {b}"
    Then the draw shows C 6, marked calculated

  Scenario: Inputs typed in another unit are converted first
    Given A typed as 2 "big-unit" (1 big-unit = 5 of the formula's unit) and B 4
    Then C is 6

  Scenario: Nothing is calculated without every input from that draw
    Given A on one draw and B on another
    Then neither draw shows C

  Scenario: A value the lab printed wins
    Given the lab reported C 7 on the draw with A 10 and B 4
    Then the draw shows only the lab's C 7

  Scenario: A formula with a condition is only used when it holds
    Given D is "{a} + 1" only if "{a} > 20"
    Then a draw with A 10 has no D, and a draw with A 30 has D 31

  Scenario: One calculated marker can feed another
    Given E is "{c} * 2"
    Then a draw with A 10 and B 4 shows E 12

  Scenario: A calculated ratio is read against bands that have no unit
    Given R is "{a} / {b}" with no unit, and its optimal band is 2 to 3 with no unit
    Then R 2.5 reads optimal

  Scenario: The history of a calculated marker lists every draw it can be worked out for
    Given two draws with A and B
    Then the history of C has two values, newest first
