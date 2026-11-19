Feature: Daily check-in and weekly recovery signs
  As the lifter I want a short, optional check-in: urine colour, walks after meals, heavy sweating,
  and once a week the signs of being under-recovered. Skipping anything is fine: unanswered is no data.

  Scenario: Answers are kept per day and can be cleared
    When I answer Pale for urine and tick a walk after Brunch on 2026-11-19
    Then 2026-11-19 shows Pale and Brunch walked
    And clearing the urine answer leaves it unanswered

  Scenario: Dark urine two days in a row
    Given Dark on 2026-11-17 and 2026-11-18
    Then Today has "Urine dark" (Improve) saying drink more, 30-40 mL per kg a day
    And Dark on only one day says nothing

  Scenario: Clear urine three days in a row
    Given Clear on 2026-11-16, 2026-11-17 and 2026-11-18
    Then Today has "Urine clear" (Tip) saying I may be drinking more than needed or losing minerals

  Scenario: Walks after meals as a weekly share, never a warning
    Given 2 meals a day planned and walks ticked after 7 of the 14 meals in the last 7 days
    Then the walk share is 50 percent
    And no Room for improvement item is made from walks

  Scenario: Recovery signs flagged only as a pattern
    Given 3 signs ticked for the week of 2026-11-10 and 4 for the week of 2026-11-17
    Then Today has "Under-recovered" (Improve) with the vault's recovery order
    But 3 signs in only one week says nothing
