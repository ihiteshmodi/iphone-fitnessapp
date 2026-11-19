"""Merges per-chapter labs catalogue fragments into one file for the app (output/labs-catalogue.json, git-ignored).

  python3 tools/labs-catalogue/merge_catalogue.py OUT FRAGMENT.json [FRAGMENT.json ...]

The same marker can come from several chapters (the Start Here chapter adds doctor lines to markers that other chapters
describe in full); their lists are joined and exact repeats dropped. Panels, prep steps, patterns and genes with the same
id keep the first and report the clash.
"""
import json
import sys

LIST_FIELDS = ["aliases", "howTested", "pushesUp", "pushesDown", "nextTo", "whatToDo", "other", "bands", "doctor",
               "retest", "prep", "disputes", "units"]
SCALAR_FIELDS = ["name", "chapter", "lesson", "sample", "what", "needsLabRange", "computed", "links"]


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
    merged, clashes = merge(fragments)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(merged, f, ensure_ascii=False, indent=1)
    counts = {k: len(v) for k, v in merged.items()}
    print(json.dumps(counts))
    if clashes:
        print("id clashes (first kept): " + ", ".join(clashes))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
