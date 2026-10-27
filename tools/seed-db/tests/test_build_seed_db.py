import sqlite3

import pytest

import build_seed_db
from workbook_helpers import D, exercise_row, measurement_row, plan_row, target_row, weight_row


def rows(conn, sql):
    return conn.execute(sql).fetchall()


def test_schema_is_applied_with_settings_and_version(build):
    conn, _ = build()
    assert conn.execute("PRAGMA user_version").fetchone()[0] == 7
    settings = dict(rows(conn, "SELECT key, value FROM settings"))
    assert settings["history_start_date"] == "2026-08-31"
    assert settings["day_label_mode"] == "number"
    assert settings["ignore_deload_sessions"] == "1"
    assert "baseline_date" not in settings
    assert len(settings) == 8


def test_imported_sets_are_not_tagged_as_deload(build):
    conn, _ = build()
    assert rows(conn, "SELECT COUNT(*) FROM set_logs WHERE is_deload != 0") == [(0,)]


def test_no_muscles_are_chosen_so_every_exercise_is_automatic(build):
    conn, _ = build()
    assert rows(conn, "SELECT COUNT(*) FROM exercise_muscles") == [(0,)]


def test_library_rows_are_inserted_trimmed_with_library_source(build):
    conn, _ = build()
    assert rows(conn, "SELECT name, muscle, instructions, source FROM exercises ORDER BY id") == [
        ("Machine Shoulder Press", "Shoulders", "seat 3", "library"),
        ("Lat Pulldown", "Back", None, "library"),
    ]


def test_blank_library_cells_become_null(spec, build):
    spec.library.append(["  Cable Fly ", "   ", ""])
    conn, _ = build()
    assert rows(conn, "SELECT name, muscle, instructions FROM exercises WHERE name = 'Cable Fly'") == [
        ("Cable Fly", None, None)
    ]


def test_case_insensitive_library_duplicates_keep_first_row_and_fill_its_blanks(spec, build):
    spec.library += [
        ["barbell rows", "Back", None],
        ["Barbell Rows ", "Back", "wide grip"],
        ["BARBELL ROWS", "Legs", "ignored: first non-blank wins"],
    ]
    conn, report = build()
    assert rows(conn, "SELECT name, muscle, instructions FROM exercises WHERE name = 'barbell rows'") == [
        ("barbell rows", "Back", "wide grip")
    ]
    assert [s.row for s in report.skipped] == [5, 6]
    assert report.counts["exercises"] == 3


def test_log_name_matches_library_case_and_whitespace_insensitively(spec, build):
    spec.master = [exercise_row(D(2026, 9, 1), "machine shoulder press ", 10, 20.0, "Shoulders")]
    conn, report = build()
    assert rows(conn, "SELECT name FROM exercises WHERE source = 'log'") == []
    assert rows(conn, "SELECT e.name FROM set_logs s JOIN exercises e ON e.id = s.exercise_id") == [
        ("Machine Shoulder Press",)
    ]
    assert report.log_only_created == 0


def test_log_only_exercise_gets_majority_muscle_label(spec, build):
    spec.master = [
        exercise_row(D(2026, 1, 1), "Cable Fly", 10, 10.0, "Arms"),
        exercise_row(D(2026, 1, 2), "cable fly", 10, 10.0, "Chest"),
        exercise_row(D(2026, 1, 3), "Cable Fly ", 10, 10.0, "Chest"),
        exercise_row(D(2026, 1, 4), "Cable Fly", 10, 10.0, None),
    ]
    conn, report = build()
    assert rows(conn, "SELECT name, muscle, instructions, source FROM exercises WHERE source = 'log'") == [
        ("Cable Fly", "Chest", None, "log")
    ]
    assert report.log_only_created == 1


def test_log_only_muscle_tie_is_broken_by_most_recent_row(spec, build):
    spec.master = [
        exercise_row(D(2026, 1, 1), "Cable Fly", 10, 10.0, "Chest"),
        exercise_row(D(2026, 1, 2), "Cable Fly", 10, 10.0, "Arms"),
    ]
    conn, _ = build()
    assert rows(conn, "SELECT muscle FROM exercises WHERE name = 'Cable Fly'") == [("Arms",)]


