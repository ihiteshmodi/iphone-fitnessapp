Feature: Supplements that say "test first" show my real result
  As the owner
  I want each test a supplement asks for matched to my bloodwork
  So that I know at a glance whether I have the gap before buying or keeping it

  Scenario: A test name finds its marker and my latest result
    Given my ferritin was 40 ng/mL on 3 May 2026, and ferritin's optimal band is 60-140
    Then the test "Ferritin" reads "Ferritin 40 ng/mL on 3 May 2026 (low)"

  Scenario: Notes in brackets are read as well
    Then "B12 (check first)" finds B12, and "CBC (MCV)" finds MCV

  Scenario: Several tests in one name, and "blood", "serum" or "plasma" in front
    Then "Ferritin / B12" finds Ferritin and B12, and "serum ferritin (on high dose)" finds Ferritin

  Scenario: A test I have not done yet, and one the catalogue does not know
    Then "MMA" reads "not tested yet", and "DEXA" is shown as written

  Scenario: The supplement check names my results
    Given Vitamin B12 is in my plan and asks for "B12, MMA", and my B12 was 300 pg/mL
    Then the Test first item says "Vitamin B12 300 pg/mL on 3 May 2026" and "MMA not tested yet"
