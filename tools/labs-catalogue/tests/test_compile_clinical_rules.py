import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from compile_clinical_rules import compile_catalogue  # noqa: E402


def _fixture_inputs():
    base = {
        "markers": [
            {
                "id": "alpha",
                "name": "Alpha",
                "lesson": "99.01.01",
                "units": [{"unit": "pg/mL", "default": True}],
                "bands": [
                    {"label": "Old opt A", "kind": "optimal", "low": 2.0, "high": 3.0, "unit": "pg/mL", "sex": "any"},
                    {"label": "Old opt B", "kind": "optimal", "low": 3.0, "high": 4.0, "unit": "pg/mL", "sex": "any"},
                ],
                "doctor": [{"op": ">", "value": 90, "unit": "pg/mL", "urgency": "sameDay", "text": "Base panic"}],
                "retest": [{"text": "8-12w", "minWeeks": 8, "maxWeeks": 12, "after": "abnormal"}],
            },
            {
                "id": "beta",
                "name": "Beta",
                "lesson": "99.01.02",
                "units": [{"unit": "ng/dL", "default": True}],
                "bands": [],
            },
            {
                "id": "alpha-beta",
                "name": "Alpha:Beta ratio",
                "lesson": "99.01.02",
                "computed": True,
                "units": [],
                "formula": {"expr": "{alpha} * 100 / {beta}", "inputs": {"alpha": "pg/mL", "beta": "ng/dL"}},
                "bands": [{"label": "Optimal", "kind": "optimal", "low": 20, "high": None}],
            },
            {
                "id": "age-hormone",
                "name": "Age Hormone",
                "lesson": "99.02.01",
                "units": [{"unit": "ug/dL", "default": True}],
                "bands": [
                    {"label": "20s", "kind": "lab", "low": 200, "high": 500, "unit": "ug/dL", "sex": "male", "condition": "age 20-29"},
                    {"label": "30s", "kind": "lab", "low": 150, "high": 400, "unit": "ug/dL", "sex": "male", "condition": "age 30-39"},
                    {"label": "40s", "kind": "lab", "low": 100, "high": 300, "unit": "ug/dL", "sex": "male", "condition": "age 40-49"},
                ],
            },
            {
                "id": "helper-only",
                "name": "Helper Only",
                "lesson": "99.00.01",
                "computed": True,
                "units": [{"unit": "ratio", "default": True}],
                "formula": {"expr": "{alpha} / {beta}", "inputs": {"alpha": "pg/mL", "beta": "ng/dL"}},
            },
        ],
        "panels": [],
        "prep": [{"id": "biotin-72h", "text": "Stop biotin", "hoursBefore": 72, "markers": ["alpha"]}],
        "patterns": [
            {
                "id": "mini-check",
                "name": "Mini check",
                "computable": True,
                "needed": "all",
                "conditions": [{"marker": "alpha", "op": "high", "sex": "any"}],
                "meaning": "Fixture mini pattern",
            }
        ],
        "genes": [{"id": "g1", "name": "GENE1", "bucket": "read", "genotypes": [{"genotype": "AA", "meaning": "ok"}]}],
        "geneticsGuide": [{"text": "Guide rule", "kind": "rule"}],
    }
    global_protocols = {
        "global_pre_analytic_rules": {
            "fasting": {"required_duration_hours": "10 to 12 hours", "fasting_exempt_markers": ["Beta"]},
            "circadian_timing": {"recommended_draw_window": "7:00 AM to 10:00 AM"},
        },
        "master_draw_day_checklist": {
            "night_before": ["Sleep normally"],
            "morning_of": ["Water only"],
            "post_draw": ["Eat snack"],
            "logging_protocol": ["Log time"],
        },
        "red_flag_emergency_thresholds": {
            "immediate_emergency_room_symptoms": ["Severe chest pressure"],
            "same_day_medical_care_thresholds": {},
            "urgent_medical_review_thresholds_within_a_few_days": {},
        },
        "composite_clinical_formulas": {
            "blood_pressure_categories": {
                "measurement_unit": "mmHg",
                "strata": {
                    "normal": "Systolic < 120 AND Diastolic < 80",
                    "elevated": "Systolic 120-129 AND Diastolic < 80",
                    "stage_1_hypertension": "Systolic 130-139 OR Diastolic 80-89",
                    "stage_2_hypertension": "Systolic >= 140 OR Diastolic >= 90",
                    "severe_hypertension": "Systolic >= 180 OR Diastolic >= 120",
                },
            },
            "cac_agatston_strata": {
                "scoring_metric": "AU",
                "strata": {"score_0": "None", "score_1_to_99": "Mild"},
            },
        },
    }
    baseline_panels = {
        "baseline_recommended_panels": {
            "core_all_adults": [{"marker_id": "99.01.01", "name": "Alpha", "category": "Core", "rationale": "Core marker"}],
            "male_specific": [{"marker_id": "99.02.01", "name": "Age Hormone", "draw_notes": "7-10 AM LC-MS/MS"}],
            "female_specific": [{"marker_id": "99.03.01", "name": "Cycle Hormone", "draw_notes": "Day 21 luteal"}],
            "tier_2_and_3_conditional_upgrades": [
                {"marker_id": "99.01.02", "name": "Beta", "when_to_order": "Order when tired"}
            ],
        }
    }
    markers = [
        {
            "marker_id": "99.00.99",
            "slug": "panel-overview",
            "name": "Panel Overview",
            "aliases": [],
            "section": "Vol 02 - 00 Overview",
            "units": {"primary": "NOT_STATED", "secondary": [], "conversion_formula": "NOT_STATED"},
            "reference_strata": [
                {
                    "population": "Adult All",
                    "standard_range": {"low": None, "high": None, "unit": "NOT_STATED"},
                    "functional_optimal": {"low": None, "high": 1.5, "sweet_spot": "leaked", "unit": "mg/dL"},
                    "bands": [],
                }
            ],
            "interpretation_logic": {"co_tests": [], "discordance_and_masking": []},
        },
        {
            "marker_id": "99.01.01",
            "slug": "alpha",
            "name": "Alpha",
            "aliases": ["Free Alpha"],
            "section": "Vol 02 - 01 Test",
            "specimen_and_assay": [{"matrix": "Serum", "preferred_assay": "LC-MS/MS", "target_population": "Adult All", "assay_pitfall": "Immunoassay cross-reacts"}],
            "units": {"primary": "pg/mL", "secondary": ["pmol/L"], "conversion_formula": "multiply pg/mL by 2.0 to get pmol/L"},
            "pre_analytic_protocol": {
                "fasting_required": True,
                "fasting_hours": "10 - 12 hours",
                "timing_window": "7:00 - 10:00 AM",
                "washout_restrictions": [{"item": "Biotin", "window": "72h", "effect": "Skews immunoassay"}],
                "redraw_triggers": ["Afternoon draw"],
            },
            "reference_strata": [
                {
                    "population": "Adult All",
                    "standard_range": {"low": 2.0, "high": 5.0, "unit": "pg/mL"},
                    "functional_optimal": {"low": 3.0, "high": 4.2, "sweet_spot": "3.2 - 4.0 pg/mL", "unit": "pg/mL"},
                    "bands": [
                        {"tier": "low", "min": None, "max": 2.0, "meaning": "Frankly low"},
                        {"tier": "suboptimal_low", "min": 2.0, "max": 3.0, "meaning": "Low-normal"},
                        {"tier": "optimal", "min": 3.0, "max": 4.2, "meaning": "Optimal"},
                        {"tier": "high", "min": 4.2, "max": None, "meaning": "Elevated"},
                    ],
                }
            ],
            "interpretation_logic": {"co_tests": ["99.01.02"], "discordance_and_masking": ["Alpha low + Beta high: conversion shunt"]},
            "interventions": {
                "tier_1_foundations": ["Sleep 8h"],
                "tier_2_nutrition": ["Eat enough carbs"],
                "tier_3_supplements": [{"name": "Selenium", "dose": "200 mcg", "target_direction": "low", "mechanism": "Deiodinase"}],
                "tier_4_peptides_educational": ["Educational peptide note"],
                "what_not_to_do": ["Never dose on an afternoon draw"],
            },
            "medical_escalation": {
                "urgent_same_day": ["Severe storm signs"],
                "routine_soon": ["Alpha < 1.5"],
                "specialists": ["Endocrinology"],
            },
        },
        {
            "marker_id": "99.01.02",
            "slug": "beta",
            "name": "Beta",
            "aliases": [],
            "section": "Vol 02 - 01 Test",
            "units": {"primary": "ng/dL", "secondary": ["mmol/mol"], "conversion_formula": "IFCC (mmol/mol) = (10.93 × NGSP [%]) - 23.5"},
            "reference_strata": [
                {
                    "population": "Adult Male",
                    "standard_range": {"low": 4.7, "high": 6.1, "unit": "ng/dL"},
                    "functional_optimal": {"low": None, "high": 5.8, "sweet_spot": "5.0 - 5.8", "unit": "ng/dL"},
                    "bands": [
                        {"tier": "low", "min": None, "max": 4.7, "meaning": "Low"},
                        {"tier": "optimal", "min": 5.0, "max": 5.8, "meaning": "Bounded optimal"},
                        {"tier": "high", "min": 5.8, "max": None, "meaning": "High"},
                    ],
                },
                {
                    "population": "Ratio Subtest - Adult All",
                    "standard_range": {"low": 0.8, "high": 1.2, "unit": "ratio"},
                    "functional_optimal": {"low": 1.0, "high": 1.0, "sweet_spot": "~1:1 (acceptable balance ~0.8 to 1.2)", "unit": "ratio"},
                    "bands": [{"tier": "optimal", "min": 0.8, "max": 1.2, "meaning": "Balanced"}],
                },
            ],
            "interpretation_logic": {"co_tests": [], "discordance_and_masking": []},
        },
        {
            "marker_id": "99.01.03",
            "slug": "glycated",
            "name": "Glycated",
            "aliases": [],
            "section": "Vol 02 - 01 Test",
            "units": {"primary": "%", "secondary": ["mmol/mol"], "conversion_formula": "IFCC (mmol/mol) = (10.93 × NGSP [%]) - 23.5"},
            "reference_strata": [],
            "interpretation_logic": {"co_tests": [], "discordance_and_masking": []},
        },
        {
            "marker_id": "99.02.01",
            "slug": "age-hormone",
            "name": "Age Hormone",
            "aliases": [],
            "section": "Vol 02 - 02 Hormones",
            "units": {"primary": "ug/dL", "secondary": [], "conversion_formula": "NOT_STATED"},
            "reference_strata": [
                {
                    "population": "Male",
                    "standard_range": {"low": 30, "high": 500, "unit": "ug/dL"},
                    "functional_optimal": {"low": None, "high": None, "sweet_spot": "Upper half of age range", "unit": "ug/dL"},
                    "bands": [],
                }
            ],
            "interpretation_logic": {"co_tests": [], "discordance_and_masking": []},
        },
        {
            "marker_id": "99.03.01",
            "slug": "cycle-hormone",
            "name": "Cycle Hormone",
            "aliases": [],
            "section": "Vol 02 - 03 Female",
            "units": {"primary": "pg/mL", "secondary": [], "conversion_formula": "NOT_STATED"},
            "reference_strata": [
                {
                    "population": "Postmenopausal females",
                    "standard_range": {"low": None, "high": 30, "unit": "pg/mL"},
                    "functional_optimal": {"low": 50, "high": 100, "sweet_spot": "50 - 100 pg/mL on HRT for symptom control", "unit": "pg/mL"},
                    "bands": [{"tier": "optimal", "min": None, "max": 30, "meaning": "Without HRT"}],
                }
            ],
            "interpretation_logic": {"co_tests": [], "discordance_and_masking": []},
        },
    ]
    patterns = [
        {
            "pattern_id": "99.14.01",
            "slug": "alpha-conversion",
            "name": "Alpha Conversion",
            "section": "Pattern Analysis",
            "markers_required": ["99.01.01", "99.01.02"],
            "cofactor_and_supporting_markers": ["99.02.01"],
            "non_blood_inputs": ["Dietary Caloric / Macronutrient Intake Log"],
            "calculated_ratios": [
                {
                    "ratio_id": "alpha_to_beta",
                    "name": "Alpha:Beta ratio",
                    "formula": "Alpha (in pg/mL) × 100 / Beta (in ng/dL)",
                    "thresholds": [
                        {"band": "optimal", "condition": "> 0.20", "meaning": "Optimal"},
                        {"band": "borderline", "condition": "0.15 - 0.20", "meaning": "Borderline"},
                        {"band": "impaired", "condition": "< 0.15", "meaning": "Impaired"},
                    ],
                }
            ],
            "diagnostic_logic": {
                "primary_signature": {
                    "operator": "AND",
                    "min_matches": None,
                    "conditions": [
                        {"marker_or_ratio": "99.01.01", "state": "Low or low-normal (< 3.0 pg/mL)"},
                        {"marker_or_ratio": "alpha_to_beta", "state": "Impaired (under 0.15)"},
                    ],
                },
                "phenotypes_and_subtypes": [
                    {
                        "phenotype_name": "Classic Impaired",
                        "trigger_rules": [{"marker_or_ratio": "alpha_to_beta", "condition": "< 0.15"}],
                        "clinical_interpretation": "Impaired shunt",
                    }
                ],
                "progression_staging": [{"stage": "Mild", "criteria": "1 driver", "expected_recovery_timeline": "90d"}],
                "differential_look_alikes": [{"condition": "Biotin artifact", "how_to_rule_out": "Hold 72h"}],
            },
            "stepped_interventions": {
                "tier_1_foundations": ["Sleep"],
                "tier_2_nutrition": ["Fuel"],
                "tier_3_supplements": [{"name": "Selenium", "dose": "200 mcg", "target_phenotype": "general", "mechanism_and_notes": "Cofactor"}],
                "tier_4_peptides_educational": [{"compound": "PeptideX", "notes": "Educational"}],
                "what_not_to_do": ["Do not crash diet"],
            },
            "medical_escalation": {
                "urgent_same_day": ["Storm"],
                "routine_referral_triggers": ["Persistent low"],
                "specialists": ["Endocrinology"],
            },
        }
    ]
    return base, global_protocols, baseline_panels, markers, patterns


