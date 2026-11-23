"""Compiles the four verified clinical rule files and base catalogue into output/labs-catalogue.json.

Usage:
  python3 tools/labs-catalogue/compile_clinical_rules.py \
    --base BASE.json \
    --global-protocols global_protocols.json \
    --baseline-panels baseline_recommended_panels.json \
    --markers markers.json \
    --patterns patterns.json \
    --out output/labs-catalogue.json
"""
import argparse
import copy
import json
import re
import sys

# Standard medical analyte slug aliases connecting multi-source schemas.
SLUG_ALIASES = {
    "ck-total": "ck",
    "lp-a": "lpa",
    "non-hdl-cholesterol": "non-hdl",
    "cholesterol-hdl-ratio": "tc-hdl",
    "transferrin-saturation": "tsat",
    "vitamin-b12": "b12",
    "leukocyte-esterase": "urine-leukocyte-esterase",
    "urine-albumin": "urine-acr",
    "lead": "blood-lead",
    "mercury": "blood-mercury",
    "a-g-ratio": "ag-ratio",
    "rheumatoid-factor": "rf",
    "bilirubin": "total-bilirubin",
}

# Sub-strata in multi-analyte lessons that belong to their own atomic marker id.
SUBSTRATUM_TARGETS = [
    ("active b12", "active-b12"),
    ("rbc folate", "rbc-folate"),
    ("serum magnesium", "serum-magnesium"),
    ("serum copper", "copper"),
    ("zinc-to-copper", "zinc-copper-ratio"),
    ("omega-6 to omega-3", "omega6-omega3-ratio"),
    ("arachidonic acid to epa", "aa-epa-ratio"),
    ("omega-3 index", "omega-3-index"),
    ("rdw-sd", "rdw-sd"),
    ("neutrophil percentage", "neutrophil-pct"),
    ("(bands)", "neutrophil-bands"),
    ("(nlr)", "nlr"),
    ("free psa percentage", "free-psa-percent"),
    ("(hair)", "hair-mercury"),
    ("(urine)", "urine-mercury"),
]

# Panel-bundle IDs that expand into component tests when ordering.
BUNDLE_EXPANSIONS = {
    "cbc-overview": [
        "rbc", "hemoglobin", "hematocrit", "mcv", "mch", "mchc", "rdw", "wbc",
        "neutrophils", "lymphocytes", "monocytes", "eosinophils", "basophils", "platelets", "mpv",
    ],
    "cmp-overview": [
        "glucose", "bun", "creatinine", "egfr", "sodium", "potassium", "chloride", "co2",
        "calcium", "total-protein", "albumin", "globulin", "ag-ratio", "total-bilirubin", "alp", "ast", "alt",
    ],
    "lipid-panel-overview": ["total-cholesterol", "ldl-c", "hdl-c", "triglycerides"],
    "iron-panel-overview": ["ferritin", "serum-iron", "tibc", "tsat"],
    "urinalysis-overview": [
        "urine-specific-gravity", "urine-ph", "urine-protein", "urine-glucose", "urine-ketones",
        "urine-blood", "urine-bilirubin", "urine-urobilinogen", "urine-nitrites",
        "urine-leukocyte-esterase", "urine-wbc", "urine-rbc", "urine-bacteria",
    ],
}

# Universal SI mass/volume prefixes (in grams and liters) for metric scale sibling units.
_MASS_G = {"g": 1.0, "mg": 1e-3, "ug": 1e-6, "mcg": 1e-6, "µg": 1e-6, "ng": 1e-9, "pg": 1e-12}
_VOL_L = {"l": 1.0, "dl": 1e-1, "ml": 1e-3, "ul": 1e-6, "µl": 1e-6, "mcl": 1e-6}

_EQUIV_GROUPS = [
    {"u/l", "iu/l"},
    {"miu/l", "uiu/l", "µiu/ml", "uiu/ml", "miu/ml"},
    {"iu/ml"},
    {"ng/ml", "µg/l", "mcg/l", "ug/l"},
    {"ug/dl", "mcg/dl", "µg/dl"},
    {"mg/g", "µg/mg", "ug/mg", "mg/g (acr)"},
    {"nmol/ml", "µmol/l", "umol/l"},
    {"x10^3/ul", "x 10^9/l", "10^3/ul", "10^9/l", "k/ul"},
    {"cells/ul", "cells/µl", "cells/mcl", "cells per microliter", "per µl", "per microliter", "platelets per microliter", "/ul"},
    {"million/ul", "million cells/ul", "x 10^12/l"},
    {"µg/g", "ug/g", "ppm"},
]


def _metric_conc_g_per_l(unit_str):
    m = re.match(r"^\s*(g|mg|ug|mcg|µg|ng|pg)\s*/\s*(L|l|dL|dl|mL|ml|uL|ul|µL|mcL)\s*$", unit_str)
    if not m:
        return None
    mass, vol = m.group(1), m.group(2).lower()
    return _MASS_G[mass] / _VOL_L[vol]


def _unit_factor_to_target(src_unit, dst_unit):
    """Pure physical / SI factor such that value_in_src * factor == value_in_dst, or None."""
    if not src_unit or not dst_unit:
        return None
    s_low, d_low = src_unit.strip().lower(), dst_unit.strip().lower()
    if s_low == d_low:
        return 1.0
    for grp in _EQUIV_GROUPS:
        if s_low in grp and d_low in grp:
            return 1.0
    # Count concentration 10^3/uL (=10^9/L) <-> cells/uL
    k_grp = {"x10^3/ul", "x 10^9/l", "10^3/ul", "10^9/l", "k/ul"}
    c_grp = {"cells/ul", "cells/µl", "cells/mcl", "cells per microliter", "per µl", "per microliter", "platelets per microliter", "/ul"}
    if s_low in k_grp and d_low in c_grp:
        return 1000.0
    if s_low in c_grp and d_low in k_grp:
        return 0.001
    # Mass/volume metric ratio
    sc, dc = _metric_conc_g_per_l(src_unit), _metric_conc_g_per_l(dst_unit)
    if sc is not None and dc is not None:
        return round(sc / dc, 10)
    return None


def _parse_formula_conversions(primary, secondary_list, formula_text):
    """Extracts (toDefault, toDefaultOffset) for secondary units stated in conversion_formula."""
    out = {}
    if not formula_text or formula_text == "NOT_STATED" or not primary:
        return out
    text = formula_text.replace("×", "*").replace("÷", "/").replace("≈", "=")

    # Affine IFCC: IFCC (mmol/mol) = (10.93 * NGSP [%]) - 23.5
    m_ifcc = re.search(r"mmol/mol.*=\s*\(?([0-9.]+)\s*\*\s*NGSP.*?\)?\s*-\s*([0-9.]+)", text, re.I)
    if m_ifcc and primary == "%":
        slope = float(m_ifcc.group(1))
        intercept = float(m_ifcc.group(2))
        out["mmol/mol"] = (1.0 / slope, intercept / slope)

    for sec in secondary_list:
        sec_clean = sec.split("(")[0].strip()
        if not sec_clean or sec in out:
            continue
        direct = _unit_factor_to_target(sec_clean, primary)
        if direct is not None:
            out[sec] = (direct, None)
            continue
        p_esc, s_esc = re.escape(primary), re.escape(sec_clean)
        # "multiply PRIMARY by N to obtain/get SEC" => sec * (1/N) = primary
        m = re.search(rf"multiply\s+{p_esc}\s+by\s+(?:~|about\s+)?([0-9.]+)\s+to\s+(?:obtain|get)\s+{s_esc}", text, re.I)
        if m:
            out[sec] = (1.0 / float(m.group(1)), None)
            continue
        # "multiply SEC by N to obtain/get PRIMARY" => sec * N = primary
        m = re.search(rf"multiply\s+{s_esc}\s+by\s+(?:~|about\s+)?([0-9.]+)\s+to\s+(?:obtain|get)\s+{p_esc}", text, re.I)
        if m:
            out[sec] = (float(m.group(1)), None)
            continue
        # "divide PRIMARY by N to obtain/get SEC" => sec * N = primary
        m = re.search(rf"divide\s+(?:[A-Za-z]+\s+from\s+)?{p_esc}\s+(?:to\s+{s_esc},?\s+divide\s+)?by\s+([0-9.]+)", text, re.I)
        if m and sec_clean.lower() in text.lower():
            out[sec] = (float(m.group(1)), None)
            continue
        # "1 PRIMARY = N SEC" or "1 PRIMARY * N = SEC"
        m = re.search(rf"1(?:\.0)?\s*{p_esc}\s*(?:=|\*)\s*([0-9.]+)\s*=?\s*{s_esc}", text, re.I)
        if m:
            out[sec] = (1.0 / float(m.group(1)), None)
            continue
        # "1 SEC = N PRIMARY"
        m = re.search(rf"1(?:\.0)?\s*{s_esc}\s*=\s*([0-9.]+)\s*{p_esc}", text, re.I)
        if m:
            out[sec] = (float(m.group(1)), None)
            continue
        # "PRIMARY * N = SEC"
        m = re.search(rf"{p_esc}\s*\*\s*([0-9.]+)\s*=\s*{s_esc}", text, re.I)
        if m:
            out[sec] = (1.0 / float(m.group(1)), None)
            continue
        # "100 mg/dL = 1.0 g/L"
        m = re.search(rf"([0-9.]+)\s*{p_esc}\s*=\s*([0-9.]+)\s*{s_esc}", text, re.I)
        if m:
            out[sec] = (float(m.group(1)) / float(m.group(2)), None)
            continue
        if "equivalent" in text.lower() or "numerically identical" in text.lower():
            out[sec] = (1.0, None)
    return out


