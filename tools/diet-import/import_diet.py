#!/usr/bin/env python3
"""Imports a diet spreadsheet (foods, recipes, the daily plan) into the app's SQLite database.

The spreadsheet and the config file hold personal data: keep them out of git. See README.md.
"""
import argparse
import json
import re
import sqlite3
import sys
from dataclasses import dataclass, field
from pathlib import Path

from ods_reader import load

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = PROJECT_ROOT / "src" / "shared" / "database" / "schema.sql"
SCHEMA_VERSION = 9
DIET_TABLES = ("foods", "recipe_items", "diet_plans", "diet_plan_items", "diet_day_ticks", "diet_extras")

DEFAULT_SHEETS = {"foods": "Database", "recipes": "Readymade_Recipe", "diet": "Diet_-_Maintain"}
DEFAULT_UNITS = {"grams": "g", "gram": "g", "units": "unit", "unit": "unit", "ml": "ml"}
DEFAULT_KINDS = {"food": "food", "topping": "topping", "suppliment": "supplement", "supplement": "supplement",
                 "herb": "herb", "liquid": "liquid"}


class ImportProblem(Exception):
    pass


@dataclass
class ImportData:
    foods: list = field(default_factory=list)
    recipes: list = field(default_factory=list)
    plan: list = field(default_factory=list)
    warnings: list = field(default_factory=list)


def text(value):
    return None if value is None else str(value).strip() or None


def number(value, default=None):
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and re.fullmatch(r"-?\d+(\.\d+)?", value.strip()):
        return float(value)
    return default


def find_header(rows, first_column):
    for index, row in enumerate(rows):
        if row and text(row[0]) == first_column:
            return index
    raise ImportProblem(f"No header row starting with '{first_column}'")


def column_map(header):
    return {text(name): index for index, name in enumerate(header) if text(name)}


def parse_foods(rows, config):
    """One dict per food row, keeping the first of any duplicate name (case-insensitive)."""
    units = {**DEFAULT_UNITS, **config.get("units", {})}
    kinds = {**DEFAULT_KINDS, **config.get("kinds", {})}
    rename = config.get("rename", {})
    overrides = config.get("price_overrides", {})
    head = find_header(rows, "Item Name")
    cols = column_map(rows[head])
    foods, seen, warnings = [], set(), []

    def cell(row, name):
        index = cols.get(name)
        return row[index] if index is not None and index < len(row) else None

    for offset, row in enumerate(rows[head + 1:], start=head + 2):
        sheet_name = text(cell(row, "Item Name"))
        if not sheet_name:
            continue
        name = rename.get(sheet_name, sheet_name)
        if name.casefold() in seen:
            warnings.append(f"Row {offset}: '{sheet_name}' is a duplicate and was ignored")
            continue
        seen.add(name.casefold())
        macros = {key: number(cell(row, col), 0.0) for key, col in
                  (("protein", "Protein"), ("carbs", "Carbs"), ("fat", "Fat"), ("fiber", "Fiber"), ("sat_fat", "Sat Fat"), ("sodium", "Sodium"))}
        calories = number(cell(row, "Calories"))
        computed = 4 * macros["protein"] + 4 * macros["carbs"] + 9 * macros["fat"]
        price, pack = number(cell(row, "Buy Price")), number(cell(row, "Pack Size"))
        override = overrides.get(sheet_name) or overrides.get(name)
        if override:
            price, pack = override.get("price", price), override.get("pack_size", pack)
        if price == 0 and not (pack and pack > 0):
            pack = 1.0  # free (water): costs nothing rather than "no price"
        priced = price is not None and price >= 0 and pack is not None and pack > 0
        unit_text = (text(cell(row, "Unit")) or "g").lower()
        kind_text = (text(cell(row, "Type")) or "food").lower()
        foods.append({
            "sheet_name": sheet_name, "name": name,
            "kind": kinds.get(kind_text, "food"), "unit": units.get(unit_text, unit_text),
            "base_qty": number(cell(row, "Base Qty"), 100.0) or 100.0, **macros,
            "label_calories": calories if calories is not None and abs(calories - computed) > 0.5 else None,
            "price": price if priced else None, "pack_size": pack if priced else None,
            "notes": text(cell(row, "Notes")),
        })
    return foods, warnings


