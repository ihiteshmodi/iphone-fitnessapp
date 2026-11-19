Feature: Export the diet for an AI review
  As the person following the Meridian rules
  I want to hand my whole diet to an agent that has read the vault
  So that the checks too fiddly for the app (iron away from tea, soaking legumes, omega-6 sources...) still get done
  whenever I change my diet.

  Scenario: The export holds the planned day meal by meal
    Given a plan with "Shake" at Brunch and "Dal" at Dinner
    When I export the diet for review on 19 Nov 2026
    Then the report lists Brunch with Shake and Dinner with Dal
    And each meal shows its calories, protein, fibre and leucine

  Scenario: The 14-day average uses only days I logged
    Given I ate everything on 18 Nov and logged nothing on 17 Nov
    When I export the diet for review on 19 Nov
    Then the average is over 1 logged day
    And nutrients with no data are listed as unknown, not as zero

  Scenario: Supplements are matched to the library
    Given "Fish oil" is a supplement in my foods and the library knows it
    When I export the diet for review
    Then the report shows Fish oil with its library verdict

  Scenario: Open Room for improvement items are included
    Given Room for improvement has open items
    When I export the diet for review
    Then each item's title and detail are in the report
    And with no open items the report says "None"