def test_log_only_muscle_tie_uses_sheet_position_for_recency(spec, build):
    spec.master = [
        exercise_row(D(2026, 1, 2), "Cable Fly", 10, 10.0, "Arms"),
        exercise_row(D(2026, 1, 1), "Cable Fly", 10, 10.0, "Chest"),
    ]
    conn, _ = build()
    # recency means the later date, not the later sheet row
    assert rows(conn, "SELECT muscle FROM exercises WHERE name = 'Cable Fly'") == [("Arms",)]


def test_log_only_exercise_with_only_blank_labels_has_null_muscle(spec, build):
    spec.master = [exercise_row(D(2026, 1, 1), "Cable Fly", 10, 10.0, " ")]
    conn, report = build()
    assert rows(conn, "SELECT muscle FROM exercises WHERE name = 'Cable Fly'") == [(None,)]
    assert report.null_muscle_exercises == 1


def test_first_seen_spelling_wins_and_variants_are_not_merged(spec, build):
    spec.master = [
        exercise_row(D(2026, 1, 1), "Tricep Pushdown", 10, 10.0),
        exercise_row(D(2026, 1, 2), "triceps pushdown", 10, 10.0),
        exercise_row(D(2026, 1, 3), "TRICEP PUSHDOWN", 10, 10.0),
    ]
    conn, _ = build()
    assert rows(conn, "SELECT name FROM exercises WHERE source = 'log' ORDER BY id") == [
        ("Tricep Pushdown",),
        ("triceps pushdown",),
    ]


def test_rows_without_name_weight_reps_or_date_are_skipped_and_reported(spec, build):
    spec.master = [
        exercise_row(D(2026, 1, 1), "Lat Pulldown", 10, 30.0),  # sheet row 2
        exercise_row(D(2026, 1, 1), "  ", 10, 30.0),  # row 3: blank name
        exercise_row(D(2026, 1, 1), "Lat Pulldown", 10, None),  # row 4: no weight
        exercise_row(D(2026, 1, 1), "Lat Pulldown", None, 30.0),  # row 5: no reps
        exercise_row(None, "Lat Pulldown", 10, 30.0),  # row 6: no date
    ]
    conn, report = build()
    assert rows(conn, "SELECT COUNT(*) FROM set_logs") == [(1,)]
    assert [(s.sheet, s.row) for s in report.skipped] == [
        ("Master Sheet", 3), ("Master Sheet", 4), ("Master Sheet", 5), ("Master Sheet", 6),
    ]
    assert all(s.reason for s in report.skipped)


def test_exercise_name_seen_only_in_skipped_rows_is_still_a_log_exercise(spec, build):
    spec.master = [exercise_row(D(2026, 1, 1), "Ghost Move", 10, None, "Core")]
    conn, report = build()
    assert rows(conn, "SELECT muscle, source FROM exercises WHERE name = 'Ghost Move'") == [("Core", "log")]
    assert rows(conn, "SELECT COUNT(*) FROM set_logs") == [(0,)]
    assert report.log_only_created == 1


def test_zero_reps_and_zero_weight_rows_are_kept(spec, build):
    spec.master = [
        exercise_row(D(2026, 1, 1), "Lat Pulldown", 0, 30.0),
        exercise_row(D(2026, 1, 2), "Lat Pulldown", 10, 0),
    ]
    conn, report = build()
    assert rows(conn, "SELECT reps, weight_kg FROM set_logs ORDER BY id") == [(0, 30.0), (10, 0.0)]
    assert report.skipped == []


def test_reps_are_stored_as_integers(spec, build):
    spec.master = [exercise_row(D(2026, 1, 1), "Lat Pulldown", 10.0, 30.5)]
    conn, _ = build()
    assert rows(conn, "SELECT typeof(reps), reps, weight_kg FROM set_logs") == [("integer", 10, 30.5)]


