Feature: Explicit sex confirmation and strict sex-only filtering
  As the app owner
  I want Bloodwork to track whether sex has been explicitly confirmed and strictly hide opposite-sex bands, panels, markers, prep steps, and notes
  So that selecting Male shows only Male and All-Adults guidance, and selecting Female shows only Female and All-Adults guidance

  Scenario: Sex starts unconfirmed and becomes confirmed once saved
    Given a fresh database
    When I load Labs settings
    Then isSexConfirmed is false
    When I save sex as Male
    Then isSexConfirmed is true and sex is Male

  Scenario: Selecting Male hides all female bands, notes, prep steps, panels, and female-only markers
    Given a catalogue with Male, Female, and All-Adults bands, notes, prep steps, panels, and an AMH female-only marker
    When I filter for Male
    Then only Male and All-Adults bands, notes, prep steps, panels, and markers are visible
    And zero Female-only items appear

  Scenario: Selecting Female hides all male bands, panels, and male-only markers like PSA
    Given a catalogue with Male, Female, and All-Adults items and a PSA male-only marker
    When I filter for Female
    Then only Female and All-Adults items are visible
    And Male panels and PSA do not appear
