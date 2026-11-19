import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from merge_catalogue import merge  # noqa: E402


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
