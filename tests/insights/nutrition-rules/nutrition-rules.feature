Feature: Nutrition rules
  As the lifter I want the hard rules from the Meridian vault (and two of my own) checked against what I eat and plan.

  Background:
    Given today is 2026-11-19 and a diet plan with Brunch and Dinner

  Scenario: Trans fat is flagged on the day it is eaten
    Given 4 Oreo biscuits with 0.9 g trans fat are eaten today
    Then Today has "Trans fat" (Fix) naming Oreo biscuit and 0.9 g

  Scenario: Leucine under 3 g in a protein meal
    Given yesterday Dinner had 30 g protein but 2.4 g leucine
    Then Today has "Leucine under 3 g" for Dinner, 2.4 g
    And a meal with no leucine value gives no data rather than a warning

  Scenario: Fiber under 14 g per 1000 calories
    Given yesterday was 2800 calories with 30 g fiber
    Then Today has "Fiber" saying 30 g of 39.2 g, with psyllium 1-2 tbsp with water as the fix

  Scenario: Fat under the range
    Given yesterday had 49 g fat for 2839 calories at 64.74 kg
    Then Today has "Fat under the range" saying 49 g of at least 63.1 g, and that fat-soluble vitamins need fat

  Scenario: EPA plus DHA under 250 mg
    Given yesterday's fish oil gave 0 mg because it was not ticked, and the rest of the day has EPA and DHA values
    Then Today has "EPA + DHA" saying 0 mg of 250 mg
    And a day where EPA and DHA are unknown gives no data

  Scenario: Caffeine late in the day
    Given coffee with 95 mg caffeine logged at Evening today
    Then Today has "Late caffeine" (Tip) saying stop 8-10 hours before bed

  Scenario: Flax and chia are not recommended for me
    Given chia seeds are eaten today
    Then Today has "Flax or chia" (Tip) calling it my own rule

  Scenario: Fewer than 3 protein meals in the plan
    Given the plan has 2 meals with at least 20 g protein
    Then Setup has "2 protein meals" (Improve) saying aim for 3-4, 3-5 hours apart

  Scenario: Fish oil form not rTG or algae
    Given the plan has a fish oil whose omega-3 form is unknown
    Then Setup has "Omega-3 form" (Tip) suggesting re-esterified triglyceride or algae