_ANALYTE_UNIT_FACTORS = {
    "total-cholesterol": ("mg/dL", [("mmol/L", 38.67)]),
    "hdl-c": ("mg/dL", [("mmol/L", 38.67)]),
    "non-hdl": ("mg/dL", [("mmol/L", 38.67)]),
    "albumin": ("g/dL", [("g/L", 0.1)]),
    "free-testosterone": ("pg/mL", [("pmol/L", 0.28842)]),
    "dhea-s": ("µg/dL", [("µmol/L", 36.85), ("umol/L", 36.85)]),
    "reverse-t3": ("ng/dL", [("nmol/L", 65.10)]),
    "bun": ("mg/dL", [("urea mmol/L", 2.801)]),
    "serum-magnesium": ("mg/dL", [("mmol/L", 2.4305)]),
    "rbc-magnesium": ("mg/dL", [("mmol/L", 2.4305)]),
    "zinc": ("mcg/dL", [("µmol/L", 6.538), ("umol/L", 6.538)]),
    "selenium": ("ng/mL", [("µmol/L", 78.96), ("umol/L", 78.96)]),
}


def _enrich_units(existing_units, nm_units, marker_id=None):
    """Builds a complete unit list with default unit preserved from existing_units when present."""
    units = [copy.deepcopy(u) for u in (existing_units or []) if isinstance(u.get("unit"), str)]
    default_unit = next((u["unit"] for u in units if u.get("default")), None)

    nm_primary = (nm_units or {}).get("primary")
    if nm_primary in (None, "", "NOT_STATED") or nm_primary.startswith(("semi-quantitative", "qualitative", "categorical")):
        nm_primary = None
    elif "(" in nm_primary and nm_primary.startswith("ratio"):
        nm_primary = "ratio"

    if not default_unit and nm_primary:
        default_unit = nm_primary
        units.insert(0, {"unit": default_unit, "default": True})
    elif units and not any(u.get("default") for u in units):
        units[0]["default"] = True
        default_unit = units[0]["unit"]

    if not default_unit:
        return units

    sec_list = list((nm_units or {}).get("secondary") or [])
    if nm_primary and nm_primary != default_unit and nm_primary not in sec_list:
        sec_list.insert(0, nm_primary)

    parsed = _parse_formula_conversions(nm_primary or default_unit, sec_list, (nm_units or {}).get("conversion_formula"))
    # Factor from nm_primary -> default_unit (1.0 when identical, else physical ratio e.g. platelets /uL -> x10^3/uL)
    prim_to_def = _unit_factor_to_target(nm_primary, default_unit) if nm_primary else 1.0
    if prim_to_def is None:
        prim_to_def = 1.0

    by_name = {u["unit"]: u for u in units}
    for sec in sec_list:
        sec_clean = sec.split("(")[0].strip() if "(" in sec and not sec.startswith("%") else sec.strip()
        if not sec_clean or sec_clean == "ratio":
            continue
        factor, offset = None, None
        if sec in parsed:
            f, off = parsed[sec]
            factor = f * prim_to_def
            offset = off * prim_to_def if off is not None else None
        else:
            direct = _unit_factor_to_target(sec_clean, default_unit)
            if direct is not None:
                factor = direct
        if sec_clean in by_name:
            if not by_name[sec_clean].get("default") and by_name[sec_clean].get("toDefault") is None and factor is not None:
                by_name[sec_clean]["toDefault"] = round(factor, 8)
                if offset is not None:
                    by_name[sec_clean]["toDefaultOffset"] = round(offset, 8)
        elif factor is not None:
            entry = {"unit": sec_clean, "toDefault": round(factor, 8)}
            if offset is not None:
                entry["toDefaultOffset"] = round(offset, 8)
            units.append(entry)
            by_name[sec_clean] = entry

    # Fill any existing unit still missing toDefault via SI/physical equivalence, and add common metric siblings (pg/mL <-> ng/dL, x10^9/L <-> x10^3/uL).
    for u in units:
        if not u.get("default") and u.get("toDefault") is None:
            f = _unit_factor_to_target(u["unit"], default_unit)
            if f is not None:
                u["toDefault"] = round(f, 8)

    metric_siblings = {
        "pg/mL": ["ng/dL", "ng/L"],
        "ng/dL": ["pg/mL", "ng/mL"],
        "ng/mL": ["µg/L", "ng/dL"],
        "ug/dL": ["mcg/dL", "µg/dL"],
        "mcg/dL": ["µg/dL", "ug/dL"],
        "µg/dL": ["mcg/dL", "ug/dL"],
        "x10^3/uL": ["x 10^9/L", "cells/uL"],
        "x 10^9/L": ["x10^3/uL", "cells/uL"],
        "million/uL": ["million cells/uL", "x 10^12/L"],
        "U/L": ["IU/L"],
        "mIU/L": ["uIU/mL"],
        "uIU/mL": ["mIU/L"],
        "µIU/mL": ["mIU/L"],
    }
    for sib in metric_siblings.get(default_unit, []):
        if sib not in by_name:
            f = _unit_factor_to_target(sib, default_unit)
            if f is not None:
                entry = {"unit": sib, "toDefault": round(f, 8)}
                units.append(entry)
                by_name[sib] = entry

    if marker_id in _ANALYTE_UNIT_FACTORS:
        expected_def, extra_factors = _ANALYTE_UNIT_FACTORS[marker_id]
        if default_unit.lower() == expected_def.lower():
            for sec_u, factor in extra_factors:
                match_u = next((u for u in units if u["unit"].lower() == sec_u.lower()), None)
                if match_u is not None:
                    if not match_u.get("default") and match_u.get("toDefault") is None:
                        match_u["toDefault"] = factor
                else:
                    entry = {"unit": sec_u, "toDefault": factor}
                    units.append(entry)
                    by_name[sec_u] = entry

    return units


def _infer_sex(population):
    p = (population or "").lower()
    if any(w in p for w in ("female", "women", "pregnan", "menopaus", "follicular", "luteal", "ovulation", "ivf")):
        return "female"
    if any(w in p for w in ("male", "men ", "men)", "adult men")) or p in ("male", "men"):
        return "male"
    return "any"


def _infer_age_bounds(text):
    t = (text or "").lower()
    m = re.search(r"(\d{2})\s*[-–]\s*(\d{2})", t)
    if m:
        return int(m.group(1)), int(m.group(2))
    m_plus = re.search(r"(\d{2})\+", t)
    if m_plus:
        return int(m_plus.group(1)), None
    if "under 50" in t:
        return 18, 49
    if "over 50" in t:
        return 50, None
    return None, None


