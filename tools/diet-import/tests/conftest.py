"""Tests use made-up foods and a small hand-built spreadsheet; no personal data."""
import sqlite3
import zipfile
from pathlib import Path

import pytest

SCHEMA = Path(__file__).resolve().parents[3] / "src" / "shared" / "database" / "schema.sql"

FOOD_HEADER = ["Item Name", "Type", "Buy Price", "Pack Size", "Unit", "Cost/Unit", "Base Qty",
               "Protein", "Carbs", "Fat", "Fiber", "Sat Fat", "Calories", "Sodium", "Notes"]


def food_row(name, kind="Food", price=100.0, pack=1000.0, unit="grams", base=100.0, protein=0.0, carbs=0.0, fat=0.0,
             fiber=None, sat=None, calories=None, sodium=None, notes=None):
    return [name, kind, price, pack, unit, None, base, protein, carbs, fat, fiber, sat, calories, sodium, notes]


@pytest.fixture
def sheets():
    return {
        "Database": [FOOD_HEADER,
                     food_row("Rolled oats", protein=12, carbs=68, fat=8, fiber=10, calories=392),
                     food_row("Flour", price=30, pack=500, protein=10, carbs=75, calories=350),
                     food_row("Mineral", kind="Suppliment", price=100, pack=100, unit="units", base=1, calories=0, notes="1 capsule"),
                     food_row("Flatbread (recipe)", price=3.5, pack=1, unit="units", base=1, calories=95),
                     food_row("Rolled oats", price=1, pack=1, calories=1),
                     food_row("Water", kind="Liquid", price=0, pack=0, unit="ml", base=1, calories=0)],
        "Recipes": [["Flatbread - small"] + [None] * 3,
                    ["Ingredient Name", "Quantity", "Cost"],
                    ["Flour", 40.0, 12.0],
                    ["Rolled oats", 10.0, 1.0],
                    ["Water", 80.0, 0.0],
                    ["Total", 130.0, 13.0]],
        "Diet": [["Meal", "Item Name", "Unit", "Quantity"],
                 ["Morning", "Mineral", "units", 1.0],
                 ["Brunch", "Flatbread (recipe)", "units", 3.0],
                 ["Brunch", "Rolled oats", "grams", 40.0]],
    }


@pytest.fixture
def config():
    return {
        "sheets": {"foods": "Database", "recipes": "Recipes", "diet": "Diet"},
        "rename": {"Flatbread (recipe)": "Flatbread"},
        "recipes": [{"food": "Flatbread (recipe)", "section": "Flatbread - small", "unit": "piece", "makes": 1}],
        "price_overrides": {"Mineral": {"price": 50, "pack_size": 100}},
        "plan_start": "2026-10-26",
    }


@pytest.fixture
def app_db(tmp_path):
    """A database made from the app schema (version 8)."""
    path = tmp_path / "app.sqlite"
    conn = sqlite3.connect(path)
    conn.executescript(SCHEMA.read_text())
    conn.close()
    return path


def write_ods(path, sheets):
    """A minimal .ods file: numbers as float cells, everything else as strings."""
    def cell(value):
        if value is None:
            return "<table:table-cell/>"
        if isinstance(value, (int, float)):
            return f'<table:table-cell office:value-type="float" office:value="{value}"><text:p>{value}</text:p></table:table-cell>'
        return f'<table:table-cell office:value-type="string"><text:p>{value}</text:p></table:table-cell>'

    tables = "".join(
        f'<table:table table:name="{name}">' + "".join("<table:table-row>" + "".join(cell(v) for v in row) + "</table:table-row>" for row in rows) + "</table:table>"
        for name, rows in sheets.items())
    content = ('<?xml version="1.0" encoding="UTF-8"?><office:document-content '
               'xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
               'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
               'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0">'
               f"<office:body><office:spreadsheet>{tables}</office:spreadsheet></office:body></office:document-content>")
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("content.xml", content)
    return path
