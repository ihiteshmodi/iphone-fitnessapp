Feature: Read a result the vault's way
  As the owner
  I want each result placed on the vault's bands, with its doctor lines checked
  So that I see where I stand without the app inventing a single number

  Background:
    Given a fixture marker "Ferritin" in ng/mL with:
      | band    | kind    | low | high | sex    | dispute |
      | Lab     | lab     | 30  | 400  | any    |         |
      | Optimal | optimal | 60  | 140  | male   | C900    |
      | Optimal | optimal | 80  | 150  | male   | C900    |
      | Women   | optimal | 40  | 100  | female |         |
    And doctor lines "above 900 soon" and "above 1500 same day"

  Scenario: Inside every optimal band
    When I read 100 ng/mL for a man
    Then it is optimal

  Scenario: In the gap between two disputed bands (D1)
    When I read 70 ng/mL for a man
    Then it is disputed, with both bands and their dispute ID, and no flag

  Scenario: Outside the optimal bands
    When I read 50 ng/mL for a man
    Then it is low; at 160 it is high

  Scenario: On a shared edge (D3)
    Given bands "Watch 20-25" and "Flag 25-40" on another marker
    When I read exactly 25
    Then both band names are shown

  Scenario: Doctor lines, most urgent first (D2)
    When I read 1600 ng/mL
    Then both doctor lines are crossed and "Same day" comes first

  Scenario: Other units convert only by the catalogue's factor
    When I read 100 µg/L (factor 1)
    Then it reads like 100 ng/mL
    And a band with no unit is never compared (D4)

  Scenario: Female bands are ignored for a man
    When I read 45 ng/mL for a man
    Then the women's band is not used
