-- Single source of truth for the Fitness database.
-- Used by the seed script (tools/seed-db) and embedded in the app (tests and first-run).
-- Dates are ISO text (YYYY-MM-DD). Weights are kg, measurements are inches.
PRAGMA foreign_keys = ON;

CREATE TABLE exercises (
    id           INTEGER PRIMARY KEY,
    name         TEXT NOT NULL UNIQUE COLLATE NOCASE,
    muscle       TEXT,
    instructions TEXT,
    -- library = "Exercise to muscle & instruction" sheet, log = only seen in the Master Sheet, user = created in the app
    source       TEXT NOT NULL DEFAULT 'library' CHECK (source IN ('library', 'log', 'user'))
);

-- A training day in the plan. The user can add, remove and reorder days.
-- weekday is ISO (1 = Monday ... 7 = Sunday) and optional; title is an optional free label such as "Pull + Chest".
CREATE TABLE plan_days (
    id       INTEGER PRIMARY KEY,
    position INTEGER NOT NULL UNIQUE CHECK (position >= 1),
    weekday  INTEGER CHECK (weekday BETWEEN 1 AND 7),
    title    TEXT
);

CREATE TABLE plan_entries (
    id          INTEGER PRIMARY KEY,
    day_id      INTEGER NOT NULL REFERENCES plan_days(id) ON DELETE CASCADE,
    position    INTEGER NOT NULL,
    exercise_id INTEGER NOT NULL REFERENCES exercises(id),
    sets        INTEGER NOT NULL CHECK (sets >= 1),
    min_reps    INTEGER NOT NULL CHECK (min_reps >= 0),
    max_reps    INTEGER NOT NULL,
    rep_type    TEXT,
    CHECK (min_reps <= max_reps),
    UNIQUE (day_id, exercise_id)
);

-- Muscles the user chose for one exercise. No rows for an exercise means "automatic": the app works them out from
-- the exercise's name and group. `part` is a MusclePart key (see src/modules/planning/muscle-anatomy).
CREATE TABLE exercise_muscles (
    exercise_id INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    part        TEXT NOT NULL,
    role        TEXT NOT NULL CHECK (role IN ('primary', 'secondary')),
    PRIMARY KEY (exercise_id, part)
);

CREATE TABLE set_logs (
    id             INTEGER PRIMARY KEY,
    performed_on   TEXT NOT NULL CHECK (performed_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    exercise_id    INTEGER NOT NULL REFERENCES exercises(id),
    weight_kg      REAL NOT NULL CHECK (weight_kg >= 0),
    reps           INTEGER NOT NULL CHECK (reps >= 0),
    -- muscle label as typed in the old Master Sheet; kept for fidelity, never used for analytics
    logged_muscle  TEXT,
    -- 1 when the set was logged while deload mode was on; can be left out of progress (setting ignore_deload_sessions)
    is_deload      INTEGER NOT NULL DEFAULT 0 CHECK (is_deload IN (0, 1))
);
CREATE INDEX idx_set_logs_exercise_date ON set_logs (exercise_id, performed_on);
CREATE INDEX idx_set_logs_date ON set_logs (performed_on);

CREATE TABLE body_weights (
    id          INTEGER PRIMARY KEY,
    measured_on TEXT NOT NULL CHECK (measured_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    weight_kg   REAL NOT NULL CHECK (weight_kg > 0)
);
CREATE INDEX idx_body_weights_date ON body_weights (measured_on);

CREATE TABLE body_measurements (
    id          INTEGER PRIMARY KEY,
    measured_on TEXT NOT NULL CHECK (measured_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    site        TEXT NOT NULL COLLATE NOCASE,
    inches      REAL NOT NULL CHECK (inches > 0)
);
CREATE INDEX idx_body_measurements_site_date ON body_measurements (site, measured_on);

-- direction: grow means at or above the target is achieved (shoulders, arms); reduce means at or below is (waist).
CREATE TABLE measurement_targets (
    site   TEXT PRIMARY KEY COLLATE NOCASE,
    inches REAL NOT NULL CHECK (inches > 0),
    set_on TEXT,
    direction TEXT NOT NULL DEFAULT 'grow' CHECK (direction IN ('grow', 'reduce'))
);

CREATE TABLE calorie_entries (
    logged_on  TEXT PRIMARY KEY CHECK (logged_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    calories   REAL NOT NULL CHECK (calories > 0),
    multiplier REAL NOT NULL DEFAULT 1 CHECK (multiplier > 0)
);

-- The calories per day that apply from a date onward (and the goal multiplier chosen with them). A day without a row
-- in calorie_entries uses the newest default whose effective_from is on or before it.
CREATE TABLE calorie_defaults (
    effective_from TEXT PRIMARY KEY CHECK (effective_from GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    calories       REAL NOT NULL CHECK (calories > 0),
    multiplier     REAL NOT NULL DEFAULT 1 CHECK (multiplier > 0)
);

CREATE TABLE settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Each setting is one independent knob. history_start_date affects every screen that looks at progress;
-- the deload_* settings only affect the workout targets.
INSERT INTO settings (key, value) VALUES
    ('history_start_date', '2026-08-31'),
    ('day_label_mode', 'number'),
    ('deload_enabled', '0'),
    ('deload_weight_multiplier', '1'),
    ('deload_reps_multiplier', '0.75'),
    ('ignore_deload_sessions', '1'),
    ('protein_g_per_lb', '1.2'),
    ('fat_percent_of_calories', '25');

PRAGMA user_version = 5;
