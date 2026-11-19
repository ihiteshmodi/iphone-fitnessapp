import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from merge_catalogue import merge, normalise, rename_ids  # noqa: E402


def test_the_same_marker_from_two_chapters_is_joined_once():
    a = {"markers": [{"id": "ferritin", "name": "Ferritin", "doctor": [{"op": ">", "value": 1, "urgency": "soon", "text": "x"}],
                      "units": [{"unit": "ng/mL", "default": True}]}]}
    b = {"markers": [{"id": "ferritin", "name": "Ferritin", "lesson": "02.10.02", "what": "Iron store",
                      "doctor": [{"op": ">", "value": 1, "urgency": "soon", "text": "x"}, {"op": "<", "value": 0, "urgency": "soon", "text": "y"}],
                      "units": [{"unit": "ng/mL", "default": True}, {"unit": "µg/L", "toDefault": 1}]}]}

    merged, clashes = merge([("a", a), ("b", b)])

    ferritin = merged["markers"][0]
    assert len(merged["markers"]) == 1
    assert ferritin["lesson"] == "02.10.02" and ferritin["what"] == "Iron store"
    assert [d["text"] for d in ferritin["doctor"]] == ["x", "y"]
    assert [u["unit"] for u in ferritin["units"]] == ["ng/mL", "µg/L"]
    assert clashes == []


def test_a_repeated_panel_id_keeps_the_first_and_reports_it():
    merged, clashes = merge([("a", {"panels": [{"id": "iron", "name": "A", "markers": []}]}),
                             ("b", {"panels": [{"id": "iron", "name": "B", "markers": []}]})])

    assert [p["name"] for p in merged["panels"]] == ["A"]
    assert clashes == ["panels:iron (b)"]


def test_unnamed_units_are_dropped_and_state_becomes_op():
    data = {"markers": [{"id": "plt", "name": "Platelets", "units": [{"unit": None}, {"unit": "10^3/uL", "default": True}]}],
            "patterns": [{"id": "p", "name": "P", "conditions": [{"marker": "ast", "state": "high"}]}]}

    assert normalise(data) == 2
    assert data["markers"][0]["units"] == [{"unit": "10^3/uL", "default": True}]
    assert data["patterns"][0]["conditions"][0] == {"marker": "ast", "op": "high"}


def test_the_first_unit_becomes_the_default_when_none_is_marked():
    data = {"markers": [{"id": "sg", "name": "Specific gravity", "units": [{"unit": "ratio"}, {"unit": "x"}]}]}

    normalise(data)

    assert data["markers"][0]["units"][0] == {"unit": "ratio", "default": True}


def test_a_chapter_alias_id_is_renamed_everywhere():
    data = {"markers": [{"id": "bilirubin", "name": "Bilirubin"}], "panels": [{"id": "lft", "name": "LFT", "markers": ["bilirubin"]}],
            "patterns": [{"id": "p", "name": "P", "conditions": [{"marker": "bilirubin", "op": ">", "value": 1}]}]}

    rename_ids(data)

    assert data["markers"][0]["id"] == "total-bilirubin"
    assert data["panels"][0]["markers"] == ["total-bilirubin"]
    assert data["patterns"][0]["conditions"][0]["marker"] == "total-bilirubin"