def _infer_cycle_or_pregnancy(population):
    p = (population or "").lower()
    if "first trimester" in p:
        return None, "trimester_1"
    if "second and third trimester" in p:
        return None, "trimester_2_3"
    if "second trimester" in p:
        return None, "trimester_2"
    if "third trimester" in p:
        return None, "trimester_3"
    if "pregnan" in p:
        return None, "pregnant"
    if "postmenopaus" in p:
        return "postmenopausal", None
    if "early follicular" in p or "day 3" in p:
        return "early_follicular", None
    if "mid-follicular" in p:
        return "mid_follicular", None
    if "late follicular" in p or "preovulatory" in p or "midcycle" in p or "ovulation" in p:
        return "ovulation", None
    if "luteal" in p:
        return "luteal", None
    if "premenopaus" in p:
        return "premenopausal", None
    return None, None


def _parse_sweet_spot_range(text):
    if not text:
        return None, None
    m = re.search(r"~?\s*([0-9]+(?:\.[0-9]+)?)\s*(?:to|[-–])\s*([0-9]+(?:\.[0-9]+)?)", text)
    if m:
        return float(m.group(1)), float(m.group(2))
    return None, None


def _convert_val_to_default(val, src_unit, default_unit, units_list):
    if val is None:
        return None
    if not src_unit or src_unit == "NOT_STATED" or not default_unit or src_unit == default_unit:
        return val
    for u in units_list:
        if u["unit"].lower() == src_unit.lower() and u.get("toDefault") is not None:
            return round(val * u["toDefault"] + (u.get("toDefaultOffset") or 0.0), 6)
    f = _unit_factor_to_target(src_unit, default_unit)
    if f is not None:
        return round(val * f, 6)
    return val


def _build_strata_for_record(raw_strata, default_unit, units_list):
    built = []
    for s in raw_strata or []:
        pop = s.get("population") or "Adult All"
        if "newborn" in pop.lower() or "children" in pop.lower():
            continue
        std = s.get("standard_range") or {}
        opt = s.get("functional_optimal") or {}
        raw_bands = s.get("bands") or []

        std_unit = std.get("unit") if std.get("unit") not in (None, "NOT_STATED") else default_unit
        opt_unit = opt.get("unit") if opt.get("unit") not in (None, "NOT_STATED") else std_unit

        std_low = _convert_val_to_default(std.get("low"), std_unit, default_unit, units_list)
        std_high = _convert_val_to_default(std.get("high"), std_unit, default_unit, units_list)
        opt_low = _convert_val_to_default(opt.get("low"), opt_unit, default_unit, units_list)
        opt_high = _convert_val_to_default(opt.get("high"), opt_unit, default_unit, units_list)
        sweet_spot = opt.get("sweet_spot") if opt.get("sweet_spot") not in (None, "NOT_STATED") else None

        opt_bands = [b for b in raw_bands if b.get("tier") == "optimal"]

        # D6: Postmenopausal natural vs on-HRT split when functional_optimal is above unreplaced standard ceiling.
        if (
            "postmenopaus" in pop.lower()
            and std_high is not None
            and opt_low is not None
            and opt_low > std_high
            and sweet_spot
            and "hrt" in sweet_spot.lower()
        ):
            unreplaced_high = opt_bands[0].get("max") if opt_bands and opt_bands[0].get("max") is not None else std_high
            unreplaced_high = _convert_val_to_default(unreplaced_high, opt_unit, default_unit, units_list)
            built.append(_finish_stratum(f"{pop} (No HRT)", std_low, std_high, None, unreplaced_high, "Without HRT", raw_bands, default_unit, opt_unit, units_list, requires_hrt=False))
            built.append(_finish_stratum(f"{pop} (On HRT)", std_low, std_high, opt_low, opt_high, sweet_spot, [], default_unit, opt_unit, units_list, requires_hrt=True))
            continue

        # D2: Zero-width optimal (e.g. 1.0 - 1.0) -> recover real span from optimal band, sweet_spot, or standard_range.
        if opt_low is not None and opt_high is not None and opt_low == opt_high:
            if opt_bands and opt_bands[0].get("min") is not None and opt_bands[0].get("max") is not None and opt_bands[0]["min"] < opt_bands[0]["max"]:
                opt_low = _convert_val_to_default(opt_bands[0]["min"], opt_unit, default_unit, units_list)
                opt_high = _convert_val_to_default(opt_bands[0]["max"], opt_unit, default_unit, units_list)
            else:
                sw_lo, sw_hi = _parse_sweet_spot_range(sweet_spot)
                if sw_lo is not None and sw_hi is not None and sw_lo < sw_hi:
                    opt_low, opt_high = sw_lo, sw_hi
                elif std_low is not None and std_high is not None and std_low < std_high:
                    opt_low, opt_high = std_low, std_high

        # D3: Missing lower optimal bound when bands[] carries an explicit bounded optimal interval.
        if opt_low is None and opt_high is not None and len(opt_bands) == 1:
            b_min, b_max = opt_bands[0].get("min"), opt_bands[0].get("max")
            if b_min is not None and b_max is not None and b_min > 0:
                opt_low = _convert_val_to_default(b_min, opt_unit, default_unit, units_list)
                opt_high = _convert_val_to_default(b_max, opt_unit, default_unit, units_list)

        # D7: Zero ceiling (<= 0) when bands[optimal] gives a detection-limit ceiling (< 1.0).
        if opt_low is None and opt_high == 0 and opt_bands:
            b_max = opt_bands[0].get("max")
            if b_max is not None and b_max > 0:
                opt_high = _convert_val_to_default(b_max, opt_unit, default_unit, units_list)

        built.append(_finish_stratum(pop, std_low, std_high, opt_low, opt_high, sweet_spot, raw_bands, default_unit, opt_unit, units_list))
    return built


def _finish_stratum(pop, std_low, std_high, opt_low, opt_high, sweet_spot, raw_bands, default_unit, band_src_unit, units_list, requires_hrt=None):
    sex = _infer_sex(pop)
    age_min, age_max = _infer_age_bounds(pop)
    cycle_phase, pregnancy = _infer_cycle_or_pregnancy(pop)
    p_low = pop.lower()
    modifier = None
    if "endurance athlete" in p_low:
        modifier = "endurance_athlete"
    elif "smoker" in p_low:
        modifier = "smoker"
    elif "african ancestry" in p_low:
        modifier = "african_ancestry"
    assay = "lc-ms-ms" if "lc-ms/ms" in p_low else ("equilibrium-dialysis" if "equilibrium dialysis" in p_low else None)

    tier_bands = []
    for b in raw_bands:
        b_min = _convert_val_to_default(b.get("min"), band_src_unit, default_unit, units_list)
        b_max = _convert_val_to_default(b.get("max"), band_src_unit, default_unit, units_list)
        tier_bands.append({
            "tier": b.get("tier") or "normal",
            "min": b_min,
            "max": b_max,
            "meaning": b.get("meaning"),
        })

    out = {
        "population": pop,
        "sex": sex,
        "unit": default_unit,
        "standardLow": std_low,
        "standardHigh": std_high,
        "optimalLow": opt_low,
        "optimalHigh": opt_high,
        "sweetSpot": sweet_spot,
        "bands": tier_bands,
    }
    if age_min is not None:
        out["ageMin"] = age_min
    if age_max is not None:
        out["ageMax"] = age_max
    if cycle_phase:
        out["cyclePhase"] = cycle_phase
    if pregnancy:
        out["pregnancy"] = pregnancy
    if modifier:
        out["modifier"] = modifier
    if assay:
        out["assay"] = assay
    if requires_hrt is not None:
        out["requiresHRT"] = requires_hrt
    return out


