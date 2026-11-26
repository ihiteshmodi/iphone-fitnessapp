Feature: WHOOP SQLite substrate (whoop.sqlite), atomic pre-ACK commit, and OpenStrap export import/export
  As the owner storing multi-month 1 Hz biometrics and RR intervals alongside my Fitness database
  I want an isolated whoop.sqlite database matching OpenStrap's exact schema with atomic pre-ACK commits and 1-tap import/export
  So that my 547k+ row OpenStrap history loads cleanly and my weekly fitness.sqlite backup stays ~1 MB

  Scenario: Atomic commitSyncBatch replaces 1 Hz rows, deletes and re-inserts replaced RR beats without orphans, archives undecodable/dropped frames, and updates cursors
    Given an empty WhoopDatabase
    When a batch commits 1 Hz second 1795113155 with 3 RR beats, then a re-delivered batch replaces second 1795113155 with 2 RR beats and archives a v26 frame
    Then decoded_onehz holds 1 row for 1795113155, decoded_rr holds strictly the 2 new beats (zero stale beat_index = 2 orphan), raw_archive_frames deduplicates by SHA-1 hash, and sync_cursor advances counter_hw, rec_ts_hw, and strap_trim

  Scenario: Failed commit rolls back completely so TrimAckPolicy refuses flash trim
    When a batch fails mid-transaction
    Then zero partial rows or cursor updates persist

  Scenario: Importing the real openstrap_export database preserves all 547,574 decoded_onehz rows, 328,371 decoded_rr rows, cursors, and battery/backlog telemetry
    Given openstrap_export_1795700891234.db
    When WhoopDatabaseFileService validates and opens/imports it
    Then summary telemetry reports the exact row counts, latest battery, and latest sync cursor, and exporting writes a clean dated whoop-YYYY-MM-DD.sqlite snapshot
