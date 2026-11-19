"""Merges per-chapter labs catalogue fragments into one file for the app (output/labs-catalogue.json, git-ignored).

  python3 tools/labs-catalogue/merge_catalogue.py OUT FRAGMENT.json [FRAGMENT.json ...]

A fragment may carry only {"id", "formula"} per marker: the vault's quoted formulas, attached to markers described elsewhere.

The same marker can come from several chapters (the Start Here chapter adds doctor lines to markers that other chapters
describe in full); their lists are joined and exact repeats dropped. Panels, prep steps, patterns and genes with the same
id keep the first and report the clash.
"""
import json
import sys

LIST_FIELDS = ["aliases", "howTested", "pushesUp", "pushesDown", "nextTo", "whatToDo", "other", "bands", "doctor",
               "retest", "prep", "disputes", "units"]
SCALAR_FIELDS = ["name", "chapter", "lesson", "sample", "what", "needsLabRange", "computed", "links", "formula"]


def _key(item):
    return json.dumps(item, sort_keys=True, ensure_ascii=False)


def merge_marker(into, new):
    for field in SCALAR_FIELDS:
        if field == "needsLabRange" or field == "computed":
            into[field] = bool(into.get(field)) or bool(new.get(field))
        elif not into.get(field) and new.get(field):
            into[field] = new[field]
    for field in LIST_FIELDS:
        merged = list(into.get(field) or [])
        if isinstance(merged, str):
            merged = [merged]
        incoming = new.get(field) or []
        if isinstance(incoming, str):
            incoming = [incoming]
        seen = {_key(x) for x in merged}
        if field == "units":
            seen = {u.get("unit") for u in merged}
        for item in incoming:
            k = item.get("unit") if field == "units" else _key(item)
            if k not in seen:
                if field == "units" and item.get("default") and any(u.get("default") for u in merged):
                    item = {key: value for key, value in item.items() if key != "default"}
                merged.append(item)
                seen.add(k)
        if merged:
            into[field] = merged


# Ids one chapter used for a marker another chapter describes in full.
RENAMES = {"bilirubin": "total-bilirubin"}


def rename_ids(data):
    def fix(ids):
        return [RENAMES.get(i, i) for i in ids]
    for marker in data.get("markers", []):
        marker["id"] = RENAMES.get(marker["id"], marker["id"])
        links = marker.get("links") or {}
        if isinstance(links, dict) and links.get("markers"):
            links["markers"] = fix(links["markers"])
    for panel in data.get("panels", []):
        panel["markers"] = fix(panel.get("markers") or [])
        if panel.get("triggerMarkers"):
            panel["triggerMarkers"] = fix(panel["triggerMarkers"])
    for step in data.get("prep", []):
        if step.get("markers"):
            step["markers"] = fix(step["markers"])
    for pattern in data.get("patterns", []):
        if pattern.get("markers"):
            pattern["markers"] = fix(pattern["markers"])
        for condition in pattern.get("conditions") or []:
            condition["marker"] = RENAMES.get(condition.get("marker"), condition.get("marker"))


def normalise(data):
    """Fixes the two shapes the fragment builders sometimes wrote: unnamed units and `state` used for a condition's op."""
    fixes = 0
    for marker in data.get("markers", []):
        units = [u for u in marker.get("units", []) if isinstance(u.get("unit"), str)]
        fixes += len(marker.get("units", [])) - len(units)
        if units and not any(u.get("default") for u in units):
            units[0] = dict(units[0], default=True)
            fixes += 1
        marker["units"] = units
    for pattern in data.get("patterns", []):
        for condition in pattern.get("conditions") or []:
            if "op" not in condition and "state" in condition:
                condition["op"] = condition.pop("state")
                fixes += 1
    return fixes


def merge(fragments):
    out = {"markers": [], "panels": [], "prep": [], "patterns": [], "genes": [], "geneticsGuide": []}
    index = {}
    clashes = []
    for name, data in fragments:
        for marker in data.get("markers", []):
            if marker["id"] in index:
                merge_marker(index[marker["id"]], marker)
            else:
                copy = dict(marker)
                index[marker["id"]] = copy
                out["markers"].append(copy)
        for kind in ["panels", "prep", "patterns", "genes"]:
            have = {x["id"] for x in out[kind]}
            for item in data.get(kind, []):
                if item["id"] in have:
                    clashes.append(f"{kind}:{item['id']} ({name})")
                    continue
                out[kind].append(item)
                have.add(item["id"])
        out["geneticsGuide"] += data.get("geneticsGuide", [])
    return out, clashes


def main(argv):
    out_path, paths = argv[1], argv[2:]
    fragments = [(p, json.load(open(p, encoding="utf-8"))) for p in paths]
    for _, data in fragments:
        rename_ids(data)
    fixes = sum(normalise(data) for _, data in fragments)
    merged, clashes = merge(fragments)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=1)
    counts = {k: len(v) for k, v in merged.items()}
    print(json.dumps(counts) + f"; {fixes} shape fixes")
    if clashes:
        print("id clashes (first kept): " + ", ".join(clashes))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
