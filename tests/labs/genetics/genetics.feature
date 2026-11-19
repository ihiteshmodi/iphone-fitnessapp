Feature: Genotypes, read the vault's way
  As the owner (no genetic test yet)
  I want to pick each genotype from the vault's table once I test
  So that the vault's meaning, actions and extra blood tests follow, while the blood number still wins

  Scenario: Picking a genotype from the vault's table
    Given the vault's FUT2 table has "AA" (add MMA to the order)
    When I pick FUT2 AA
    Then FUT2 shows the vault's meaning and actions, and MMA is added to "From your genetics" in the order

  Scenario: Only genotypes from the table can be picked
    When I pick FUT2 "XY"
    Then I am told that genotype is not in the vault's table

  Scenario: A doctor-bucket genotype is a Fix item with its urgency
    Given G6PD deficient is "sameDay" in the vault
    When I pick it
    Then the Labs tab shows a Fix item with that urgency