def test_dates_are_converted_to_iso_from_datetime_and_string_cells(spec, build):
    spec.master = [
        exercise_row(D(2026, 9, 1, 0, 0), "Lat Pulldown", 10, 30.0),
        exercise_row("2026-09-02", "Lat Pulldown", 10, 30.0),
        exercise_row("2026-09-03 00:00:00", "Lat Pulldown", 10, 30.0),
        exercise_row(D(2026, 9, 4, 13, 45), "Lat Pulldown", 10, 30.0),
        weight_row("2026-09-05T08:00:00", 70.0),
    ]
    conn, _ = build()
    assert [r[0] for r in rows(conn, "SELECT performed_on FROM set_logs ORDER BY id")] == [
        "2026-09-01", "2026-09-02", "2026-09-03", "2026-09-04",
    ]
    assert rows(conn, "SELECT measured_on FROM body_weights") == [("2026-09-05",)]


def test_unparseable_date_is_skipped_and_reported(spec, build):
    spec.master = [exercise_row("not a date", "Lat Pulldown", 10, 30.0)]
    conn, report = build()
    assert rows(conn, "SELECT COUNT(*) FROM set_logs") == [(0,)]
    assert len(report.skipped) == 1


def test_set_log_ids_follow_sheet_order_not_date_order(spec, build):
    spec.master = [
        exercise_row(D(2026, 3, 1), "Lat Pulldown", 10, 31.0),
        weight_row(D(2026, 3, 1), 70.0),
        exercise_row(D(2026, 1, 1), "Lat Pulldown", 10, 32.0),
        exercise_row(D(2026, 2, 1), "Lat Pulldown", 10, 33.0),
    ]
    conn, _ = build()
    assert rows(conn, "SELECT id, weight_kg FROM set_logs ORDER BY id") == [(1, 31.0), (2, 32.0), (3, 33.0)]


def test_logged_muscle_is_trimmed_or_null(spec, build):
    spec.master = [
        exercise_row(D(2026, 1, 1), "Lat Pulldown", 10, 30.0, " Back "),
        exercise_row(D(2026, 1, 2), "Lat Pulldown", 10, 30.0, None),
    ]
    conn, _ = build()
    assert rows(conn, "SELECT logged_muscle FROM set_logs ORDER BY id") == [("Back",), (None,)]


def test_body_weights_and_measurements_are_loaded_and_invalid_rows_skipped(spec, build):
    spec.master = [
        weight_row(D(2026, 1, 1), 70.5),
        weight_row(D(2026, 1, 2), None),
        measurement_row(D(2026, 1, 1), " Waist ", 33.5),
        measurement_row(D(2026, 1, 1), None, 33.5),
        measurement_row(D(2026, 1, 1), "Chest", None),
    ]
    conn, report = build()
    assert rows(conn, "SELECT measured_on, weight_kg FROM body_weights") == [("2026-01-01", 70.5)]
    assert rows(conn, "SELECT measured_on, site, inches FROM body_measurements") == [("2026-01-01", "Waist", 33.5)]
    assert [s.row for s in report.skipped] == [3, 5, 6]
    assert rows(conn, "SELECT COUNT(*) FROM calorie_entries") == [(0,)]


def test_target_keeps_latest_date_per_site(spec, build):
    spec.master = [
        target_row(D(2022, 12, 18), "Waist", 28.0),
        target_row(D(2024, 1, 1), "waist", 29.0),
        target_row(D(2023, 1, 1), "WAIST ", 27.0),
        target_row(D(2022, 12, 18), "Chest", 40.0),
    ]
    conn, _ = build()
    assert rows(conn, "SELECT site, inches, set_on FROM measurement_targets ORDER BY site") == [
        ("Chest", 40.0, "2022-12-18"),
        ("waist", 29.0, "2024-01-01"),
    ]


def test_waist_type_targets_are_reduce_sites_and_the_rest_grow(spec, build):
    spec.master = [
        target_row(D(2022, 12, 18), "Waist", 28.0),
        target_row(D(2022, 12, 18), "waist (belly Button)", 30.0),
        target_row(D(2022, 12, 18), "Shoulders", 45.3),
    ]
    conn, _ = build()
    assert dict(rows(conn, "SELECT site, direction FROM measurement_targets")) == {
        "Waist": "reduce",
        "waist (belly Button)": "reduce",
        "Shoulders": "grow",
    }