def test_preserves_genes_helpers_and_resolves_lesson_ids_to_slugs():
    out = compile_catalogue(*_fixture_inputs())

    ids = {m["id"] for m in out["markers"]}
    assert {"alpha", "beta", "alpha-beta", "age-hormone", "helper-only", "cycle-hormone"}.issubset(ids)
    assert out["genes"][0]["id"] == "g1"
    alpha = next(m for m in out["markers"] if m["id"] == "alpha")
    assert alpha["lessonID"] == "99.01.01"
    assert alpha["coTests"] == ["beta"]
    assert alpha["interventions"]["whatNotToDo"] == ["Never dose on an afternoon draw"]
    assert alpha["escalation"]["specialists"] == ["Endocrinology"]


def test_excludes_panel_overviews_from_loggable_markers():
    out = compile_catalogue(*_fixture_inputs())

    overview = next(m for m in out["markers"] if m["id"] == "panel-overview")
    assert overview["isOverview"] is True
    assert overview["bands"] == []


def test_fixes_missing_lower_bound_zero_width_ratio_and_postmenopausal_hrt_split():
    out = compile_catalogue(*_fixture_inputs())

    beta = next(m for m in out["markers"] if m["id"] == "beta")
    male_stratum = next(s for s in beta["strata"] if "Male" in s["population"])
    assert male_stratum["optimalLow"] == 5.0
    assert male_stratum["optimalHigh"] == 5.8

    ratio_stratum = next(s for s in beta["strata"] if "Ratio" in s["population"])
    assert ratio_stratum["optimalLow"] == 0.8
    assert ratio_stratum["optimalHigh"] == 1.2

    cycle = next(m for m in out["markers"] if m["id"] == "cycle-hormone")
    pops = [s["population"] for s in cycle["strata"]]
    assert any("No HRT" in p for p in pops) and any("On HRT" in p for p in pops)


