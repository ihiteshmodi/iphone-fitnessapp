Feature: Calorie target
  As the lifter I want my maintenance calories estimated from my weight trend
  so that I can set next week's calories.

  Background:
    Given body weights are averaged over the 7 days ending at the latest weigh-in
    And compared with the 7 days before that
    And 1 lb of body weight is 3500 calories and 454 g

  Scenario: Weight is dropping, so the phase is Cut
    Given the latest 7-day average is 63.86 kg and the previous 7-day average is 63.94 kg
    And I ate 2948.5 calories per day with multiplier 1
    When I calculate my calorie target
    Then estimated maintenance is 3036.61 calories
    And the phase is "Cut" with a daily deficit of 88.11 calories
    And the new target is 3037 calories

  Scenario: Weight is rising
    Given the latest 7-day average is 64.5 kg and the previous 7-day average is 64.0 kg
    And I ate 3000 calories per day with multiplier 1
    When I calculate my calorie target
    Then the phase is "Maintenance / Bulk" with a daily surplus of 550.66 calories
    And estimated maintenance is 2449.34 calories

  Scenario: Cutting multiplier adds macros
    Given the latest 7-day average is 63.86 kg and the previous 7-day average is 63.94 kg
    And I ate 2948.5 calories per day with multiplier 0.8
    When I calculate my calorie target
    Then the target is 2429 calories
    And protein is 168.59 g (674.36 cal), fat is 67.47 g (607.25 cal), carbs are 286.85 g (1147.39 cal)

  Scenario: Not enough weigh-ins
    Given there are no weigh-ins in the previous 7 days
    When I calculate my calorie target
    Then I am told "Log body weight for both of the last two weeks"