def _strata_to_legacy_bands(strata, default_unit, existing_qualitative_bands):
    """Synthesizes clean LabBand rows so existing LabReader callers work without false disputed overlaps."""
    if existing_qualitative_bands:
        return copy.deepcopy(existing_qualitative_bands)
    bands = []
    for s in strata:
        is_conditional = any(s.get(k) is not None for k in ("cyclePhase", "pregnancy", "modifier", "ageMin", "ageMax")) or s.get("requiresHRT") is True
        cond = s["population"] if is_conditional else None
        sex = s.get("sex", "any")
        unit = s.get("unit") or default_unit
        if s.get("standardLow") is not None or s.get("standardHigh") is not None:
            b = {"label": "Standard range", "kind": "lab", "low": s.get("standardLow"), "high": s.get("standardHigh"), "unit": unit, "sex": sex}
            if cond:
                b["condition"] = cond
            bands.append(b)
        if s.get("optimalLow") is not None or s.get("optimalHigh") is not None:
            b = {"label": "Optimal", "kind": "optimal", "low": s.get("optimalLow"), "high": s.get("optimalHigh"), "unit": unit, "sex": sex}
            if s.get("sweetSpot"):
                b["meaning"] = s["sweetSpot"]
            if cond:
                b["condition"] = cond
            bands.append(b)
        elif not is_conditional:
            # Union any optimal sub-bands in s["bands"] into clean non-conflicting optimal band(s)
            opt_tiers = [tb for tb in s.get("bands", []) if tb.get("tier") == "optimal" and (tb.get("min") is not None or tb.get("max") is not None)]
            if opt_tiers:
                lows = [tb["min"] for tb in opt_tiers if tb.get("min") is not None]
                highs = [tb["max"] for tb in opt_tiers if tb.get("max") is not None]
                has_open_low = any(tb.get("min") is None for tb in opt_tiers)
                has_open_high = any(tb.get("max") is None for tb in opt_tiers)
                b = {
                    "label": "Optimal",
                    "kind": "optimal",
                    "low": None if has_open_low else (min(lows) if lows else None),
                    "high": None if has_open_high else (max(highs) if highs else None),
                    "unit": unit,
                    "sex": sex,
                }
                bands.append(b)
    return bands


def _parse_threshold_bounds(cond_text, scale=1.0):
    if not cond_text:
        return None, None
    t = cond_text.strip()
    m_range = re.match(r"^([0-9]+(?:\.[0-9]+)?)\s*[-–]\s*([0-9]+(?:\.[0-9]+)?)", t)
    if m_range:
        return round(float(m_range.group(1)) * scale, 6), round(float(m_range.group(2)) * scale, 6)
    m_gt = re.match(r"^>=?\s*([0-9]+(?:\.[0-9]+)?)", t)
    if m_gt:
        return round(float(m_gt.group(1)) * scale, 6), None
    m_lt = re.match(r"^<=?\s*([0-9]+(?:\.[0-9]+)?)", t)
    if m_lt:
        return None, round(float(m_lt.group(1)) * scale, 6)
    return None, None


GENE_ENTRY_MAP = {
    "07.01.01": ("mthfr", "MTHFR", []),
    "07.01.02": ("mtr-mtrr", "MTR / MTRR", ["mtr", "mtrr"]),
    "07.01.03": ("fads1-fads2", "FADS1 / FADS2", ["fads1", "fads2"]),
    "07.01.04": ("bco1", "BCO1", ["bcmo1"]),
    "07.01.05": ("pemt", "PEMT", []),
    "07.01.06": ("hfe", "HFE", []),
    "07.02.01": ("fut2", "FUT2", []),
    "07.02.02": ("hla-dq2-dq8", "HLA-DQ2 / DQ8", []),
    "07.02.03": ("lct-mcm6", "LCT / MCM6", ["lct", "mcm6"]),
    "07.03.01": ("apoe", "APOE", []),
    "07.03.02": ("tcf7l2", "TCF7L2", []),
    "07.03.03": ("fto", "FTO", []),
    "07.03.04": ("cyp1a2", "CYP1A2", []),
    "07.03.05": ("comt", "COMT", []),
    "07.03.06": ("aldh2", "ALDH2", []),
    "07.04.01": ("lpa-gene", "LPA", []),
    "07.04.02": ("vdr", "VDR", ["gc-cyp2r1"]),
    "07.04.03": ("actn3-ace", "ACTN3 / ACE", ["actn3", "ace"]),
    "07.04.04": ("gstm1-gstt1", "GSTM1 / GSTT1", ["gstm1", "gstt1", "gstp1"]),
    "07.04.05": ("sod2", "SOD2", []),
    "07.04.06": ("salt-sensitivity", "Salt Sensitivity (AGT / ACE / CYP11B2 / ADD1)", ["agt", "cyp11b2", "add1"]),
    "07.05.01": ("f5-f2", "Factor V Leiden / Prothrombin (F5 / F2)", ["f5", "f2"]),
    "07.05.02": ("g6pd", "G6PD", []),
    "07.05.03": ("cyp2d6-cyp2c19", "CYP2D6 / CYP2C19", ["cyp2d6", "cyp2c19"]),
}

ACTION_TO_BUCKET = {
    "nutrient_swap": "take",
    "marker_shift": "read",
    "priority_shift": "priority",
    "change_nothing": "nothing",
    "hard_contraindication": "doctor",
}