def parse_recipe_section(rows, section):
    """Ingredient (name, quantity) lines under a section title, up to its Total row."""
    start = next((i for i, row in enumerate(rows) if row and text(row[0]) == section), None)
    if start is None:
        raise ImportProblem(f"Recipe section '{section}' was not found")
    lines = []
    for row in rows[start + 2:]:
        name = text(row[0]) if row else None
        if not name or name.casefold() == "total":
            break
        quantity = number(row[1] if len(row) > 1 else None)
        if quantity is None or quantity <= 0:
            raise ImportProblem(f"'{name}' in recipe '{section}' has no quantity")
        lines.append((name, quantity))
    if not lines:
        raise ImportProblem(f"Recipe section '{section}' has no ingredients")
    return lines


def parse_plan(rows):
    head = find_header(rows, "Meal")
    cols = column_map(rows[head])
    plan = []
    for offset, row in enumerate(rows[head + 1:], start=head + 2):
        meal, item = text(row[cols["Meal"]]), text(row[cols["Item Name"]])
        quantity = number(row[cols["Quantity"]] if cols["Quantity"] < len(row) else None)
        if not meal and not item:
            continue
        if not meal or not item or quantity is None or quantity <= 0:
            raise ImportProblem(f"Diet row {offset} needs a meal, an item and a quantity above 0")
        plan.append((meal, item, quantity))
    return plan


def build(sheets, config):
    """Everything to write, from the sheets already loaded (sheet name -> rows of cell values)."""
    names = {**DEFAULT_SHEETS, **config.get("sheets", {})}
    rename = config.get("rename", {})
    data = ImportData()
    data.foods, data.warnings = parse_foods(sheets[names["foods"]], config)
    by_sheet = {f["sheet_name"]: f for f in data.foods}
    by_name = {f["name"].casefold(): f for f in data.foods}

    def resolve(sheet_name):
        food = by_sheet.get(sheet_name) or by_name.get(rename.get(sheet_name, sheet_name).casefold())
        if not food:
            raise ImportProblem(f"'{sheet_name}' is not in the food list")
        return food

    for recipe in config.get("recipes", []):
        food = resolve(recipe["food"])
        lines = [(resolve(name)["name"], quantity) for name, quantity in parse_recipe_section(sheets[names["recipes"]], recipe["section"])]
        makes = sum(q for _, q in lines) if recipe.get("makes", 1) == "total" else float(recipe.get("makes", 1))
        food.update(kind="recipe", unit=recipe.get("unit", food["unit"]), base_qty=1.0, protein=0.0, carbs=0.0, fat=0.0,
                    fiber=0.0, sat_fat=0.0, sodium=0.0, label_calories=None, price=None, pack_size=None, recipe_makes=makes)
        data.recipes.append({"name": food["name"], "lines": lines})

    for meal, item, quantity in parse_plan(sheets[names["diet"]]):
        data.plan.append((meal, resolve(item)["name"], quantity))
    return data


def strip_comments(sql):
    return "\n".join(line.split("--", 1)[0] for line in sql.splitlines())


def migrate(conn, schema_path=SCHEMA_PATH):
    """Adds the diet tables and rules to an older app database, using the same SQL as the app's schema."""
    statements = [s.strip() for s in strip_comments(schema_path.read_text()).split(";") if s.strip()]
    for statement in statements:
        match = re.match(r"CREATE (TABLE|INDEX) (\w+)", statement)
        if match and (match.group(2) in DIET_TABLES or match.group(2) == "diet_extras_by_day"):
            conn.execute(re.sub(r"^CREATE (TABLE|INDEX)", r"CREATE \1 IF NOT EXISTS", statement, count=1))
    conn.execute("INSERT OR IGNORE INTO settings (key, value) VALUES ('protein_min_g', '180'), ('diet_fat_percent', '20'), ('fat_ceiling_g_per_lb', '0.4')")
    conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")


