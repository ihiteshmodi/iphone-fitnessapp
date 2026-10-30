import sqlite3

import demo_diet
import import_diet


def test_the_demo_diet_is_written_with_a_recipe_a_packaged_snack_and_a_cycled_supplement(app_db):
    conn = sqlite3.connect(app_db)
    conn.execute("PRAGMA foreign_keys = ON")

    demo_diet.write_demo(conn)

    assert conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0] == 10
    assert conn.execute("SELECT COUNT(*) FROM diet_plan_items").fetchone()[0] == 8
    assert conn.execute("SELECT pieces_per_pack FROM foods WHERE name = 'Tea biscuits'").fetchone() == (35.0,)
    assert conn.execute("SELECT recipe_makes FROM foods WHERE name = 'Flatbread'").fetchone() == (2.0,)
    assert conn.execute("""SELECT cycle_mode, cycle_on, cycle_off, cycle_start FROM diet_plan_items i JOIN foods f ON f.id = i.food_id
                           WHERE f.name = 'Mineral'""").fetchone() == ("weeks", 2, 1, "2026-10-05")
    assert conn.execute("PRAGMA foreign_key_check").fetchall() == []


def test_the_demo_command_upgrades_an_older_database_and_can_be_repeated(app_db):
    conn = sqlite3.connect(app_db)
    for table in ("diet_extras", "diet_day_ticks", "diet_plan_items", "diet_plans", "recipe_items", "foods"):
        conn.execute(f"DROP TABLE {table}")
    conn.execute("PRAGMA user_version = 7")
    conn.commit()
    conn.close()

    demo_diet.main(["--db", str(app_db)])
    demo_diet.main(["--db", str(app_db), "--replace"])

    conn = sqlite3.connect(app_db)
    assert conn.execute("PRAGMA user_version").fetchone()[0] == import_diet.SCHEMA_VERSION
    assert conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0] == 10
