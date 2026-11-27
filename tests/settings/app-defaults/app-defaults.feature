Feature: Centralized AppDefaultsStore, Meal Timestamps (ate_at), Check-In Cutoffs, and Full Domain Editability

  As the iPhone owner customizing rules and fixing past logs without deleting and re-creating entries
  I want editable meal timestamps, caffeine/alcohol check-ins, centralized AppDefaultsStore settings, and in-place editing for genotypes, custom genes, marker optimal overrides, and saved lab names
  So every user-controlled entry and threshold can be corrected or tuned in place.

  Scenario: Retroactive meal confirmation uses configurable default meal time and supports editing ate_at for Last-Meal-to-Sleep gap
    Given AppDefaultsStore sets default meal time for "Dinner" to "20:00" and "Brunch" to "12:30"
    When I confirm yesterday's unlogged "Dinner" (containing 65g carbs) and edit its ate_at time to "21:30"
    And sleep onset that night is 23:45 (gap 2.25h < 3.0h)
    Then LastMealToSleepEvaluator flags a "< 3 h before bed" warning with 2.25h gap and 65g last-meal carbs
    When I update yesterday's "Dinner" ate_at in place to "19:15" (gap 4.5h)
    Then LastMealToSleepEvaluator reports Optimal (4–6h window) with 65g carbs

  Scenario: Genetics, custom genes, marker optimal overrides, and saved lab names are editable in place
    Given MTHFR is logged as "C677T TT" on 2026-10-01
    When I update MTHFR in place with custom genotype text "C677T TT + A1298C WT", date 2026-09-15, lab "MapMyGenome", and note "Clinical panel"
    And I add a custom gene "COMT" ("Val158Met Met/Met"), then update its note in place
    And I set a personal optimal override on "ferritin" (80..130 ng/mL) and rename saved lab "Helthians" to "Healthians Labs"
    Then all edits persist in place without deleting or losing surrounding records

  Scenario: AppDefaultsStore persists meal defaults, cutoffs, 1-Mile Max HR, manual HR zones, HIIT presets, stepTicksPerStep, and 7-day silent alarms
    When I save custom settings in AppDefaultsStore and schedule a weekday alarm with +12s strap clock drift
    Then reloading AppDefaultsStore returns every updated setting and builds a 0x42 alarm frame compensated into the strap's RTC frame
