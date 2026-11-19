Feature: Load past lab reports
  As the owner with reports going back to 2022
  I want them loaded once from a private file
  So that trends and retest timing start from real results

  Scenario: Results become draws by date and lab
    Given a file with two results on 3 May 2026 at one lab and one on 1 Oct 2026 at another
    When I apply it
    Then two draws exist with those results and their lab ranges

  Scenario: Applying twice adds nothing
    When I apply the same file again
    Then no new draw or result is added

  Scenario: Unknown markers or units are skipped with a reason
    Given a row for a marker the catalogue does not have
    Then that row is skipped and listed, and the rest load

  Scenario: The date of birth setting is applied
    Given a setting row "labs_birth_date,1998-06-09"
    Then Labs settings hold that date of birth
