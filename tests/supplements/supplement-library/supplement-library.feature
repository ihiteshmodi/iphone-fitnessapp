Feature: Supplement library and checks
  As the lifter I want every supplement the vault covers, recommended or not, searchable with its reason,
  my own supplements checked against it, and a what-if view for my multivitamin.

  Background:
    Given a library with Creatine (recommended, 3-5 g a day), Fadogia (not recommended) and Vitamin B12 (conditional, test first)

  Scenario: Search finds a supplement by name or alias, with its verdict and reason
    When I search "fadogia agrestis"
    Then I find Fadogia, not recommended, with its reason

  Scenario: My supplements are matched to the library
    Given my diet has "Creatine - ASES" 3 g a day
    Then it matches Creatine and its 3 g is within 3-5 g

  Scenario: A dose outside the vault's range or a not-recommended product is flagged
    Given my diet has "Creatine - ASES" 12 g a day and "Fadogia 600" 1 capsule
    Then Setup has "Supplement checks" saying Creatine is above 3-5 g and Fadogia is not recommended, with why

  Scenario: Test-first supplements are pointed to bloodwork
    Given my diet has "Vitamin B12 1500 mcg" 1 tablet
    Then Setup has a Tip that B12 should be tested first (Blood Labs)

  Scenario: One new supplement at a time
    Given Glycine was added to the plan on 2026-11-10 and Boron on 2026-11-17
    Then Setup has "One new supplement at a time" (Tip): wait 2-4 weeks between new ones

  Scenario: Multivitamin what if
    Given a multivitamin with vitamin D 25 mcg and zinc 15 mg per tablet and food giving zinc 10 mg
    When I look at 2 tablets
    Then vitamin D is 50 of 20 mcg (fat-soluble) and zinc 40 mg of 11 mg, at its 40 mg upper limit
    And at 3 tablets zinc is 55 mg, over the 40 mg upper limit
    And B6 shows two upper limits (100 mg US, 12 mg EU) and is not flagged until Labs settles it
