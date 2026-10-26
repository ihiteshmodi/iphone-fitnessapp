Feature: Measurement tolerance and percentages
  As the lifter I do not need to hit a target to the hundredth of an inch. I want to see how far each site is from its
  target in percent, and have the colour say whether that is fine, worth watching, or far off.

  Background:
    Given the tolerance is 3% unless I change it
    And "off" starts above 10%

  Scenario Outline: Percent from target and the colour
    Given "<site>" is a "<direction>" site with target <target> and current <current>
    Then Progress shows <percent> from the target
    And the colour is "<colour>"

    Examples:
      | site      | direction | target | current | percent | colour | why                                  |
      | Left Calf | grow      | 15.31  | 14.0    | -8.6%   | amber  | 8.6% short, beyond 3%                |
      | Left Calf | grow      | 15.31  | 15.0    | -2.0%   | green  | within 3%                            |
      | Left Calf | grow      | 45.0   | 40.0    | -11.1%  | red    | more than 10% short                  |
      | Shoulders | grow      | 45.3   | 46.0    | +1.5%   | green  | past a growth target is fine         |
      | Shoulders | grow      | 45.3   | 52.0    | +14.8%  | green  | past a growth target is always fine  |
      | Waist     | reduce    | 28.0   | 30.2    | +7.9%   | amber  | 7.9% over, beyond 3%                 |
      | Waist     | reduce    | 28.0   | 28.5    | +1.8%   | green  | within 3%                            |
      | Waist     | reduce    | 28.0   | 31.5    | +12.5%  | red    | more than 10% over                   |
      | Waist     | reduce    | 28.0   | 27.0    | -3.6%   | green  | below a reduce target is fine        |

  Scenario Outline: The edges of the bands
    Given a grow site with target 100 and current <current>
    Then the colour is "<colour>"

    Examples:
      | current | colour |
      | 97      | green  |
      | 96.9    | amber  |
      | 90      | amber  |
      | 89.9    | red    |

  Scenario: A wider tolerance turns amber into green
    Given the tolerance is 5%
    And a grow site has target 15.31 and current 14.8, which is 3.3% short
    Then the colour is "green"

  Scenario Outline: The tolerance must be sensible
    When I set the tolerance to <value>
    Then <result>

    Examples:
      | value | result                                                  |
      | 5     | it is saved                                             |
      | 0     | it is saved (every miss is flagged)                     |
      | -1    | it is rejected with "Tolerance must be between 0% and 50%" |
      | 60    | it is rejected with "Tolerance must be between 0% and 50%" |

  Scenario: A site with no reading or no target has no percent and no colour
    Given "Neck" has a target but no reading
    Then no percent and no colour are shown
