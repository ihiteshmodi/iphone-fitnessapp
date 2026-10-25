import sqlite3
from pathlib import Path

import openpyxl
import pytest

import build_seed_db

REAL_XLSX = Path(build_seed_db.DEFAULT_XLSX)

pytestmark = pytest.mark.skipif(not REAL_XLSX.exists(), reason="real workbook not available")

GOLDEN_DAY3_HEAVIEST_KG = {
    "Triceps Press": 45,
    "Triceps Pushdown": 45,
    "DB Overhead Triceps": 35,
    "Lat Pulldown": 36,
    "Vertical Pulldown - Black Machine": 60,
    "Power Row machine - Orange": 25,
    "T bar row - panatta machine": 15,
    "Chest Dips Machine": 54,
    "Reverse Lat Pulldown": 36,
    "Preacher Curls": 25,
    "Champagne Press": 30,
    "Guillotine press - incline black chest machine": 60,
    "Chest Fly Machine": 59,
    "Belt machine Stiff Leg Deadlift": 100,
    "Seated rows mid back": 40,
    "DB Hammer Curls": 12.5,
}
INCREASE_WEIGHT = {"Triceps Pushdown", "Reverse Lat Pulldown"}
BASELINE = "2026-08-31"


@pytest.fixture(scope="module")
def real(tmp_path_factory):
    out = tmp_path_factory.mktemp("real") / "fitness.sqlite"
    report = build_seed_db.build(REAL_XLSX, out)
    conn = sqlite3.connect(out)
    yield conn, report
    conn.close()


@pytest.fixture(scope="module")
def master_rows():
    wb = openpyxl.load_workbook(REAL_XLSX, data_only=True, read_only=True)
    raw = [tuple(r) + (None,) * (7 - len(r)) for r in wb["Master Sheet"].iter_rows(min_row=2, values_only=True)]
    wb.close()
    return raw


def scalar(conn, sql, *args):
    return conn.execute(sql, args).fetchone()[0]


def test_library_has_160_source_rows_of_which_case_insensitive_duplicates_are_merged(real):
    conn, report = real
    merged = [s for s in report.skipped if s.sheet == build_seed_db.LIBRARY_SHEET]
    stored = scalar(conn, "SELECT COUNT(*) FROM exercises WHERE source = 'library'")
    assert stored + len(merged) == 160
    # "Barbell Rows"/"Barbell rows" and "Weighted Pull Ups"/"Weighted pull ups" collide under COLLATE NOCASE
    assert len(merged) == 2


def test_plan_has_49_entries_split_17_16_16(real):
    conn, _ = real
    assert scalar(conn, "SELECT COUNT(*) FROM plan_entries") == 49
    assert dict(conn.execute(
        """SELECT d.position, COUNT(*) FROM plan_entries p JOIN plan_days d ON d.id = p.day_id
           GROUP BY d.position"""
    ).fetchall()) == {1: 17, 2: 16, 3: 16}


def test_plan_days_has_three_days_and_every_entry_points_at_one(real):
    conn, report = real
    assert conn.execute("SELECT position, weekday, title FROM plan_days ORDER BY position").fetchall() == [
        (1, None, None), (2, None, None), (3, None, None),
    ]
    assert scalar(conn, "SELECT COUNT(*) FROM plan_entries WHERE day_id NOT IN (SELECT id FROM plan_days)") == 0
    assert report.counts["plan_days"] == 3


def test_settings_carry_the_renamed_history_start_date_and_label_mode(real):
    conn, _ = real
    settings = dict(conn.execute("SELECT key, value FROM settings").fetchall())
    assert settings["history_start_date"] == "2026-08-31"
    assert settings["day_label_mode"] == "number"
    assert "baseline_date" not in settings


def test_body_tables_match_valid_source_rows(real, master_rows):
    conn, _ = real
    valid = lambda cat, col: sum(  # noqa: E731
        1 for r in master_rows
        if r[0] == cat and r[1] is not None and r[col] is not None and (cat == "Weight" or (r[2] and str(r[2]).strip()))
    )
    assert scalar(conn, "SELECT COUNT(*) FROM body_weights") == valid("Weight", 6)
    assert scalar(conn, "SELECT COUNT(*) FROM body_measurements") == valid("Body Measurement", 3)
    assert scalar(conn, "SELECT COUNT(*) FROM measurement_targets") == len(
        {str(r[2]).strip().lower() for r in master_rows if r[0] == "Target Measurement"}
    )
    assert scalar(conn, "SELECT COUNT(*) FROM measurement_targets") == 14


def test_set_logs_equal_exercise_rows_minus_skipped(real, master_rows):
    conn, report = real
    exercise_rows = sum(1 for r in master_rows if r[0] == "Exercise")
    skipped = sum(1 for s in report.skipped if s.table == "set_logs")
    assert exercise_rows == 7296
    assert scalar(conn, "SELECT COUNT(*) FROM set_logs") == exercise_rows - skipped


def test_integrity_checks_are_clean(real):
    conn, _ = real
    assert conn.execute("PRAGMA foreign_key_check").fetchall() == []
    assert conn.execute("PRAGMA integrity_check").fetchall() == [("ok",)]


def heaviest_set(conn, name):
    return conn.execute(
        """SELECT s.weight_kg, s.reps FROM set_logs s JOIN exercises e ON e.id = s.exercise_id
           WHERE e.name = ? AND s.performed_on >= ?
           ORDER BY s.weight_kg DESC, s.reps DESC LIMIT 1""",
        (name, BASELINE),
    ).fetchone()


@pytest.mark.parametrize("name,expected_kg", GOLDEN_DAY3_HEAVIEST_KG.items())
def test_golden_day3_heaviest_set_weight(real, name, expected_kg):
    conn, _ = real
    assert heaviest_set(conn, name) is not None, f"no sets on/after {BASELINE} for {name}"
    assert heaviest_set(conn, name)[0] == expected_kg


@pytest.mark.parametrize("name", GOLDEN_DAY3_HEAVIEST_KG)
def test_golden_day3_heaviest_set_reps_drive_the_recommendation(real, name):
    conn, _ = real
    plan = conn.execute(
        """SELECT p.min_reps, p.max_reps FROM plan_entries p JOIN exercises e ON e.id = p.exercise_id
           JOIN plan_days d ON d.id = p.day_id WHERE d.position = 3 AND e.name = ?""",
        (name,),
    ).fetchone()
    assert plan is not None, f"{name} is not on plan day 3"
    min_reps, max_reps = plan
    _, reps = heaviest_set(conn, name)
    if name in INCREASE_WEIGHT:
        assert max_reps == 10
        assert reps >= max_reps
    else:
        assert min_reps <= reps < max_reps
