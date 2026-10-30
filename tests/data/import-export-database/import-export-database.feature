Feature: Import and export the database
  As the lifter I want one file holding all my data so that I can back it up to Drive by hand.

  Scenario: First launch with no data
    Given the app has no database
    When I open it
    Then I see "Set up your data" with three choices: "Load my data", "Import a database file" and "Start empty"

  Scenario: Load the data shipped inside the app
    Given the app has no database
    When I tap "Load my data"
    Then Day 1, 2 and 3 show their exercises with the full history, without using any file picker

  Scenario: Start empty
    Given the app has no database
    When I tap "Start empty"
    Then the app opens with no days or history, and I can build my plan and log from scratch
    And an existing database is never replaced by "Start empty"

  Scenario: The database lives in the app's Documents folder
    Given I place fitness.sqlite in the app's data folder (Files app or LiveContainer "Open Data Folder")
    When I open the app
    Then it opens that database without importing
    And I can copy the same file out to Google Drive at any time

  Scenario: Import the seeded database
    Given I picked fitness.sqlite from Files
    When I import it
    Then Day 1, 2 and 3 show their exercises with history
    And a copy of any previous database is kept as a safety backup

  Scenario: Reject a file that is not a valid database
    Given I picked a PDF
    When I import it
    Then nothing changes and I see "This is not a Fitness database"

  Scenario: Reject a database from a newer app version
    Given the file has schema version 99
    When I import it
    Then nothing changes and I see "This database needs a newer app"

  Scenario: Export for the weekly Drive upload
    When I tap Export
    Then the share sheet offers a dated copy "fitness-2026-10-25.sqlite"
    And the live database is not locked or changed

  Scenario: Opening a database from before ticks keeps every earlier diet day as it was
    Given a version 8 database with a diet plan from 2026-10-26, Oats unticked on 2026-10-29, and activity up to 2026-10-30
    When the app opens it
    Then every planned item is ticked on 2026-10-26 to 2026-10-30 except Oats on 2026-10-29
    And days after 2026-10-30 have nothing ticked
    And the old skipped-items table is gone
    And opening it again changes nothing, so an item unticked afterwards stays unticked