def test_preserves_base_age_brackets_and_normalizes_100x_ratio_scale():
    out = compile_catalogue(*_fixture_inputs())

    age_h = next(m for m in out["markers"] if m["id"] == "age-hormone")
    age_bands = [b for b in age_h["bands"] if b.get("condition", "").startswith("age")]
    assert len(age_bands) == 3

    engine = next(p["engine"] for p in out["patterns"] if p["id"] == "alpha-conversion")
    ratio = engine["calculatedRatios"][0]
    assert ratio["scaleFactor"] == 100.0
    impaired = next(t for t in ratio["thresholds"] if t["band"] == "impaired")
    assert impaired["max"] == 15.0


def test_parses_multiplicative_metric_and_affine_unit_conversions():
    out = compile_catalogue(*_fixture_inputs())

    alpha = next(m for m in out["markers"] if m["id"] == "alpha")
    pmol = next(u for u in alpha["units"] if u["unit"] == "pmol/L")
    ngdl = next(u for u in alpha["units"] if u["unit"] == "ng/dL")
    assert abs(pmol["toDefault"] - 0.5) < 1e-6
    assert abs(ngdl["toDefault"] - 10.0) < 1e-6

    glyc = next(m for m in out["markers"] if m["id"] == "glycated")
    ifcc = next(u for u in glyc["units"] if u["unit"] == "mmol/mol")
    assert abs(ifcc["toDefault"] - (1.0 / 10.93)) < 1e-5
    assert abs(ifcc["toDefaultOffset"] - (23.5 / 10.93)) < 1e-5


def test_builds_sex_tagged_baseline_panels_and_global_protocols():
    out = compile_catalogue(*_fixture_inputs())

    by_id = {p["id"]: p for p in out["panels"]}
    assert by_id["baseline-core"]["when"] == "first"
    assert by_id["baseline-male"]["tag"] == "male"
    assert by_id["baseline-female"]["tag"] == "female"
    assert by_id["baseline-upgrades"]["when"] == "upgrade"
    assert by_id["baseline-male"]["drawNotes"]["age-hormone"] == "7-10 AM LC-MS/MS"
    assert out["globalProtocols"]["fastingExemptMarkers"] == ["beta"]
