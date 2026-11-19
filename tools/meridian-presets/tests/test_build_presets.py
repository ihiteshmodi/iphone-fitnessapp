import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from build_presets import parse_prescription, parse_reps, routines, workouts  # noqa: E402


def test_prescriptions_become_sets_and_a_rep_range():
    assert parse_prescription("4×10 @1 - 2 RIR") == (4, 10, 10)
    assert parse_prescription("2×6 - 8 @0 - 2 RIR") == (2, 6, 8)
    assert parse_prescription("1×10:00") is None
    assert parse_reps("6-8") == (6, 8)


def test_timed_stretching_is_left_out_and_names_say_where_they_came_from():
    data = {"routines": [{"name": "Push", "exercises": [
        {"name": "Stretching (Upper)", "prescription": "1×8-10 @2-3 RIR"},
        {"name": "Chest Press (Machine)", "prescription": "4×10 @1 - 2 RIR"}]}]}
    assert routines(data) == [{"name": "Meridian · Push", "exercises": [
        {"name": "Chest Press (Machine)", "sets": 4, "min_reps": 10, "max_reps": 10}]}]


def test_workout_days_keep_their_weekday():
    data = {"workouts": [{"name": "4-Day Upper/Lower", "days": [{"weekday": "Monday", "name": "Upper", "exercises": [
        {"name": "Stretching (Upper)", "sets": None, "reps": None, "duration": "10 min"},
        {"name": "Preacher Curl (Machine)", "sets": 2, "reps": "6-8", "duration": None}]}]}]}
    assert workouts(data)[0]["days"] == [{"title": "Upper", "weekday": 1, "exercises": [
        {"name": "Preacher Curl (Machine)", "sets": 2, "min_reps": 6, "max_reps": 8}]}]
