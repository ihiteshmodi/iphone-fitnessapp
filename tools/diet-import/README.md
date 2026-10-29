# diet-import

Imports a diet spreadsheet into the app's SQLite database: the food list, the recipes (ingredient lists) and the daily plan.
Standard library only, apart from pytest for the tests.

The spreadsheet and the config file are personal. Keep them in `current_artifacts/` (ignored by git), never in a commit.

## Run

```
cd tools/diet-import
python3 import_diet.py --ods "../../current_artifacts/Diet Sheet.ods" \
    --db ../../output/fitness.sqlite --config ../../current_artifacts/diet-import.config.json --dry-run
```

Drop `--dry-run` to write. An older database (before version 8) is upgraded with the diet tables first, using the same SQL as the app's `schema.sql`.
Importing twice is refused unless you pass `--replace`, and `--replace` is refused once extras have been logged. Work on a copy of the database when in doubt.

Tests (any Python with pytest): `python3 -m pytest`. They use made-up foods and a small hand-built spreadsheet.

## The spreadsheet

| Sheet (default name) | Layout |
|---|---|
| `Database` | A header row starting with `Item Name`, then one food per row. Columns used: Type, Buy Price, Pack Size, Unit, Base Qty, Protein, Carbs, Fat, Fiber, Sat Fat, Sodium, Calories, Notes. |
| `Readymade_Recipe` | Sections: a title row, a header row, then `Ingredient Name`, `Quantity` lines up to a `Total` row. |
| `Diet_-_Maintain` | A header row starting with `Meal`, then `Meal`, `Item Name`, `Unit`, `Quantity` per line. |

## The config (JSON)

```json
{
  "sheets": {"foods": "Database", "recipes": "Readymade_Recipe", "diet": "Diet_-_Maintain"},
  "rename": {"Sheet name (recipe)": "Name in the app"},
  "units": {"grams": "g", "units": "unit"},
  "kinds": {"Suppliment": "supplement"},
  "recipes": [{"food": "Sheet name (recipe)", "section": "Section title", "unit": "piece", "makes": 1}],
  "price_overrides": {"Some food": {"price": 100, "pack_size": 100}},
  "plan_start": "2026-10-26"
}
```

Every key is optional. `makes` is a number or `"total"` (the section's total quantity, for a batch measured in grams). `rename` also applies to the names used in recipe and diet rows.

## Rules

- Names are matched ignoring case; a duplicate food name keeps the first row and prints a note.
- A food's calories are stored as a label value only when the sheet's number differs from 4 x protein + 4 x carbs + 9 x fat, otherwise they stay automatic.
- A price of 0 means free. A missing price or pack size means "no price yet".
- A recipe food takes its nutrition and cost from its ingredients; the sheet's own numbers for it are ignored.
- Anything it cannot match (an ingredient or plan item that is not in the food list, a missing quantity) stops the import before anything is written.
- Everything is written in one transaction and checked with `PRAGMA foreign_key_check`.
