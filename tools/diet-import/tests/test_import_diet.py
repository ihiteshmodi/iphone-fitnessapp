import json
import sqlite3

import pytest

import import_diet
from ods_reader import load
from conftest import food_row, write_ods


def test_ods_reader_returns_numbers_and_text_per_sheet(tmp_path):
    path = write_ods(tmp_path / "a.ods", {"One": [["Name", 1.5], [None, "x"]]})

    rows = load(path)["One"]

    assert rows == [["Name", 1.5], [None, "x"]]


def test_foods_are_read_with_units_kinds_and_a_label_only_when_it_differs_from_the_macros(sheets, config):
    data = import_diet.build(sheets, config)
    foods = {f["name"]: f for f in data.foods}

    assert foods["Rolled oats"]["unit"] == "g"
    assert foods["Rolled oats"]["label_calories"] is None, "392 is what 4/4/9 gives, so it is left automatic"
    assert foods["Flour"]["label_calories"] == 350, "the label differs from the 340 the macros give, so it is kept"
    assert foods["Mineral"]["kind"] == "supplement"
    assert foods["Mineral"]["unit"] == "unit"
    assert foods["Mineral"]["notes"] == "1 capsule"


def test_a_duplicate_food_name_keeps_the_first_and_says_so(sheets, config):
    data = import_diet.build(sheets, config)

    assert [f["name"] for f in data.foods].count("Rolled oats") == 1
    assert next(f for f in data.foods if f["name"] == "Rolled oats")["price"] == 100
    assert any("duplicate" in w and "Rolled oats" in w for w in data.warnings)


def test_a_price_correction_replaces_the_sheet_value(sheets, config):
    mineral = next(f for f in import_diet.build(sheets, config).foods if f["name"] == "Mineral")

    assert (mineral["price"], mineral["pack_size"]) == (50, 100)


def test_a_free_food_costs_nothing_and_a_food_with_no_price_has_none(sheets, config):
    sheets["Database"].append(food_row("Mystery", price=None, pack=None))

    foods = {f["name"]: f for f in import_diet.build(sheets, config).foods}

    assert (foods["Water"]["price"], foods["Water"]["pack_size"]) == (0, 1), "free: zero, not 'no price'"
    assert foods["Mystery"]["price"] is None and foods["Mystery"]["pack_size"] is None


def test_a_recipe_takes_its_ingredients_makes_and_unit_from_the_config(sheets, config):
    data = import_diet.build(sheets, config)
    flatbread = next(f for f in data.foods if f["name"] == "Flatbread")

    assert flatbread["kind"] == "recipe" and flatbread["unit"] == "piece" and flatbread["recipe_makes"] == 1
    assert data.recipes == [{"name": "Flatbread", "lines": [("Flour", 40.0), ("Rolled oats", 10.0), ("Water", 80.0)]}]


def test_a_batch_recipe_can_make_its_total_weight(sheets, config):
    config["recipes"][0]["makes"] = "total"

    flatbread = next(f for f in import_diet.build(sheets, config).foods if f["name"] == "Flatbread")

    assert flatbread["recipe_makes"] == 130


def test_the_plan_lists_meals_items_and_quantities_in_sheet_order_using_app_names(sheets, config):
    data = import_diet.build(sheets, config)

    assert data.plan == [("Morning", "Mineral", 1.0), ("Brunch", "Flatbread", 3.0), ("Brunch", "Rolled oats", 40.0)]


def test_an_unknown_ingredient_or_plan_item_stops_the_import(sheets, config):
    sheets["Diet"].append(["Dinner", "Mystery", "grams", 5.0])

    with pytest.raises(import_diet.ImportProblem, match="Mystery"):
        import_diet.build(sheets, config)


def test_a_missing_recipe_section_stops_the_import(sheets, config):
    config["recipes"][0]["section"] = "Nope"

    with pytest.raises(import_diet.ImportProblem, match="Nope"):
        import_diet.build(sheets, config)


def test_a_plan_line_without_a_quantity_stops_the_import(sheets, config):
    sheets["Diet"].append(["Dinner", "Flour", "grams", None])

    with pytest.raises(import_diet.ImportProblem, match="quantity"):
        import_diet.build(sheets, config)


