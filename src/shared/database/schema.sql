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
    -- sets = main sets (logged and counted). warmup_sets are reference only: shown with weights, never logged.
    warmup_sets INTEGER NOT NULL DEFAULT 0 CHECK (warmup_sets BETWEEN 0 AND 3),
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

-- The answer to "did every rep have a full contraction?", asked once per exercise per day when the top of the rep
-- range is reached. 1 = clean, 0 = not clean. No row means it was never asked (older sessions count as clean).
CREATE TABLE form_checks (
    exercise_id  INTEGER NOT NULL REFERENCES exercises(id) ON DELETE CASCADE,
    performed_on TEXT NOT NULL CHECK (performed_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    clean        INTEGER NOT NULL CHECK (clean IN (0, 1)),
    PRIMARY KEY (exercise_id, performed_on)
);

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

-- A food, a supplement or a recipe. Nutrition is for base_qty of the food's unit (100 for grams, 1 for a capsule or a piece).
-- label_calories is what the pack says; when it is empty calories are worked out as 4 x protein + 4 x carbs + 9 x fat.
-- price is for one pack of pack_size units. pieces_per_pack and piece_weight let "4 biscuits" become grams.
-- A recipe (kind = 'recipe') has no nutrition of its own: it is worked out from recipe_items and divided by recipe_makes units.
CREATE TABLE foods (
    id              INTEGER PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE COLLATE NOCASE,
    kind            TEXT NOT NULL DEFAULT 'food' CHECK (kind IN ('food', 'topping', 'supplement', 'herb', 'liquid', 'packaged', 'recipe')),
    unit            TEXT NOT NULL DEFAULT 'g',
    base_qty        REAL NOT NULL DEFAULT 100 CHECK (base_qty > 0),
    protein         REAL NOT NULL DEFAULT 0 CHECK (protein >= 0),
    carbs           REAL NOT NULL DEFAULT 0 CHECK (carbs >= 0),
    fat             REAL NOT NULL DEFAULT 0 CHECK (fat >= 0),
    fiber           REAL NOT NULL DEFAULT 0 CHECK (fiber >= 0),
    sat_fat         REAL NOT NULL DEFAULT 0 CHECK (sat_fat >= 0),
    sodium          REAL NOT NULL DEFAULT 0 CHECK (sodium >= 0),
    label_calories  REAL CHECK (label_calories IS NULL OR label_calories >= 0),
    price           REAL CHECK (price IS NULL OR price >= 0),
    pack_size       REAL CHECK (pack_size IS NULL OR pack_size > 0),
    pieces_per_pack REAL CHECK (pieces_per_pack IS NULL OR pieces_per_pack > 0),
    piece_weight    REAL CHECK (piece_weight IS NULL OR piece_weight > 0),
    recipe_makes    REAL CHECK (recipe_makes IS NULL OR recipe_makes > 0),
    notes           TEXT
);

CREATE TABLE recipe_items (
    recipe_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
    food_id   INTEGER NOT NULL REFERENCES foods(id) ON DELETE RESTRICT,
    position  INTEGER NOT NULL DEFAULT 1,
    quantity  REAL NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (recipe_id, food_id)
);

-- The plan applies from effective_from onward until a newer plan starts (the same idea as calorie_defaults).
CREATE TABLE diet_plans (
    effective_from TEXT PRIMARY KEY CHECK (effective_from GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]')
);

-- cycle_mode: daily = every day; weeks and days count cycle_on / cycle_off from cycle_start (a Monday for weeks);
-- weekdays uses the cycle_weekdays bit mask (Monday = 1 ... Sunday = 64); training follows the workout plan's weekdays.
CREATE TABLE diet_plan_items (
    id             INTEGER PRIMARY KEY,
    plan_from      TEXT NOT NULL REFERENCES diet_plans(effective_from) ON DELETE CASCADE,
    meal           TEXT NOT NULL,
    position       INTEGER NOT NULL,
    food_id        INTEGER NOT NULL REFERENCES foods(id) ON DELETE RESTRICT,
    quantity       REAL NOT NULL CHECK (quantity > 0),
    cycle_mode     TEXT NOT NULL DEFAULT 'daily' CHECK (cycle_mode IN ('daily', 'weeks', 'days', 'weekdays', 'training')),
    cycle_on       INTEGER CHECK (cycle_on IS NULL OR cycle_on >= 1),
    cycle_off      INTEGER CHECK (cycle_off IS NULL OR cycle_off >= 1),
    cycle_start    TEXT CHECK (cycle_start IS NULL OR cycle_start GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    cycle_weekdays INTEGER CHECK (cycle_weekdays IS NULL OR cycle_weekdays BETWEEN 1 AND 127)
);

-- A planned item unticked for one day.
CREATE TABLE diet_day_skips (
    day     TEXT NOT NULL CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    meal    TEXT NOT NULL,
    food_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE CASCADE,
    PRIMARY KEY (day, meal, food_id)
);

-- Something eaten on top of the plan. amount is in the food's unit (grams for a packet); pieces is only for showing.
CREATE TABLE diet_extras (
    id      INTEGER PRIMARY KEY,
    day     TEXT NOT NULL CHECK (day GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
    food_id INTEGER NOT NULL REFERENCES foods(id) ON DELETE RESTRICT,
    amount  REAL NOT NULL CHECK (amount > 0),
    pieces  REAL CHECK (pieces IS NULL OR pieces > 0)
);
CREATE INDEX diet_extras_by_day ON diet_extras(day);

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
    ('fat_percent_of_calories', '25'),
    ('protein_min_g', '180'),
    ('diet_fat_percent', '20'),
    ('fat_ceiling_g_per_lb', '0.4');

PRAGMA user_version = 8;
