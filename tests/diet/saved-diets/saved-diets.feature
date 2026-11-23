Feature: Saved diets
  As the lifter I change my fixed diet every few months and sometimes want an old one back.
  I want to keep each diet under a name and switch to any of them from a date, without touching earlier days.

  Background:
    Given the plan from 2026-10-26 has Brunch (Oats 100 g) and Dinner (Lentils 200 g)

  Scenario: Save the current diet under a name
    When I save the diet in force on 2026-11-19 as "High-protein 2-meal"
    Then "High-protein 2-meal" is listed with 2 meals, 2 foods and its calories and protein
    And it is marked as the diet in force on 2026-11-19

  Scenario: Use a saved diet from a date
    Given "High-protein 2-meal" is saved and the plan later changes to Rice 150 g only from 2026-11-25
    When I use "High-protein 2-meal" from 2026-12-01
    Then from 2026-12-01 the plan is Brunch (Oats 100 g) and Dinner (Lentils 200 g) again
    And 2026-11-30 still has Rice 150 g

  Scenario: Names are unique and an empty plan cannot be saved
    Given "High-protein 2-meal" is saved
    When I save another diet as "high-protein 2-meal"
    Then I am told "A saved diet with that name already exists"
    And saving on 2026-10-01, before any plan, says "There is no diet plan on that day to save"

  Scenario: Deleting a saved diet leaves the plan alone
    Given "High-protein 2-meal" is saved
    When I delete it
    Then it is no longer listed and the plan in force is unchanged

  Scenario: Previewing a saved diet shows every meal, item, quantity, cycle and macro total without altering the plan
    Given "High-protein 2-meal" is saved
    When I inspect its detail preview
    Then it lists Brunch (Oats 100 g) and Dinner (Lentils 200 g) with meal and whole-diet macros
    And the active plan is unchanged
