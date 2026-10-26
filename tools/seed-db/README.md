# seed-db

One-time tool: converts the Excel workbook into the SQLite seed database for the offline iOS app.

## Run

```
cd tools/seed-db
python3 -m venv .venv && .venv/bin/pip install openpyxl pandas pytest   # once
.venv/bin/python build_seed_db.py [--xlsx PATH] [--out PATH]
.venv/bin/python -m pytest
```

Defaults: workbook `current_artifacts/Data File - Single Line.xlsx`, output `output/fitness.seed.sqlite` (overwritten; the test fixture, so it never replaces `output/fitness.sqlite`, the real exported database the app bundles).
The database is created by executing `src/shared/database/schema.sql` verbatim. A summary (counts, skipped rows with sheet row numbers) is printed.

## Rules

- All text is trimmed; empty -> NULL. Exercise names match case-insensitively; the first-seen spelling is stored (library beats log). Variants like "Tricep"/"Triceps" are not merged.
- `exercises`: library sheet first (`source='library'`; case-insensitive duplicate rows are merged: first row wins, blanks filled from later rows), then log-only names (`source='log'`, muscle = most frequent non-blank log label, ties -> most recent row, none -> NULL).
- `plan_days`: one row per distinct V5 `Day` (position = Day number, weekday/title NULL). `plan_entries`: from `V5Fullbody_JMK`, linked via `day_id`, position = Exercise Number; a name missing from the library aborts the build.
- `set_logs`: Master Sheet `Exercise` rows in sheet order; rows lacking name/date/weight/reps are skipped and reported. Zero reps/weight are kept.
- `body_weights`, `body_measurements`, `measurement_targets` (latest date per site) from the matching categories; invalid rows are skipped and reported. `calorie_entries` stays empty.
- One transaction; `foreign_key_check` and `integrity_check` must be clean; ends with `VACUUM`.