def _slugify_gene(entry):
    eid = entry.get("gene_entry_id") or ""
    if eid in GENE_ENTRY_MAP:
        return GENE_ENTRY_MAP[eid]
    syms = [g.get("symbol", "") for g in (entry.get("genes") or []) if g.get("symbol")]
    title_head = (entry.get("title") or eid).split(" - ")[0].strip()
    raw = "-".join(syms) if syms else title_head
    slug = re.sub(r"[^a-z0-9]+", "-", raw.lower()).strip("-")
    legacy = [re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-") for s in syms if len(syms) > 1]
    return slug, title_head, [x for x in legacy if x != slug]


def _compile_genetics(genetics_entries, base_genes, base_guide, by_id, resolve_ref, pattern_id_to_slug):
    if not genetics_entries:
        return copy.deepcopy(base_genes or []), copy.deepcopy(base_guide or [])

    base_by_id = {g["id"]: g for g in (base_genes or [])}
    guide_out = []
    genes_out = []

    for entry in genetics_entries:
        eid = entry.get("gene_entry_id") or ""
        cat = entry.get("action_category") or "change_nothing"
        ir = entry.get("intervention_rules") or {}
        caveats = entry.get("testing_and_ancestry_caveats") or {}

        if cat == "foundational":
            if entry.get("core_thesis"):
                guide_out.append({"text": entry["core_thesis"], "source": eid, "kind": "thesis"})
            for rule in ir.get("what_not_to_do") or []:
                guide_out.append({"text": rule, "source": eid, "kind": "guardrail"})
            for blind in caveats.get("dtc_microarray_blind_spots") or []:
                guide_out.append({"text": blind, "source": eid, "kind": "caveat"})
            for anc in caveats.get("ancestry_discrepancies") or []:
                guide_out.append({"text": anc, "source": eid, "kind": "ancestry"})
            for trap in caveats.get("timing_or_assay_traps") or []:
                guide_out.append({"text": trap, "source": eid, "kind": "assay"})
            continue

        slug, display_name, legacy_ids = _slugify_gene(entry)
        bucket = ACTION_TO_BUCKET.get(cat, "nothing")

        # Variant summary line from genes[].rsids & star_or_named_alleles
        loci_parts = []
        symbols = []
        for g in entry.get("genes") or []:
            sym = g.get("symbol") or ""
            if sym and sym not in symbols:
                symbols.append(sym)
            bits = list(g.get("rsids") or []) + list(g.get("star_or_named_alleles") or [])
            if bits:
                loci_parts.append(f"{sym}: {', '.join(bits[:4])}" if len(entry.get("genes") or []) > 1 else ", ".join(bits[:5]))
        variant_summary = "; ".join(loci_parts) if loci_parts else None

        # Resolve phenotypic_verifiers accurately
        bi = entry.get("bloodwork_integration") or {}
        verifiers = []
        orderable_marker_ids = []
        confirm_names = []

        for v in bi.get("phenotypic_verifiers") or []:
            raw_mid = (v.get("marker_id") or "").strip()
            m_name = v.get("marker_name") or raw_mid
            role = v.get("role") or "surveillance"
            rule_txt = v.get("rule") or ""

            if raw_mid.startswith(("None", "N/A", "Prescriber-Ordered")):
                verifiers.append({
                    "kind": "non_lab",
                    "markerID": None,
                    "patternID": None,
                    "markerName": m_name,
                    "role": role,
                    "rule": rule_txt,
                })
                continue

            if raw_mid.startswith("Cuff"):
                bp_id = "blood-pressure" if "blood-pressure" in by_id else None
                verifiers.append({
                    "kind": "marker" if bp_id else "non_lab",
                    "markerID": bp_id,
                    "patternID": None,
                    "markerName": m_name,
                    "role": role,
                    "rule": rule_txt,
                })
                confirm_names.append(m_name)
                continue

            if raw_mid in pattern_id_to_slug:
                verifiers.append({
                    "kind": "pattern",
                    "markerID": None,
                    "patternID": pattern_id_to_slug[raw_mid],
                    "markerName": m_name,
                    "role": role,
                    "rule": rule_txt,
                })
                continue

            if not raw_mid or not re.match(r"^\d{2}\.\d{2}\.\d{2}$", raw_mid):
                verifiers.append({
                    "kind": "external_lab",
                    "markerID": None,
                    "patternID": None,
                    "markerName": m_name,
                    "role": role,
                    "rule": rule_txt,
                })
                confirm_names.append(m_name)
                continue

            # Resolve 02.XX.YY marker ID with multi-analyte precision
            resolved_ids = []
            low_name = m_name.lower()
            if raw_mid == "02.11.07" and "omega-3-index" in by_id:
                resolved_ids.append("omega-3-index")
            elif raw_mid == "02.11.03" and "rbc folate" in low_name and "rbc-folate" in by_id:
                resolved_ids.append("rbc-folate")
                if "folate" in by_id:
                    resolved_ids.append("folate")
            elif raw_mid == "02.06.08" and "remnant" in low_name and "remnant-cholesterol" in by_id:
                if "non-hdl" in by_id:
                    resolved_ids.append("non-hdl")
                resolved_ids.append("remnant-cholesterol")
            else:
                r = resolve_ref(raw_mid)
                if r:
                    resolved_ids.append(r)

            for rid in resolved_ids:
                verifiers.append({
                    "kind": "marker",
                    "markerID": rid,
                    "patternID": None,
                    "markerName": by_id[rid]["name"] if rid in by_id else m_name,
                    "role": role,
                    "rule": rule_txt,
                })
                if role in ("mandatory_confirmer", "outranks_genotype", "safety_gate") and rid not in orderable_marker_ids:
                    orderable_marker_ids.append(rid)
            confirm_names.append(m_name)

        # Collect legacy genotype strings from base genes so saved user genotypes continue to resolve
        legacy_genotypes = []
        for lid in [slug] + legacy_ids:
            bg = base_by_id.get(lid)
            if bg:
                for lg in bg.get("genotypes") or []:
                    g_str = lg.get("genotype")
                    if g_str and g_str not in legacy_genotypes:
                        legacy_genotypes.append(g_str)

        genotypes_out = []
        for vt in entry.get("variant_tiers") or []:
            g_label = vt.get("genotype_or_phenotype") or ""
            risk = vt.get("risk_level") or "baseline"
            impact = vt.get("activity_or_risk_impact") or ""
            c_rule = vt.get("clinical_rule") or ""

            is_baseline = risk == "baseline"
            urgency = None
            if not is_baseline and cat == "hard_contraindication":
                urgency = "urgent" if risk == "critical_red_line" else "routine"
            elif risk == "critical_red_line" and eid in ("07.01.06", "07.03.06"):
                urgency = "soon"

            adds = []
            if not is_baseline or cat == "change_nothing":
                adds = list(orderable_marker_ids)
                for v in verifiers:
                    if v["kind"] == "external_lab" and v["role"] in ("mandatory_confirmer", "outranks_genotype", "safety_gate") and not is_baseline:
                        if v["markerName"] not in adds:
                            adds.append(v["markerName"])

            genotypes_out.append({
                "genotype": g_label,
                "meaning": impact,
                "actions": [c_rule] if c_rule else [],
                "addsMarkers": adds,
                "urgency": urgency,
                "riskLevel": risk,
                "clinicalRule": c_rule,
            })

        shifts_raw = bi.get("threshold_or_screening_shifts") or {}
        shifts_obj = {
            "advanceScreeningYears": shifts_raw.get("advance_screening_years"),
            "tightenedTargets": list(shifts_raw.get("tightened_targets") or []),
            "behavioralStrictness": list(shifts_raw.get("behavioral_strictness") or []),
        }

        swaps_out = [
            {
                "replaceOrAvoid": s.get("replace_or_avoid") or "",
                "useInstead": s.get("use_instead") or "",
                "targetGenotypes": list(s.get("target_genotypes") or []),
                "crossVolumeRef": s.get("cross_volume_ref"),
            }
            for s in (ir.get("form_substitutions") or [])
        ]

        contras_out = [
            {
                "triggerGenotype": h.get("trigger_genotype") or "",
                "forbiddenItems": list(h.get("forbidden_items") or []),
                "mandatoryReferral": h.get("mandatory_referral"),
                "coachStopLine": h.get("coach_stop_line") or "",
            }
            for h in (ir.get("hard_contraindications_and_referrals") or [])
        ]

        epistatic_out = [
            {
                "condition": eg.get("condition") or "",
                "interpretation": eg.get("interpretation") or "",
                "action": eg.get("action") or "",
            }
            for eg in (bi.get("epistatic_diagnostic_grid") or [])
        ]

        caveats_obj = {
            "dtcBlindSpots": list(caveats.get("dtc_microarray_blind_spots") or []),
            "ancestryDiscrepancies": list(caveats.get("ancestry_discrepancies") or []),
            "timingOrAssayTraps": list(caveats.get("timing_or_assay_traps") or []),
        }

        genes_out.append({
            "id": slug,
            "entryID": eid,
            "name": display_name,
            "title": entry.get("title") or display_name,
            "symbols": symbols,
            "legacyIDs": legacy_ids,
            "legacyGenotypes": legacy_genotypes,
            "variant": variant_summary,
            "bucket": bucket,
            "actionCategory": cat,
            "coreThesis": entry.get("core_thesis"),
            "mechanismSummary": entry.get("mechanism_summary"),
            "genotypes": genotypes_out,
            "confirmWith": confirm_names,
            "phenotypicVerifiers": verifiers,
            "epistaticGrid": epistatic_out,
            "thresholdShifts": shifts_obj,
            "changeNothingMandate": bool(ir.get("change_nothing_mandate")),
            "formSubstitutions": swaps_out,
            "hardContraindications": contras_out,
            "whatNotToDo": list(ir.get("what_not_to_do") or []),
            "caveats": caveats_obj,
            "source": eid,
        })

    if not guide_out:
        guide_out = copy.deepcopy(base_guide or [])
    return genes_out, guide_out


def compile_catalogue(base, global_protocols, baseline_panels, markers, patterns, genetics=None):
    base_markers = copy.deepcopy((base or {}).get("markers") or [])
    by_id = {m["id"]: m for m in base_markers}
    ordered_ids = [m["id"] for m in base_markers]

    # Map lesson_id (02.XX.YY) -> primary marker slug
    lesson_to_slug = {}
    for nm in markers or []:
        lid = nm["marker_id"]
        raw_slug = nm["slug"]
        slug = SLUG_ALIASES.get(raw_slug, raw_slug)
        if slug not in by_id:
            # Check if a single base marker already cites this exact lesson id
            matches = [m["id"] for m in base_markers if lid in re.split(r"[;, ]+", m.get("lesson") or "")]
            if len(matches) == 1 and not raw_slug.endswith("-overview"):
                slug = matches[0]
        lesson_to_slug[lid] = slug
        if slug not in by_id:
            by_id[slug] = {"id": slug, "name": nm["name"], "aliases": list(nm.get("aliases") or []), "units": [], "bands": []}
            ordered_ids.append(slug)

    def resolve_ref(ref):
        if not ref:
            return None
        if ref in by_id:
            return ref
        if ref in lesson_to_slug:
            return lesson_to_slug[ref]
        if ref in SLUG_ALIASES and SLUG_ALIASES[ref] in by_id:
            return SLUG_ALIASES[ref]
        return ref

    # Enrich markers from markers.json
    for nm in markers or []:
        lid = nm["marker_id"]
        raw_slug = nm["slug"]
        slug = lesson_to_slug[lid]
        target = by_id[slug]
        target["lessonID"] = lid
        if not target.get("lesson"):
            target["lesson"] = lid
        if not target.get("chapter") and nm.get("section"):
            target["chapter"] = re.sub(r"^Vol\s*\d+\s*-\s*\d+\s*", "", nm["section"]).strip()

        for alias in nm.get("aliases") or []:
            if alias not in target.setdefault("aliases", []) and alias != target.get("name"):
                target["aliases"].append(alias)

        is_overview = raw_slug.endswith("-overview") or raw_slug in BUNDLE_EXPANSIONS
        if is_overview:
            target["isOverview"] = True
            target["bands"] = []
            target["strata"] = []
            continue

        # Partition multi-analyte strata to their dedicated atomic markers when present in catalogue
        primary_strata_raw = []
        routed_strata = {}
        for s in nm.get("reference_strata") or []:
            pop_low = (s.get("population") or "").lower()
            sub_target = None
            for needle, sub_id in SUBSTRATUM_TARGETS:
                if needle in pop_low and sub_id in by_id and sub_id != slug:
                    sub_target = sub_id
                    break
            if sub_target:
                routed_strata.setdefault(sub_target, []).append(s)
            else:
                primary_strata_raw.append(s)

        # Cortisol 02.01.02 LC-MS/MS merges as an LC-MS/MS assay stratum onto cortisol
        if raw_slug == "cortisol-am-lc-ms-ms" and "cortisol" in by_id:
            cort = by_id["cortisol"]
            cort_def = next((u["unit"] for u in cort.get("units", []) if u.get("default")), "ug/dL")
            lcms_strata = []
            for s in primary_strata_raw:
                s_copy = copy.deepcopy(s)
                s_copy["population"] = f"{s_copy.get('population', 'Adult All')} (LC-MS/MS)"
                lcms_strata.append(s_copy)
            built_lcms = _build_strata_for_record(lcms_strata, cort_def, cort.get("units", []))
            cort.setdefault("strata", []).extend(built_lcms)
            if slug != "cortisol" and slug in ordered_ids and slug not in {m["id"] for m in base_markers}:
                ordered_ids.remove(slug)
                del by_id[slug]
            lesson_to_slug[lid] = "cortisol"
            continue

        target["units"] = _enrich_units(target.get("units"), nm.get("units"), marker_id=slug)
        default_unit = next((u["unit"] for u in target["units"] if u.get("default")), None)

        # D5: Check if base marker had age-bracketed lab bands that new JSON collapsed
        base_age_bands = [b for b in (target.get("bands") or []) if "age" in (b.get("condition") or "").lower() or re.search(r"\b\d0s\b", (b.get("label") or "").lower())]
        qual_bands = [b for b in (target.get("bands") or []) if b.get("values")]

        built_strata = _build_strata_for_record(primary_strata_raw, default_unit, target["units"])
        if len(base_age_bands) >= 3 and not any(s.get("ageMin") is not None for s in built_strata):
            # Preserve age-bracketed strata & bands from base
            age_strata = []
            for ab in base_age_bands:
                amin, amax = _infer_age_bounds((ab.get("condition") or "") + " " + (ab.get("label") or ""))
                st = {
                    "population": f"{(ab.get('sex') or 'any').capitalize()} {ab.get('condition') or ab.get('label')}",
                    "sex": ab.get("sex") or "any",
                    "unit": ab.get("unit") or default_unit,
                    "standardLow": ab.get("low"),
                    "standardHigh": ab.get("high"),
                    "optimalLow": None,
                    "optimalHigh": None,
                    "sweetSpot": built_strata[0].get("sweetSpot") if built_strata else None,
                    "bands": [],
                }
                if amin is not None:
                    st["ageMin"] = amin
                if amax is not None:
                    st["ageMax"] = amax
                age_strata.append(st)
            target["strata"] = age_strata + built_strata
            # Keep base bands intact
        else:
            target["strata"] = built_strata
            if built_strata:
                # Preserve existing non-lab/non-optimal watch/flag bands while replacing lab/optimal cleanly
                extra_bands = [b for b in (target.get("bands") or []) if b.get("kind") not in ("lab", "optimal")]
                target["bands"] = _strata_to_legacy_bands(built_strata, default_unit, qual_bands) + extra_bands

        # Apply routed sub-strata onto their dedicated atomic markers (e.g. zinc-copper-ratio, active-b12, copper)
        for sub_id, sub_raw in routed_strata.items():
            sub_m = by_id[sub_id]
            sub_def = next((u["unit"] for u in sub_m.get("units", []) if u.get("default")), None) or (sub_raw[0].get("standard_range") or {}).get("unit")
            if sub_def and not sub_m.get("units"):
                sub_m["units"] = [{"unit": sub_def, "default": True}]
            sub_built = _build_strata_for_record(sub_raw, sub_def, sub_m.get("units", []))
            sub_m["strata"] = sub_built
            if not sub_m.get("bands") or sub_id == "zinc-copper-ratio":
                sub_m["bands"] = _strata_to_legacy_bands(sub_built, sub_def, [])

        # Attach structured clinical fields (Part 0, 1, 2, 3, 4)
        co_tests = []
        for cid in (nm.get("interpretation_logic") or {}).get("co_tests") or []:
            resolved = resolve_ref(cid)
            if resolved and resolved != slug and resolved not in co_tests:
                # Expand overview bundles into concrete markers if needed
                if by_id.get(resolved, {}).get("isOverview") and resolved in BUNDLE_EXPANSIONS:
                    for sub in BUNDLE_EXPANSIONS[resolved]:
                        if sub in by_id and sub not in co_tests:
                            co_tests.append(sub)
                else:
                    co_tests.append(resolved)
        target["coTests"] = co_tests
        target["discordance"] = list((nm.get("interpretation_logic") or {}).get("discordance_and_masking") or [])

        pa = nm.get("pre_analytic_protocol")
        if pa:
            target["preAnalytic"] = {
                "fastingRequired": bool(pa.get("fasting_required")),
                "fastingHours": pa.get("fasting_hours") if pa.get("fasting_hours") != "NOT_STATED" else None,
                "timingWindow": pa.get("timing_window") if pa.get("timing_window") != "NOT_STATED" else None,
                "washouts": [
                    {"item": w.get("item", ""), "window": w.get("window", ""), "effect": w.get("effect", "")}
                    for w in (pa.get("washout_restrictions") or [])
                ],
                "sampleHandling": pa.get("sample_stability_and_handling") if pa.get("sample_stability_and_handling") != "NOT_STATED" else None,
                "redrawTriggers": list(pa.get("redraw_triggers") or []),
            }

        specs = nm.get("specimen_and_assay") or []
        if specs:
            target["specimens"] = [
                {
                    "matrix": sp.get("matrix", ""),
                    "preferredAssay": sp.get("preferred_assay", ""),
                    "targetPopulation": sp.get("target_population", ""),
                    "assayPitfall": sp.get("assay_pitfall", ""),
                }
                for sp in specs
            ]

        inter = nm.get("interventions")
        if inter:
            t3 = []
            for item in inter.get("tier_3_supplements") or []:
                if isinstance(item, dict):
                    t3.append({
                        "name": item.get("name", ""),
                        "dose": item.get("dose") if item.get("dose") != "NOT_STATED" else None,
                        "target": item.get("target_direction") or item.get("target_phenotype"),
                        "notes": item.get("mechanism") or item.get("mechanism_and_notes"),
                    })
                elif isinstance(item, str):
                    t3.append({"name": item, "dose": None, "target": None, "notes": None})
            t4 = [x if isinstance(x, str) else f"{x.get('compound', '')}: {x.get('notes', '')}".strip(": ") for x in (inter.get("tier_4_peptides_educational") or [])]
            target["interventions"] = {
                "tier1Foundations": list(inter.get("tier_1_foundations") or []),
                "tier2Nutrition": list(inter.get("tier_2_nutrition") or []),
                "tier3Supplements": t3,
                "tier4Peptides": t4,
                "whatNotToDo": list(inter.get("what_not_to_do") or []),
            }

        esc_block = nm.get("medical_escalation")
        if esc_block:
            target["escalation"] = {
                "urgentSameDay": list(esc_block.get("urgent_same_day") or []),
                "routineSoon": list(esc_block.get("routine_soon") or esc_block.get("routine_referral_triggers") or []),
                "specialists": list(esc_block.get("specialists") or []),
            }

        spec_sub = nm.get("specialty_subschema")
        if spec_sub and spec_sub.get("type") not in (None, "NONE"):
            target["specialty"] = {"kind": spec_sub["type"], "details": spec_sub.get("details")}

    # Enable Cortisol / DHEA-S formula if present (locked choice)
    if "cortisol-dhea-ratio" in by_id and "cortisol" in by_id and "dhea-s" in by_id:
        cdr = by_id["cortisol-dhea-ratio"]
        cort_def = next((u["unit"] for u in by_id["cortisol"].get("units", []) if u.get("default")), "ug/dL")
        dhea_def = next((u["unit"] for u in by_id["dhea-s"].get("units", []) if u.get("default")), "µg/dL")
        cdr["computed"] = True
        if not cdr.get("units"):
            cdr["units"] = [{"unit": "ratio", "default": True}]
        cdr["formula"] = {"expr": "{cortisol} * 100 / {dhea-s}", "inputs": {"cortisol": cort_def, "dhea-s": dhea_def}, "source": "02.14.02"}

    # Ensure every remaining base marker also has physical unit factors filled (e.g. wbc x 10^9/L, platelets per µL)
    for mid in ordered_ids:
        m = by_id[mid]
        if m.get("units"):
            m["units"] = _enrich_units(m["units"], None, marker_id=mid)

    # Compile Baseline Recommended Panels (Part 0) + preserve conditional panels from base
    out_panels = []
    bp_root = (baseline_panels or {}).get("baseline_recommended_panels") or {}

    def expand_panel_item(raw_id):
        slug = resolve_ref(raw_id)
        if slug in BUNDLE_EXPANSIONS:
            return [x for x in BUNDLE_EXPANSIONS[slug] if x in by_id]
        return [slug] if slug else []

    if bp_root:
        core_ids, core_notes = [], {}
        for item in bp_root.get("core_all_adults") or []:
            expanded = expand_panel_item(item["marker_id"])
            for eid in expanded:
                if eid not in core_ids:
                    core_ids.append(eid)
                if item.get("rationale"):
                    core_notes.setdefault(eid, item["rationale"])
        if core_ids:
            out_panels.append({
                "id": "baseline-core",
                "name": "Core adult baseline",
                "markers": core_ids,
                "when": "first",
                "drawNotes": core_notes,
                "source": "baseline_recommended_panels",
            })

        male_ids, male_notes = [], {}
        for item in bp_root.get("male_specific") or []:
            for eid in expand_panel_item(item["marker_id"]):
                if eid not in male_ids:
                    male_ids.append(eid)
                if item.get("draw_notes"):
                    male_notes[eid] = item["draw_notes"]
        if male_ids:
            out_panels.append({
                "id": "baseline-male",
                "name": "Male hormone baseline",
                "markers": male_ids,
                "when": "first",
                "tag": "male",
                "drawNotes": male_notes,
                "source": "baseline_recommended_panels",
            })

        female_ids, female_notes = [], {}
        for item in bp_root.get("female_specific") or []:
            for eid in expand_panel_item(item["marker_id"]):
                if eid not in female_ids:
                    female_ids.append(eid)
                if item.get("draw_notes"):
                    female_notes[eid] = item["draw_notes"]
        if female_ids:
            out_panels.append({
                "id": "baseline-female",
                "name": "Female hormone baseline",
                "markers": female_ids,
                "when": "first",
                "tag": "female",
                "drawNotes": female_notes,
                "source": "baseline_recommended_panels",
            })

        upg_ids, upg_notes = [], {}
        for item in bp_root.get("tier_2_and_3_conditional_upgrades") or []:
            for eid in expand_panel_item(item["marker_id"]):
                if eid not in upg_ids:
                    upg_ids.append(eid)
                if item.get("when_to_order"):
                    upg_notes[eid] = item["when_to_order"]
        if upg_ids:
            out_panels.append({
                "id": "baseline-upgrades",
                "name": "Tier 2 & 3 symptom/context upgrades",
                "markers": upg_ids,
                "when": "upgrade",
                "drawNotes": upg_notes,
                "source": "baseline_recommended_panels",
            })

    seen_panel_ids = {p["id"] for p in out_panels}
    for bp in copy.deepcopy((base or {}).get("panels") or []):
        if bp["id"] in seen_panel_ids:
            continue
        # Fix missing male tag on male-only panels from v1 catalogue
        if bp["id"] in ("sex-hormones-male", "path-low-drive-men") and not bp.get("tag"):
            bp["tag"] = "male"
        # If baseline_recommended_panels replaced 'first' panels, demote legacy 'first' duplicates so order isn't doubled
        if bp_root and bp.get("when") == "first":
            continue
        out_panels.append(bp)
        seen_panel_ids.add(bp["id"])

    # Compile Patterns: preserve computable mini-patterns from base + add the 6 deep Pattern Engines
    out_patterns = [copy.deepcopy(p) for p in ((base or {}).get("patterns") or []) if not p.get("engine")]
    pattern_by_id = {p["id"]: p for p in out_patterns}

    ratio_slug_aliases = {
        "free_t3_to_rt3": "ft3-rt3",
        "cortisol_to_dhea_s": "cortisol-dhea-ratio",
        "nlr": "nlr",
        "mlr": "mlr",
        "tsat": "tsat",
        "mentzer_index": "mentzer",
        "homa_ir": "homa-ir",
        "tg_to_hdl": "tg-hdl",
        "ast_to_alt": "ast-alt",
        "non_hdl_cholesterol": "non-hdl",
    }

    for pat in patterns or []:
        pslug = pat["slug"]
        req_markers = [resolve_ref(x) for x in (pat.get("markers_required") or [])]
        cofactors = [resolve_ref(x) for x in (pat.get("cofactor_and_supporting_markers") or [])]

        compiled_ratios = []
        ratio_scales = {}
        for r in pat.get("calculated_ratios") or []:
            rid = r["ratio_id"]
            mapped = ratio_slug_aliases.get(rid, rid.replace("_to_", "-").replace("_", "-"))
            if mapped not in by_id:
                # Match by fuzzy ratio slug against base computed markers
                cand = rid.replace("_to_", "-")
                if cand in by_id:
                    mapped = cand
            base_m = by_id.get(mapped)
            expr = ((base_m or {}).get("formula") or {}).get("expr") or ""
            raw_thresh = r.get("thresholds") or []
            # D1: Detect 100x scale mismatch when base formula uses `* 100` while pattern numbers are < 1.0
            sample_vals = []
            for t in raw_thresh:
                lo, hi = _parse_threshold_bounds(t.get("condition"), 1.0)
                if lo is not None:
                    sample_vals.append(lo)
                if hi is not None:
                    sample_vals.append(hi)
            scale = 100.0 if ("* 100" in expr and sample_vals and max(sample_vals) <= 1.0) else 1.0
            ratio_scales[rid] = (mapped if mapped in by_id else rid, scale)

            thresh_out = []
            for t in raw_thresh:
                lo, hi = _parse_threshold_bounds(t.get("condition"), scale)
                thresh_out.append({
                    "band": t.get("band", ""),
                    "condition": t.get("condition", ""),
                    "min": lo,
                    "max": hi,
                    "meaning": t.get("meaning", ""),
                })
            compiled_ratios.append({
                "ratioID": rid,
                "markerID": mapped if mapped in by_id else None,
                "name": r.get("name", rid),
                "formula": r.get("formula", ""),
                "scaleFactor": scale,
                "thresholds": thresh_out,
            })

        def resolve_sig_target(raw_key):
            if raw_key in ratio_scales:
                return ratio_scales[raw_key]
            return resolve_ref(raw_key), 1.0

        diag = pat.get("diagnostic_logic") or {}
        prim = diag.get("primary_signature") or {}
        sig_conds = []
        for c in prim.get("conditions") or []:
            t_id, sc = resolve_sig_target(c.get("marker_or_ratio"))
            sig_conds.append({
                "target": t_id,
                "rawTarget": c.get("marker_or_ratio"),
                "state": c.get("state", ""),
                "scaleFactor": sc,
            })

        phenos = []
        for ph in diag.get("phenotypes_and_subtypes") or []:
            rules = []
            for tr in ph.get("trigger_rules") or []:
                t_id, sc = resolve_sig_target(tr.get("marker_or_ratio"))
                rules.append({
                    "target": t_id,
                    "condition": tr.get("condition", ""),
                    "scaleFactor": sc,
                })
            phenos.append({
                "name": ph.get("phenotype_name", ""),
                "rules": rules,
                "interpretation": ph.get("clinical_interpretation", ""),
            })

        s_inter = pat.get("stepped_interventions") or {}
        t3_p = [
            {
                "name": x.get("name", ""),
                "dose": x.get("dose") if x.get("dose") != "NOT_STATED" else None,
                "target": x.get("target_phenotype"),
                "notes": x.get("mechanism_and_notes"),
            }
            for x in (s_inter.get("tier_3_supplements") or [])
            if isinstance(x, dict)
        ]
        t4_p = []
        for x in s_inter.get("tier_4_peptides_educational") or []:
            if isinstance(x, dict):
                parts = [p for p in [x.get("compound"), x.get("mechanism_or_notes") or x.get("notes")] if p and p != "NOT_STATED"]
                t4_p.append(": ".join(parts))
            elif isinstance(x, str):
                t4_p.append(x)

        p_esc = pat.get("medical_escalation") or {}
        engine_obj = {
            "patternID": pat["pattern_id"],
            "slug": pslug,
            "section": pat.get("section", ""),
            "markersRequired": req_markers,
            "cofactorMarkers": cofactors,
            "nonBloodInputs": list(pat.get("non_blood_inputs") or []),
            "calculatedRatios": compiled_ratios,
            "primarySignature": {
                "operator": prim.get("operator", "AND"),
                "minMatches": prim.get("min_matches"),
                "conditions": sig_conds,
            },
            "phenotypes": phenos,
            "progressionStaging": [
                {
                    "stage": st.get("stage", ""),
                    "criteria": st.get("criteria", ""),
                    "timeline": st.get("expected_recovery_timeline"),
                }
                for st in (diag.get("progression_staging") or [])
            ],
            "differentialLookAlikes": [
                {"condition": lk.get("condition", ""), "howToRuleOut": lk.get("how_to_rule_out", "")}
                for lk in (diag.get("differential_look_alikes") or [])
            ],
            "upstreamCauses": [
                {"driver": uc.get("driver", ""), "mechanism": uc.get("mechanism", "")}
                for uc in (pat.get("upstream_root_causes") or [])
            ],
            "confoundingMedications": [
                {"medication": md.get("medication", ""), "effect": md.get("effect", "")}
                for md in (pat.get("medications_that_cause_or_confound") or [])
            ],
            "interventions": {
                "tier1Foundations": list(s_inter.get("tier_1_foundations") or []),
                "tier2Nutrition": list(s_inter.get("tier_2_nutrition") or []),
                "tier3Supplements": t3_p,
                "tier4Peptides": t4_p,
                "whatNotToDo": list(s_inter.get("what_not_to_do") or []),
            },
            "escalation": {
                "urgentSameDay": list(p_esc.get("urgent_same_day") or []),
                "routineSoon": list(p_esc.get("routine_referral_triggers") or p_esc.get("routine_soon") or []),
                "specialists": list(p_esc.get("specialists") or []),
            },
        }

        pat_entry = {
            "id": pslug,
            "name": pat["name"],
            "markers": req_markers,
            "computable": False,  # Evaluated by dedicated LabPatternEvaluator rather than flat LabCondition list
            "source": pat["pattern_id"],
            "engine": engine_obj,
        }
        if pslug in pattern_by_id:
            pattern_by_id[pslug].update(pat_entry)
        else:
            out_patterns.append(pat_entry)
            pattern_by_id[pslug] = pat_entry

    # Compile Global Protocols (Part 1, 3, 4)
    gp = global_protocols or {}
    gpa = gp.get("global_pre_analytic_rules") or {}
    exempt_names = (gpa.get("fasting") or {}).get("fasting_exempt_markers") or []
    exempt_ids = []
    for ename in exempt_names:
        el = ename.lower()
        for mid in ordered_ids:
            m = by_id[mid]
            names_low = [m["id"].lower(), m.get("name", "").lower()] + [a.lower() for a in (m.get("aliases") or [])]
            if el in names_low or any(el == n for n in names_low):
                if mid not in exempt_ids:
                    exempt_ids.append(mid)
    chk = gp.get("master_draw_day_checklist") or {}
    rf = gp.get("red_flag_emergency_thresholds") or {}
    comp = gp.get("composite_clinical_formulas") or {}

    compiled_global = {
        "fastingHours": (gpa.get("fasting") or {}).get("required_duration_hours"),
        "fastingAllowedIntake": (gpa.get("fasting") or {}).get("allowed_intake"),
        "fastingExemptMarkers": exempt_ids,
        "recommendedDrawWindow": (gpa.get("circadian_timing") or {}).get("recommended_draw_window"),
        "checklist": {
            "nightBefore": list(chk.get("night_before") or []),
            "morningOf": list(chk.get("morning_of") or []),
            "postDraw": list(chk.get("post_draw") or []),
            "loggingProtocol": list(chk.get("logging_protocol") or []),
        },
        "emergencySymptoms": list(rf.get("immediate_emergency_room_symptoms") or []),
        "bloodPressure": comp.get("blood_pressure_categories"),
        "cacAgatston": comp.get("cac_agatston_strata"),
    }

    pattern_id_to_slug = {pat["pattern_id"]: pat["slug"] for pat in (patterns or []) if pat.get("pattern_id") and pat.get("slug")}
    compiled_genes, compiled_guide = _compile_genetics(
        genetics_entries=genetics,
        base_genes=(base or {}).get("genes"),
        base_guide=(base or {}).get("geneticsGuide"),
        by_id=by_id,
        resolve_ref=resolve_ref,
        pattern_id_to_slug=pattern_id_to_slug,
    )

    return {
        "markers": [by_id[mid] for mid in ordered_ids],
        "panels": out_panels,
        "prep": copy.deepcopy((base or {}).get("prep") or []),
        "patterns": out_patterns,
        "genes": compiled_genes,
        "geneticsGuide": compiled_guide,
        "globalProtocols": compiled_global,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description="Compile clinical JSON rules into labs-catalogue.json")
    parser.add_argument("--base", required=True)
    parser.add_argument("--global-protocols", required=True)
    parser.add_argument("--baseline-panels", required=True)
    parser.add_argument("--markers", required=True)
    parser.add_argument("--patterns", required=True)
    parser.add_argument("--genetics", required=False)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    def load(p):
        with open(p, encoding="utf-8") as f:
            return json.load(f)

    compiled = compile_catalogue(
        base=load(args.base),
        global_protocols=load(args.global_protocols),
        baseline_panels=load(args.baseline_panels),
        markers=load(args.markers),
        patterns=load(args.patterns),
        genetics=load(args.genetics) if args.genetics else None,
    )
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(compiled, f, ensure_ascii=False, indent=1)

    print(json.dumps({
        "markers": len(compiled["markers"]),
        "panels": len(compiled["panels"]),
        "prep": len(compiled["prep"]),
        "patterns": len(compiled["patterns"]),
        "patternEngines": sum(1 for p in compiled["patterns"] if p.get("engine")),
        "genes": len(compiled["genes"]),
    }))
    return 0


if __name__ == "__main__":
    sys.exit(main())

