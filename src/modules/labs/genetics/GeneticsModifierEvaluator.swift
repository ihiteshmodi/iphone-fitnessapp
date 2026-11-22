import Foundation

public struct LabGeneticEpistaticMatch: Equatable, Identifiable {
    public let id: String
    public let geneID: String
    public let geneName: String
    public let condition: String
    public let interpretation: String
    public let action: String
    public let isUrgentSafetyStop: Bool
}

public enum GeneticsModifierEvaluator {
    /// Applies active genotype marker shifts and tightened thresholds to a base `LabReading`.
    public static func applyReadingModifiers(base: LabReading, marker: LabMarker, preferences: LabPreferences,
                                             genotypes: [GenotypeEntry]) -> LabReading {
        guard !genotypes.isEmpty, let value = base.value else { return base }
        let active = Dictionary(uniqueKeysWithValues: genotypes.map { ($0.gene.id, $0) })

        var status = base.status
        var tier = base.tier
        var tierLabel = base.tierLabel
        var doctorLines = base.doctorLines
        var notes = base.geneticNotes

        // 07.02.01 FUT2 non-secretor: serum B12 loses its vote; MMA + Homocysteine outrank it.
        if marker.id == "b12", let fut2 = active["fut2"], !fut2.row.isBaseline {
            notes.append("FUT2 non-secretor (\(fut2.row.genotype)): serum B12 can look falsely reassuring — verify cellular status with MMA and Homocysteine.")
        }

        // 07.03.01 APOE e4: tighten ApoB target to <= 60 mg/dL (approved G3).
        if marker.id == "apob", let apoe = active["apoe"], apoe.row.genotype.lowercased().contains("e4") {
            if value > 60.0 {
                if status == .optimal || status == .disputed {
                    status = .high
                    tier = .watchHigh
                    tierLabel = "Above APOE e4 target (≤ 60 mg/dL)"
                }
                notes.append("APOE (\(apoe.row.genotype)) priority shift: ApoB target tightened to ≤ 60 mg/dL (standard optimal ≤ 80 mg/dL).")
            } else {
                notes.append("APOE (\(apoe.row.genotype)): meets tightened ApoB target (≤ 60 mg/dL).")
            }
        }

        // 07.01.01 & 07.01.02 MTHFR / MTR-MTRR: Homocysteine < 7 umol/L & RBC Folate > 800 ng/mL.
        let mthfrEntry = active["mthfr"].flatMap { $0.row.isBaseline ? nil : $0 }
            ?? active["mtr-mtrr"].flatMap { $0.row.isBaseline ? nil : $0 }
        if let meth = mthfrEntry {
            if marker.id == "homocysteine" {
                if value < 7.0 {
                    notes.append("\(meth.gene.name) (\(meth.row.genotype)): Homocysteine < 7 µmol/L confirms the variant is phenotypically silent — nothing to fix.")
                } else if value <= 8.0 && status == .optimal {
                    status = .high
                    tier = .watchHigh
                    tierLabel = "Above methylation-carrier target (< 7 µmol/L)"
                    notes.append("\(meth.gene.name) (\(meth.row.genotype)) target shift: Homocysteine optimal tightened to < 7 µmol/L.")
                }
            } else if marker.id == "rbc-folate", value <= 800.0 {
                if status == .optimal {
                    status = .low
                    tier = .watchLow
                    tierLabel = "Below MTHFR RBC folate target (> 800 ng/mL)"
                }
                notes.append("\(meth.gene.name) (\(meth.row.genotype)) target shift: RBC folate target > 800 ng/mL.")
            }
        }

        // 07.01.06 HFE: TSAT > 45% flags active iron loading.
        if marker.id == "tsat", let hfe = active["hfe"], !hfe.row.isBaseline, value > 45.0 {
            if status == .optimal { status = .high; tier = .high }
            notes.append("HFE (\(hfe.row.genotype)): Transferrin Saturation > 45% flags active iron loading — stop all supplemental iron and mealtime high-dose Vitamin C.")
        }

        // 07.05.01 Factor V Leiden / Prothrombin + active TRT/HRT + Hematocrit > 52% -> urgent prescriber referral.
        if marker.id == "hematocrit", let f5 = active["f5-f2"], !f5.row.isBaseline, preferences.onTRTOrHRT, value > 52.0 {
            let stopLine = LabDoctorLine(
                op: ">", value: 52.0, unit: "%", sex: .any, urgency: .urgent,
                text: "\(f5.gene.name) carrier on TRT/HRT with Hematocrit > 52%: immediate prescribing physician / hematologist referral for thrombotic risk management.",
                source: "07.05.01", requires: nil, tag: nil, origin: .vault)
            doctorLines = ([stopLine] + doctorLines).sorted { $0.urgency < $1.urgency }
            notes.append("Clotting variant + active TRT/HRT: Hematocrit trigger lowered to > 52% — refer to prescriber immediately.")
        }

        return LabReading(value: base.value, unit: base.unit, status: status, tier: tier, tierLabel: tierLabel,
                          activeStratum: base.activeStratum, bands: base.bands, optimalBands: base.optimalBands,
                          disputes: base.disputes, edgeLabels: base.edgeLabels, doctorLines: doctorLines,
                          conditionalDoctorLines: base.conditionalDoctorLines, geneticNotes: notes)
    }

