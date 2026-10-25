import sqlite3

import pytest

import build_seed_db
from workbook_helpers import WorkbookSpec


@pytest.fixture
def spec():
    s = WorkbookSpec()
    s.library = [
        ["Machine Shoulder Press", "Shoulders", "  seat 3  "],
        ["Lat Pulldown", "Back", None],
    ]
    return s


@pytest.fixture
def build(spec, tmp_path):
    """Builds the database from the spec; returns (connection, report)."""
    def _build():
        xlsx = spec.write(tmp_path / "in.xlsx")
        out = tmp_path / "out" / "fitness.sqlite"
        report = build_seed_db.build(xlsx, out)
        conn = sqlite3.connect(out)
        conn.execute("PRAGMA foreign_keys=ON")
        return conn, report
    return _build
