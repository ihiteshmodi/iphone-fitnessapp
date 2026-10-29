#!/usr/bin/env python3
"""Writes a small made-up diet (foods, one recipe, a packaged snack, a cycled supplement, a plan) into an app database.

Used by the UI tests and the README screenshots, so nothing personal is needed. Run:
  python3 demo_diet.py --db PATH [--start 2026-10-01] [--replace]
"""
import argparse
import sqlite3
import sys

from import_diet import ImportData, ImportProblem, migrate, write, SCHEMA_VERSION

DEMO_START = "2026-10-01"


def food(name, kind="food", unit="g", base=100.0, protein=0.0, carbs=0.0, fat=0.0, fiber=0.0, label=None,
         price=None, pack=None, pieces=None, makes=None, notes=None):
    return {"sheet_name": name, "name": name, "kind": kind, "unit": unit, "base_qty": base, "protein": protein, "carbs": carbs,
            "fat": fat, "fiber": fiber, "sat_fat": 0.0, "sodium": 0.0, "label_calories": label, "price": price, "pack_size": pack,
            "recipe_makes": makes, "pieces_per_pack": pieces, "piece_weight": None, "notes": notes}


def demo_data():
    data = ImportData()
    data.foods = [
        food("Rolled oats", protein=12, carbs=68, fat=8, fiber=10, price=160, pack=1000),
        food("Soy chunks", protein=52, carbs=33, fat=1, fiber=13, price=170, pack=1000),
        food("Peanuts", protein=26, carbs=16, fat=49, fiber=9, price=180, pack=1000),
        food("Rice flour", protein=6, carbs=80, fat=1, fiber=2, price=60, pack=1000),
        food("Water", unit="ml", base=1, price=0, pack=1),
        food("Flatbread", kind="recipe", unit="piece", base=1, makes=2),
        food("Whey blend", kind="supplement", protein=75, carbs=9, fat=5, price=2400, pack=1000),
        food("Fish oil", kind="supplement", unit="capsule", base=1, label=0, price=9, pack=1),
        food("Mineral", kind="supplement", unit="capsule", base=1, label=0, price=2, pack=1, notes="Two weeks on, one week off"),
        food("Tea biscuits", kind="packaged", protein=7, carbs=70, fat=18, fiber=2, label=480, price=40, pack=250, pieces=35),
    ]
    data.recipes = [{"name": "Flatbread", "lines": [("Rice flour", 60.0), ("Rolled oats", 20.0), ("Water", 80.0)]}]
    data.plan = [
        ("Morning", "Rolled oats", 60.0), ("Morning", "Whey blend", 30.0),
        ("Lunch", "Soy chunks", 60.0), ("Lunch", "Flatbread", 3.0), ("Lunch", "Fish oil", 1.0),
        ("Lunch", "Mineral", 1.0, {"mode": "weeks", "on": 2, "off": 1, "start": "2026-10-05"}),
        ("Dinner", "Peanuts", 30.0), ("Dinner", "Soy chunks", 40.0),
    ]
    return data


def write_demo(conn, start=DEMO_START, replace=False):
    write(conn, demo_data(), start, replace)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--db", required=True)
    parser.add_argument("--start", default=DEMO_START)
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args(argv)
    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        if conn.execute("PRAGMA user_version").fetchone()[0] < SCHEMA_VERSION:
            migrate(conn)
            conn.commit()
        write_demo(conn, args.start, args.replace)
    except ImportProblem as error:
        raise SystemExit(f"Cannot write the demo diet: {error}")
    finally:
        conn.close()
    print("Demo diet written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