    /// Evaluates same-draw epistatic 2x2 combinations between saved genotypes, blood markers, and profile context.
    public static func evaluateEpistaticGrid(results: [LabResult], genotypes: [GenotypeEntry],
                                             preferences: LabPreferences) -> [LabGeneticEpistaticMatch] {
        guard !genotypes.isEmpty else { return [] }
        let byMarker = Dictionary(uniqueKeysWithValues: results.map { ($0.markerID, $0.defaultValue ?? $0.value) })
        let active = Dictionary(uniqueKeysWithValues: genotypes.map { ($0.gene.id, $0) })
        var matches: [LabGeneticEpistaticMatch] = []

        // 1. Methylation & FUT2 / MTR-MTRR / MTHFR 2x2 (Homocysteine x MMA)
        let methCarrier = [active["fut2"], active["mthfr"], active["mtr-mtrr"]].compactMap { $0 }.first { !$0.row.isBaseline }
        if let carrier = methCarrier, let hcy = byMarker["homocysteine"] {
            let mma = byMarker["mma"]
            if hcy >= 10.0, let mma, mma > 0.27 {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-\(carrier.gene.id)-b12-bottleneck",
                    geneID: carrier.gene.id, geneName: carrier.gene.name,
                    condition: "High Homocysteine (\(LabInsightsRule.number(hcy))) + High MMA (\(LabInsightsRule.number(mma)))",
                    interpretation: "Functional intracellular B12 deficiency is the rate-limiting bottleneck (outranking serum B12 and MTHFR).",
                    action: "Replete methylcobalamin or hydroxocobalamin (500–1,000 mcg/day) and recheck Homocysteine + MMA in 8–12 weeks.",
                    isUrgentSafetyStop: false))
            } else if hcy >= 10.0, (mma == nil || mma! <= 0.27) {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-\(carrier.gene.id)-folate-bottleneck",
                    geneID: carrier.gene.id, geneName: carrier.gene.name,
                    condition: "Elevated Homocysteine (\(LabInsightsRule.number(hcy))) with clean/unflagged MMA",
                    interpretation: "Active folate/remethylation bottleneck.",
                    action: "Swap synthetic folic acid for L-5-MTHF (400–1,000 mcg/day) paired with B12 + riboflavin; recheck in 8–12 weeks.",
                    isUrgentSafetyStop: false))
            } else if hcy < 7.0, (mma == nil || mma! <= 0.27) {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-\(carrier.gene.id)-silent",
                    geneID: carrier.gene.id, geneName: carrier.gene.name,
                    condition: "\(carrier.gene.name) (\(carrier.row.genotype)) + clean Homocysteine (< 7 µmol/L)",
                    interpretation: "Phenotype outranks genotype: pathway is functionally clean and variant is silent.",
                    action: "Take zero supplement action; do not build a methylation stack for an unexpressed genotype.",
                    isUrgentSafetyStop: false))
            }
        }

        // 2. HFE 2x2 (C282Y x TSAT x Ferritin x hs-CRP)
        if let hfe = active["hfe"], !hfe.row.isBaseline, let tsat = byMarker["tsat"], let ferr = byMarker["ferritin"] {
            let ferrHigh = preferences.sex == .female ? ferr > 150 : ferr > 200
            if tsat > 45.0 && ferrHigh {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-hfe-active-loading",
                    geneID: "hfe", geneName: hfe.gene.name,
                    condition: "\(hfe.row.genotype) + TSAT \(LabInsightsRule.number(tsat))% + Ferritin \(LabInsightsRule.number(ferr)) ng/mL",
                    interpretation: "Confirmed active phenotypic iron loading.",
                    action: "Stop all iron supplements & mealtime high-dose Vitamin C, cut alcohol, and refer to physician/hematologist for phlebotomy evaluation.",
                    isUrgentSafetyStop: true))
            } else if tsat <= 45.0 && !ferrHigh {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-hfe-unexpressed",
                    geneID: "hfe", geneName: hfe.gene.name,
                    condition: "\(hfe.row.genotype) + normal TSAT (\(LabInsightsRule.number(tsat))%) & Ferritin (\(LabInsightsRule.number(ferr)) ng/mL)",
                    interpretation: "Unexpressed HFE genotype (~14% penetrance) — no active tissue iron loading.",
                    action: "No phlebotomy or red-meat elimination needed; avoid supplemental iron and recheck iron panel once a year.",
                    isUrgentSafetyStop: false))
            }
        }

        // 3. APOE e4 discordance & e2/e2 remnant dyslipidemia
        if let apoe = active["apoe"], !apoe.row.isBaseline {
            let gLow = apoe.row.genotype.lowercased()
            if gLow.contains("e4"), let ldl = byMarker["ldl-c"], let apob = byMarker["apob"], ldl <= 100, apob > 60 {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-apoe4-apob-discordance",
                    geneID: "apoe", geneName: apoe.gene.name,
                    condition: "APOE \(apoe.row.genotype) + normal LDL-C (\(LabInsightsRule.number(ldl))) + ApoB \(LabInsightsRule.number(apob)) mg/dL",
                    interpretation: "Delayed hepatic remnant clearance leaves atherogenic ApoB above the ≤ 60 mg/dL APOE e4 target.",
                    action: "Guide lipid management strictly by ApoB, blood pressure, insulin sensitivity, sleep, and exercise.",
                    isUrgentSafetyStop: false))
            } else if gLow.contains("e2/e2"), let tg = byMarker["triglycerides"], tg >= 150 {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-apoe2-remnants",
                    geneID: "apoe", geneName: apoe.gene.name,
                    condition: "APOE e2/e2 + elevated Triglycerides (\(LabInsightsRule.number(tg)) mg/dL)",
                    interpretation: "Impaired APOE e2/e2 remnant particle clearance.",
                    action: "Refer to a physician to evaluate remnant dyslipidemia rather than relying on stricter dieting alone.",
                    isUrgentSafetyStop: true))
            }
        }

        // 4. TCF7L2 normal fasting glucose + creeping HbA1c
        if let tcf = active["tcf7l2"], !tcf.row.isBaseline,
           let fg = byMarker["glucose"], let a1c = byMarker["hba1c"], fg < 100, a1c >= 5.5 {
            matches.append(LabGeneticEpistaticMatch(
                id: "epistatic-tcf7l2-postprandial",
                geneID: "tcf7l2", geneName: tcf.gene.name,
                condition: "TCF7L2 \(tcf.row.genotype) + normal Fasting Glucose (\(LabInsightsRule.number(fg))) + HbA1c \(LabInsightsRule.number(a1c))%",
                interpretation: "Beta-cell insulin-release lag: morning fasting glucose misses post-meal glycemic excursions captured by HbA1c.",
                action: "Check 2-hour post-meal glucose or OGTT/CGM; eat protein and fiber first at meals.",
                isUrgentSafetyStop: false))
        }

        // 5. Factor V Leiden / Prothrombin + Active TRT/HRT + Hematocrit > 52%
        if let f5 = active["f5-f2"], !f5.row.isBaseline, preferences.onTRTOrHRT,
           let hct = byMarker["hematocrit"], hct > 52.0 {
            matches.append(LabGeneticEpistaticMatch(
                id: "epistatic-f5-trt-hematocrit",
                geneID: "f5-f2", geneName: f5.gene.name,
                condition: "\(f5.gene.name) (\(f5.row.genotype)) on TRT/HRT + Hematocrit \(LabInsightsRule.number(hct))% (> 52%)",
                interpretation: "Synergistic thrombotic hazard from inherited activated protein C / prothrombin risk stacked with TRT erythrocytosis.",
                action: "Immediate medical stop-line: refer back to prescribing physician now for hematocrit & thrombophilia management.",
                isUrgentSafetyStop: true))
        }

        return matches
    }
}
