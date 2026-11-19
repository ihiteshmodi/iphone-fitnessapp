"""Turn the Meridian "Train & Eat" export (coach_routines.json, workouts.json) into output/meridian-presets.json.

The export is a paid program's content, so neither it nor the presets file is committed: the file lands in output/
(git-ignored) and the app build bundles it when it is there. Usage:

    python tools/meridian-presets/build_presets.py "/path/to/Train & Eat"
"""
import json
import re
import sys
from pathlib import Path

WEEKDAYS = {"monday": 1, "tuesday": 2, "wednesday": 3, "thursday": 4, "friday": 5, "saturday": 6, "sunday": 7}


def is_timed(name):
    """Stretching is done for minutes, not for sets and reps, so it is not an exercise the app logs."""
    return name.lower().startswith("stretching")


def parse_reps(text):
    """'10' -> (10, 10); '6-8' or '6 - 8' -> (6, 8)."""
    numbers = [int(n) for n in re.findall(r"\d+", text)]
    if not numbers:
        return None
    return numbers[0], numbers[1] if len(numbers) > 1 else numbers[0]


def parse_prescription(text):
    """'4×10 @1 - 2 RIR' -> (4, 10, 10); '2×6 - 8 @0 - 2 RIR' -> (2, 6, 8); '1×10:00' (a duration) -> None."""
    match = re.match(r"\s*(\d+)\s*[×x]\s*([^@]+)", text)
    if not match or ":" in match.group(2):
        return None
    reps = parse_reps(match.group(2))
    return (int(match.group(1)),) + reps if reps else None


def item(name, sets, min_reps, max_reps):
    return {"name": name, "sets": sets, "min_reps": min_reps, "max_reps": max_reps}


def routines(data):
    out = []
    for routine in data["routines"]:
        exercises = []
        for e in routine["exercises"]:
            parsed = None if is_timed(e["name"]) else parse_prescription(e["prescription"])
            if parsed:
                exercises.append(item(e["name"], *parsed))
        out.append({"name": f"Meridian · {routine['name']}", "exercises": exercises})
    return out


def workouts(data):
    out = []
    for workout in data["workouts"]:
        days = []
        for day in workout["days"]:
            exercises = []
            for e in day["exercises"]:
                reps = parse_reps(e["reps"]) if e.get("reps") and e.get("sets") and not is_timed(e["name"]) else None
                if reps:
                    exercises.append(item(e["name"], e["sets"], *reps))
            weekday = WEEKDAYS.get((day.get("weekday") or "").lower())
            days.append({"title": day["name"], "weekday": weekday, "exercises": exercises})
        out.append({"name": f"Meridian · {workout['name']}", "days": days})
    return out


def build(source):
    source = Path(source)
    coach = json.loads((source / "coach_routines.json").read_text())
    plans = json.loads((source / "workouts.json").read_text())
    return {"routines": routines(coach), "workouts": workouts(plans)}


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    target = Path(__file__).resolve().parents[2] / "output" / "meridian-presets.json"
    target.parent.mkdir(exist_ok=True)
    presets = build(sys.argv[1])
    target.write_text(json.dumps(presets, indent=1, ensure_ascii=False))
    print(f"{len(presets['routines'])} routines and {len(presets['workouts'])} workouts written to {target}")