def test_writing_fills_the_diet_tables_and_keeps_the_foreign_keys_valid(sheets, config, app_db):
    data = import_diet.build(sheets, config)
    conn = sqlite3.connect(app_db)
    conn.execute("PRAGMA foreign_keys = ON")

    import_diet.write(conn, data, "2026-10-26")

    assert conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0] == 5
    assert conn.execute("SELECT COUNT(*) FROM recipe_items").fetchone()[0] == 3
    assert conn.execute("SELECT effective_from FROM diet_plans").fetchall() == [("2026-10-26",)]
    assert conn.execute("""SELECT meal, f.name, quantity FROM diet_plan_items i JOIN foods f ON f.id = i.food_id ORDER BY position""").fetchall() == [
        ("Morning", "Mineral", 1.0), ("Brunch", "Flatbread", 3.0), ("Brunch", "Rolled oats", 40.0)]
    assert conn.execute("SELECT recipe_makes, unit FROM foods WHERE name = 'Flatbread'").fetchone() == (1.0, "piece")


def test_importing_twice_is_refused_unless_asked_to_replace(sheets, config, app_db):
    data = import_diet.build(sheets, config)
    conn = sqlite3.connect(app_db)
    conn.execute("PRAGMA foreign_keys = ON")
    import_diet.write(conn, data, "2026-10-26")

    with pytest.raises(import_diet.ImportProblem, match="--replace"):
        import_diet.write(conn, data, "2026-10-26")
    import_diet.write(conn, data, "2026-10-26", replace=True)

    assert conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0] == 5
    assert conn.execute("SELECT COUNT(*) FROM diet_plan_items").fetchone()[0] == 3


def test_replacing_is_refused_when_extras_are_logged_against_the_foods(sheets, config, app_db):
    data = import_diet.build(sheets, config)
    conn = sqlite3.connect(app_db)
    conn.execute("PRAGMA foreign_keys = ON")
    import_diet.write(conn, data, "2026-10-26")
    conn.execute("INSERT INTO diet_extras (day, food_id, amount) VALUES ('2026-10-27', 1, 10)")

    with pytest.raises(import_diet.ImportProblem, match="Extras"):
        import_diet.write(conn, data, "2026-10-26", replace=True)


def test_an_older_database_is_upgraded_with_the_diet_tables_and_keeps_its_data(app_db):
    conn = sqlite3.connect(app_db)
    for table in ("diet_extras", "diet_day_ticks", "diet_plan_items", "diet_plans", "recipe_items", "foods"):
        conn.execute(f"DROP TABLE {table}")
    conn.execute("DELETE FROM settings WHERE key IN ('protein_min_g', 'diet_fat_percent', 'fat_ceiling_g_per_lb')")
    conn.execute("INSERT INTO calorie_defaults (effective_from, calories) VALUES ('2026-10-26', 2839)")
    conn.execute("PRAGMA user_version = 7")

    import_diet.migrate(conn)

    tables = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    assert set(import_diet.DIET_TABLES) <= tables
    assert conn.execute("PRAGMA user_version").fetchone()[0] == 9
    assert conn.execute("SELECT calories FROM calorie_defaults").fetchone() == (2839,)
    assert conn.execute("SELECT value FROM settings WHERE key = 'protein_min_g'").fetchone() == ("180",)


def test_the_command_line_imports_from_a_spreadsheet_file(sheets, config, app_db, tmp_path, capsys):
    ods = write_ods(tmp_path / "diet.ods", sheets)
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config))

    import_diet.main(["--ods", str(ods), "--db", str(app_db), "--config", str(config_path)])

    assert sqlite3.connect(app_db).execute("SELECT COUNT(*) FROM diet_plan_items").fetchone()[0] == 3
    assert "5 foods, 1 recipes, 3 plan lines starting 2026-10-26" in capsys.readouterr().out


def test_a_dry_run_writes_nothing(sheets, config, app_db, tmp_path):
    ods = write_ods(tmp_path / "diet.ods", sheets)
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config))

    import_diet.main(["--ods", str(ods), "--db", str(app_db), "--config", str(config_path), "--dry-run"])

    assert sqlite3.connect(app_db).execute("SELECT COUNT(*) FROM foods").fetchone()[0] == 0
