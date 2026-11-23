Feature: Training rules
  As the lifter I train three days a week and want the vault's hard training rules checked:
  day spacing, deloads, weekly sets per muscle, and the rate of a cut or bulk.

  Scenario: Back-to-back days that train the same muscle
    Given Monday "Push" (Bench press) and Tuesday "Arms" (Close-grip bench) both train chest and triceps
    Then Setup has "Back-to-back days" (Improve) naming Mon and Tue, chest and triceps
    And it explains the 48 h rule and the 24-48 h protein window, suggesting days like Mon/Wed/Fri
    And Monday and Wednesday training the same muscles say nothing

  Scenario: A key lift dropping two sessions in a row
    Given Bench press (the first exercise of Monday) best sets of 80x8, 77.5x8 and 75x8 in the last three sessions
    Then Setup has "Deload suggested" (Improve) saying Bench press dropped 2 sessions in a row
    And it offers to turn deload mode on

  Scenario: Weeks since the last deload
    Given the first set was logged 9 weeks ago and no deload was ever logged
    Then Setup has "Deload due" saying 9 weeks without a deload, every 4-8 weeks
    And with deload mode already on there is nothing

  Scenario: Weekly hard sets per muscle
    Given 6 sets of Bench press in the last 7 days
    Then Today has "Weekly sets" (Tip) saying Chest 6 sets, aim 10-20
    And when Calves is configured to 4-10 weekly sets and 6 calf sets are logged, Weekly sets does not flag Calves

  Scenario: A cut losing too fast
    Given I am cutting and the weekly average fell from 66.0 kg to 65.0 kg
    Then Setup has "Cutting fast" (Tip) saying 1.5% a week, aim 0.5-1%