def test_plan_entries_are_loaded_by_exercise_name(spec, build):
    spec.plan = [
        plan_row(1, 1, "lat pulldown ", sets=2, min_reps=6, max_reps=10, rep_type=" "),
        plan_row(2, 1, "Machine Shoulder Press", rep_type="Drop"),
    ]
    conn, _ = build()
    assert rows(conn, """SELECT d.position, p.position, e.name, p.sets, p.min_reps, p.max_reps, p.rep_type
                         FROM plan_entries p JOIN exercises e ON e.id = p.exercise_id
                         JOIN plan_days d ON d.id = p.day_id ORDER BY p.id""") == [
        (1, 1, "Lat Pulldown", 2, 6, 10, None),
        (2, 1, "Machine Shoulder Press", 3, 8, 12, "Drop"),
    ]


def test_one_plan_day_per_distinct_day_number_with_null_weekday_and_title(spec, build):
    spec.plan = [
        plan_row(3, 1, "Lat Pulldown"),
        plan_row(1, 1, "Lat Pulldown"),
        plan_row(1, 2, "Machine Shoulder Press"),
        plan_row(2, 1, "Lat Pulldown"),
    ]
    conn, report = build()
    assert rows(conn, "SELECT position, weekday, title FROM plan_days ORDER BY position") == [
        (1, None, None), (2, None, None), (3, None, None),
    ]
    assert report.counts["plan_days"] == 3


def test_plan_entries_point_at_their_day_and_keep_the_exercise_number_as_position(spec, build):
    spec.plan = [plan_row(2, 5, "Lat Pulldown"), plan_row(1, 7, "Lat Pulldown")]
    conn, _ = build()
    assert rows(conn, """SELECT d.position, p.position FROM plan_entries p
                         JOIN plan_days d ON d.id = p.day_id ORDER BY p.id""") == [(2, 5), (1, 7)]
    assert rows(conn, "SELECT COUNT(*) FROM plan_entries WHERE day_id NOT IN (SELECT id FROM plan_days)") == [(0,)]


def test_plan_exercise_missing_from_library_fails_loudly_with_the_name(spec, tmp_path):
    spec.plan = [plan_row(1, 1, "Mystery Move")]
    spec.master = [exercise_row(D(2026, 1, 1), "Mystery Move", 10, 10.0)]  # log presence must not rescue it
    xlsx = spec.write(tmp_path / "in.xlsx")
    with pytest.raises(build_seed_db.MissingLibraryExercise, match="Mystery Move"):
        build_seed_db.build(xlsx, tmp_path / "out.sqlite")


def test_foreign_key_check_and_integrity_are_clean(spec, build):
    spec.plan = [plan_row(1, 1, "Lat Pulldown")]
    spec.master = [exercise_row(D(2026, 1, 1), "New Move", 10, 10.0), weight_row(D(2026, 1, 1), 70.0)]
    conn, _ = build()
    assert rows(conn, "PRAGMA foreign_key_check") == []
    assert rows(conn, "PRAGMA integrity_check") == [("ok",)]


def test_existing_output_file_is_overwritten(spec, tmp_path):
    xlsx = spec.write(tmp_path / "in.xlsx")
    out = tmp_path / "out.sqlite"
    out.write_text("garbage")
    build_seed_db.build(xlsx, out)
    assert sqlite3.connect(out).execute("SELECT COUNT(*) FROM exercises").fetchone() == (2,)


def test_report_counts_per_table(spec, build):
    spec.master = [exercise_row(D(2026, 1, 1), "Lat Pulldown", 10, 10.0), weight_row(D(2026, 1, 1), 70.0)]
    spec.plan = [plan_row(1, 1, "Lat Pulldown")]
    _, report = build()
    assert report.counts["exercises"] == 2
    assert report.counts["set_logs"] == 1
    assert report.counts["body_weights"] == 1
    assert report.counts["plan_entries"] == 1
    assert report.counts["calorie_entries"] == 0