def write(conn, data, plan_start, replace=False):
    """Writes the foods, recipes and plan in one transaction. Refuses to touch existing diet data unless `replace`."""
    existing = conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
    if existing and not replace:
        raise ImportProblem(f"The database already has {existing} foods; use --replace to import again")
    if replace and conn.execute("SELECT COUNT(*) FROM diet_extras").fetchone()[0]:
        raise ImportProblem("Extras are logged against these foods; they would be lost, so --replace is refused")
    with conn:
        if replace:
            for table in ("diet_day_ticks", "diet_plan_items", "diet_plans", "recipe_items", "foods"):
                conn.execute(f"DELETE FROM {table}")
        ids = {}
        for food in data.foods:
            cursor = conn.execute(
                """INSERT INTO foods (name, kind, unit, base_qty, protein, carbs, fat, fiber, sat_fat, sodium, label_calories,
                                      price, pack_size, pieces_per_pack, piece_weight, recipe_makes, notes)
                   VALUES (:name, :kind, :unit, :base_qty, :protein, :carbs, :fat, :fiber, :sat_fat, :sodium, :label_calories,
                           :price, :pack_size, :pieces_per_pack, :piece_weight, :recipe_makes, :notes)""",
                {"recipe_makes": None, "pieces_per_pack": None, "piece_weight": None, **food})
            ids[food["name"]] = cursor.lastrowid
        for recipe in data.recipes:
            for position, (name, quantity) in enumerate(recipe["lines"], start=1):
                conn.execute("INSERT INTO recipe_items (recipe_id, food_id, position, quantity) VALUES (?, ?, ?, ?)",
                             (ids[recipe["name"]], ids[name], position, quantity))
        conn.execute("INSERT INTO diet_plans (effective_from) VALUES (?)", (plan_start,))
        for position, (meal, name, quantity, *rest) in enumerate(data.plan, start=1):
            cycle = rest[0] if rest else {}
            conn.execute("""INSERT INTO diet_plan_items (plan_from, meal, position, food_id, quantity, cycle_mode, cycle_on, cycle_off, cycle_start)
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                         (plan_start, meal, position, ids[name], quantity, cycle.get("mode", "daily"), cycle.get("on"), cycle.get("off"), cycle.get("start")))
        problems = conn.execute("PRAGMA foreign_key_check").fetchall()
        if problems:
            raise ImportProblem(f"Foreign key problems after import: {problems}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ods", required=True, help="the diet spreadsheet")
    parser.add_argument("--db", required=True, help="the app database to write into (a copy is safest)")
    parser.add_argument("--config", required=True, help="JSON with recipes, renames and corrections (personal, keep out of git)")
    parser.add_argument("--plan-start", help="date the plan starts, YYYY-MM-DD (overrides the config)")
    parser.add_argument("--replace", action="store_true", help="delete earlier imported diet data first")
    parser.add_argument("--dry-run", action="store_true", help="read and check everything, write nothing")
    args = parser.parse_args(argv)

    config = json.loads(Path(args.config).read_text())
    plan_start = args.plan_start or config.get("plan_start")
    if not plan_start or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", plan_start):
        raise SystemExit("Give the plan start date as YYYY-MM-DD (--plan-start or plan_start in the config)")
    try:
        data = build(load(args.ods), config)
    except ImportProblem as error:
        raise SystemExit(f"Cannot import: {error}")

    print(f"{len(data.foods)} foods, {len(data.recipes)} recipes, {len(data.plan)} plan lines starting {plan_start}")
    for warning in data.warnings:
        print("  note:", warning)
    if args.dry_run:
        return 0
    conn = sqlite3.connect(args.db)
    conn.execute("PRAGMA foreign_keys = ON")
    try:
        if conn.execute("PRAGMA user_version").fetchone()[0] < SCHEMA_VERSION:
            migrate(conn)
            conn.commit()
            print(f"Upgraded the database to version {SCHEMA_VERSION}")
        write(conn, data, plan_start, args.replace)
    except ImportProblem as error:
        raise SystemExit(f"Cannot import: {error}")
    finally:
        conn.close()
    print("Done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
