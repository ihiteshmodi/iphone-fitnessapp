Feature: Sweaty-activity bottle
  As the lifter my daily workout mix stays as it is, but for a long sweaty hike I want to know what to put in the water I carry.

  Scenario: A 4-hour hike with heavy sweating, carrying 3 litres
    When I plan 4 hours of heavy sweating with a 3 litre bottle
    Then it suggests 2000-2800 mg sodium, about 5.3-7.4 g Himalayan salt
    And 320-900 mg potassium, about 0.6-1.7 g potassium chloride, spread across the 3 litres
    And to sip 180-360 mL every 15-20 minutes

  Scenario: Light sweating uses the low end
    When I plan 2 hours of light sweating with a 1 litre bottle
    Then it suggests 600 mg sodium, about 1.6 g Himalayan salt

  Scenario: The inputs must make sense
    When I plan 0 hours
    Then I am told "Enter how long the activity is"
