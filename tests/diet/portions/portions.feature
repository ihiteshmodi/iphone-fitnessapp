Feature: Pieces, grams and shares of a pack
  As the lifter I eat part of a packet ("4 biscuits"), and the label is written for 100 g, so I want the app to work the amounts out.

  Background:
    Given a packaged food "Tea biscuits": a 250 g pack of 35 pieces, price 40
    And its label says per 100 g: 480 calories, protein 7, carbs 70, fat 18

  Scenario: One piece weighs the pack divided by its pieces
    Then one piece weighs 7.14 g and costs 1.14

  Scenario: Pieces become grams and then nutrition
    When I eat 4 pieces
    Then that is 28.57 g
    And it gives 137.1 calories, protein 2, carbs 20, fat 5.14

  Scenario: Grams are used as they are
    When I eat 30 g
    Then it gives 144 calories

  Scenario: A share of the pack is a share of its weight
    When I eat half the pack
    Then that is 125 g, which is 17.5 pieces

  Scenario: A piece I weighed myself replaces the pack maths
    Given I weighed one piece at 8.28 g
    When I eat 4 pieces
    Then that is 33.12 g

  Scenario: A label written per serving is kept as it is
    Given the label of another food says per 30 g: 150 calories, protein 3
    When I eat 45 g
    Then it gives 225 calories and protein 4.5

  Scenario: A food with no piece information cannot be entered in pieces
    Given a food "Loose rice" with no pieces in its pack
    When I try to eat 3 pieces
    Then it is rejected with "Loose rice has no piece size"

  Scenario: A food counted in pieces needs no conversion
    Given a recipe "Flatbread" whose unit is one piece
    When I eat 3 pieces
    Then the amount is 3 pieces, with no grams involved

  Scenario Outline: An amount must be above zero
    When I enter <amount> as pieces, grams or a share of a pack
    Then it is rejected with "Enter an amount above 0"

    Examples:
      | amount |
      | 0      |
      | -2     |

  Scenario: The entry modes a food offers
    Then the packet offers Pieces, Grams and Share of pack
    And a food in grams with no pieces offers Grams only
    And a food counted in pieces, like a recipe, offers just its own count
    And a food in grams with a pack size but no pieces offers Grams and Share of pack

  Scenario: Each mode starts at a sensible amount and moves in sensible steps
    Then Pieces start at 1 and move by 1, Grams start at 30 and move by 5, Share of pack starts at a quarter and moves by a quarter
    And a count-based food starts at 1 and moves by 1
