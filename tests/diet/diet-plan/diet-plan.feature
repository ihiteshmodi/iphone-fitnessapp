Feature: The daily diet plan
  As the lifter I eat the same plan every day. I want to write it once, change it from a date, and never lose what earlier days looked like.

  Scenario: A plan is a list of foods in meals
    Given a plan from 2026-10-01 with Morning: Oats 50 g, and Dinner: Rice 150 g and Lentils 60 g
    When I read the plan for 2026-10-05
    Then I get the meals Morning and Dinner in that order, with each food and quantity in order

  Scenario: The plan in force on a day is the newest one that started on or before it
    Given a plan from 2026-10-01 and another from 2026-10-20
    Then 2026-10-19 uses the first plan and 2026-10-20 uses the second
    And 2026-10-30, a future day, uses the second
    And 2026-09-30, before any plan, has no plan

  Scenario: Changing the plan from a date never rewrites earlier days
    Given a plan from 2026-10-01 with Oats 50 g
    When I change Oats to 80 g starting 2026-10-26
    Then 2026-10-25 still has Oats 50 g
    And 2026-10-26 and later have Oats 80 g

  Scenario: A change made on the date a plan starts edits that plan in place
    Given a plan from 2026-10-26
    When I change an item starting 2026-10-26 and then change another starting 2026-10-26
    Then there is still one plan from 2026-10-26 holding both changes

  Scenario: Adding, removing and moving items
    Given a plan from 2026-10-26
    When I add Lentils 60 g to Dinner starting 2026-10-26
    Then the plan from 2026-10-26 has Lentils 60 g in Dinner
    And removing it takes it out again
    And moving Oats to the meal Brunch puts it under Brunch

  Scenario: An item can have a cycle
    Given an item with the cycle 2 weeks on and 1 week off from Monday 2026-10-26
    Then the plan keeps the cycle with the item
    And copying the plan to a new date keeps it

  Scenario: The same food cannot appear twice in one meal
    Given Oats is in Morning
    When I add Oats to Morning again
    Then it is rejected with "Oats is already in Morning"
    And Oats in Dinner as well is fine

  Scenario: Removing the plan that starts on a date lets the earlier plan apply again
    Given a plan from 2026-10-01 and another from 2026-10-20
    When I remove the plan from 2026-10-20
    Then 2026-10-25 uses the plan from 2026-10-01

  Scenario Outline: A plan item must be valid
    When I add an item with <field> <value>
    Then it is rejected with "<message>"

    Examples:
      | field    | value        | message                       |
      | quantity | 0            | Enter a quantity above 0      |
      | meal     | empty        | Give the meal a name          |
      | food     | not in library | That food is not in the library |
