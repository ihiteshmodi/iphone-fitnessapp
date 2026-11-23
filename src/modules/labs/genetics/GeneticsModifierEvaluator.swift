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

        // 1a. FUT2 2x2 (Serum B12 x Intracellular MMA / Homocysteine)
        if let fut2 = active["fut2"], !fut2.row.isBaseline, let b12 = byMarker["b12"] {
            let mma = byMarker["mma"]
            let hcy = byMarker["homocysteine"]
            if (mma ?? 0) > 0.27 || (hcy ?? 0) >= 10.0 {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-fut2-masked-b12-deficiency",
                    geneID: "fut2", geneName: fut2.gene.name,
                    condition: "FUT2 (\(fut2.row.genotype)) + Serum B12 \(LabInsightsRule.number(b12)) pg/mL with elevated MMA/Homocysteine",
                    interpretation: "Masked intracellular B12 deficiency despite normal/elevated serum B12.",
                    action: "Ignore reassuring serum B12; replete methylcobalamin or hydroxocobalamin and recheck MMA + Homocysteine in 8–12 weeks.",
                    isUrgentSafetyStop: false))
            } else if b12 < 400, let mma, mma <= 0.27, (hcy == nil || hcy! < 8.0) {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-fut2-benign-low-b12",
                    geneID: "fut2", geneName: fut2.gene.name,
                    condition: "FUT2 (\(fut2.row.genotype)) + low Serum B12 (\(LabInsightsRule.number(b12))) with normal MMA & Homocysteine",
                    interpretation: "Lower haptocorrin-bound serum B12 transport pool while holotranscobalamin/tissue B12 remains sufficient.",
                    action: "Functional markers outrank serum B12; avoid unnecessary high-dose B12 injections.",
                    isUrgentSafetyStop: false))
            }
        }

        // 1b. Methylation 2x2 for MTHFR / MTR-MTRR (Homocysteine x MMA)
        let methCarrier = [active["mthfr"], active["mtr-mtrr"]].compactMap { $0 }.first { !$0.row.isBaseline }
        if let carrier = methCarrier, let hcy = byMarker["homocysteine"] {
            let mma = byMarker["mma"]
            if hcy >= 10.0, let mma, mma > 0.27 {
                matches.append(LabGeneticEpistaticMatch(
                    id: "epistatic-\(carrier.gene.id)-b12-bottleneck",
                    geneID: carrier.gene.id, geneName: carrier.gene.name,
                    condition: "High Homocysteine (\(LabInsightsRule.number(hcy))) + High MMA (\(LabInsightsRule.number(mma)))",
                    interpretation: "Functional intracellular B12 deficiency is the rate-limiting bottleneck (outranking MTHFR).",
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

    // MARK: - Active Diet, Supplement & Clinical Context Cross-Checks

    public struct DietSnapshot {
        public var totalNutrients: [Nutrient: Double] = [:]
        public var supplementNutrients: [Nutrient: Double] = [:]
        public var totalSatFatGrams: Double = 0
        public var items: [(food: Food, meal: String, quantity: Double, text: String)] = []

        public static func load(from db: Database, on today: ISODate) -> DietSnapshot {
            var snap = DietSnapshot()
            guard let plan = try? DietPlanService(db).plan(inForceOn: today),
                  let book = try? FoodLibrary(db).book() else { return snap }
            for item in plan.items {
                guard let food = book.food(item.foodID) else { continue }
                let text = "\(food.name) \(food.draft.notes ?? "")".lowercased()
                snap.items.append((food: food, meal: item.meal, quantity: item.quantity, text: text))
                if let nut = try? book.nutrition(of: item.foodID, quantity: item.quantity) {
                    snap.totalSatFatGrams += nut.satFat
                }
                if let prof = try? book.profile(of: item.foodID, quantity: item.quantity) {
                    for (k, v) in prof.values {
                        snap.totalNutrients[k, default: 0] += v
                        if food.draft.kind == .supplement || food.draft.kind == .herb {
                            snap.supplementNutrients[k, default: 0] += v
                        }
                    }
                }
            }
            return snap
        }

        public func hasSupplement(matching keywords: [String]) -> String? {
            for entry in items where entry.food.draft.kind == .supplement || entry.food.draft.kind == .herb {
                if keywords.contains(where: { entry.text.contains($0) }) { return entry.food.name }
            }
            return nil
        }

        public func hasAnyItem(matching keywords: [String], excluding: [String] = []) -> String? {
            for entry in items {
                if excluding.contains(where: { entry.text.contains($0) }) { continue }
                if keywords.contains(where: { entry.text.contains($0) }) { return entry.food.name }
            }
            return nil
        }

        public var hasLateDayCaffeine: Bool {
            let lateMeals = ["afternoon", "evening", "dinner", "night", "pm", "pre-workout", "post-workout"]
            return items.contains { entry in
                let mealLow = entry.meal.lowercased()
                guard lateMeals.contains(where: { mealLow.contains($0) }) else { return false }
                let caff = entry.food.draft.nutrients[.caffeine] ?? 0
                return caff > 0 || entry.text.contains("espresso") || entry.text.contains("coffee") || entry.text.contains("caffeine")
            }
        }
    }

    /// Evaluates active genetic insights across all 5 Volume 07 action categories.
    /// Fires ONLY for mandatory clinical referrals/stop-lines or real collisions with Diet, Bloodwork, or Profile Context.
    public static func evaluateInsights(on today: ISODate, db: Database, genotypes: [GenotypeEntry],
                                        preferences: LabPreferences, latestResults: [LabResult],
                                        latestDraw: LabDrawDraft?) -> [Insight] {
        guard !genotypes.isEmpty else { return [] }
        let diet = DietSnapshot.load(from: db, on: today)
        let byMarker = Dictionary(uniqueKeysWithValues: latestResults.map { ($0.markerID, $0.defaultValue ?? $0.value) })
        let drawDay = latestDraw?.date
        var out: [Insight] = []

        for entry in genotypes where !entry.row.isBaseline {
            let gid = entry.gene.id
            let gLow = entry.row.genotype.lowercased()
            let day = drawDay ?? entry.enteredOn
            let why = entry.gene.entryID.map { "Vault \($0)" } ?? (entry.gene.source.map { "Vault \($0)" } ?? "Vault genetics")

            // 1. Unconditional mandatory clinical referrals & hard contraindications:
            // ONLY Category 5 (`hard_contraindication`: F5/F2, G6PD, CYP2D6/2C19), APOE e4 / e2/e2, or HFE C282Y Homozygous.
            // Reference coach-scope boundaries on other genes stay quiet unless an active collision triggers below.
            if !entry.gene.hardContraindications.isEmpty,
               shouldEmitMandatoryContraAlert(gene: entry.gene, genotypeLower: gLow) {
                var bullets: [String] = []
                let referrals = Array(Set(entry.gene.hardContraindications.compactMap(\.mandatoryReferral))).sorted()
                if !referrals.isEmpty { bullets.append("Mandatory referral: \(referrals.joined(separator: "; "))") }
                let forbidden = Array(Set(entry.gene.hardContraindications.flatMap(\.forbiddenItems))).sorted()
                if !forbidden.isEmpty { bullets.append("Strictly avoid: \(forbidden.joined(separator: ", "))") }
                bullets += entry.gene.hardContraindications.map(\.coachStopLine).filter { !$0.isEmpty }

                // Active context / supplement collision amplifiers
                if gid == "f5-f2" && preferences.onTRTOrHRT {
                    let hctNote = byMarker["hematocrit"].map { $0 > 52 ? " Hematocrit is \(LabInsightsRule.number($0))% (> 52% stop-line)." : "" } ?? ""
                    bullets.insert("ACTIVE COLLISION: TRT/HRT is enabled in your profile with \(entry.gene.name).\(hctNote) Discuss thrombophilia & hematocrit monitoring with your prescriber immediately.", at: 0)
                }
                if gid == "g6pd" {
                    if let hit = diet.hasAnyItem(matching: ["methylene blue", "fava"]) {
                        bullets.insert("ACTIVE COLLISION: \(hit) is in your active diet/supplement plan — stop immediately (acute hemolysis risk).", at: 0)
                    } else if (diet.supplementNutrients[.vitaminC] ?? 0) > 1000 {
                        bullets.insert("ACTIVE COLLISION: High-dose Vitamin C supplement (> 1,000 mg/day) logged with G6PD deficiency.", at: 0)
                    }
                }
                if gid == "cyp2d6-cyp2c19" {
                    if let herb = diet.hasSupplement(matching: ["st. john", "st john", "goldenseal", "cbd"]) {
                        bullets.insert("ACTIVE COLLISION: \(herb) is logged in your plan alongside \(entry.gene.name) — St. John's Wort / CYP inhibitors induce phenoconversion.", at: 0)
                    }
                    if preferences.activeMedications.contains(.cpicPrescription) {
                        bullets.insert("ACTIVE CONTEXT: CPIC-sensitive prescription class is active in your profile — verify exact drug & dose with your prescriber/pharmacist.", at: 0)
                    }
                }

                out.append(Insight(
                    ruleID: "lab-gene-contra-\(gid)", kind: .labs, severity: .fix,
                    title: "Clinical safety rule: \(entry.gene.name) (\(entry.row.genotype))",
                    detail: LabInsightsRule.lines(entry.gene.coreThesis ?? "Hard genetic safety guardrail.", bullets),
                    why: why, day: day))
            }

            // 2. Category 1 — Nutrient Swaps (fire ONLY on active diet/supplement or biomarker collision)
            if entry.gene.actionCategory == .nutrientSwap {
                out += nutrientSwapInsights(entry: entry, diet: diet, byMarker: byMarker, preferences: preferences, day: day, why: why)
            }

            // 3. Category 2 — Marker Shifts (FUT2 missing MMA reminder, LCT dairy collision)
            if entry.gene.actionCategory == .markerShift {
                if gid == "fut2", byMarker["b12"] != nil, byMarker["mma"] == nil {
                    out.append(Insight(
                        ruleID: "lab-gene-shift-fut2", kind: .labs, severity: .improve,
                        title: "FUT2 non-secretor: pair Serum B12 with MMA",
                        detail: "Serum B12 was measured without Methylmalonic Acid (MMA). In FUT2 (\(entry.row.genotype)), serum B12 can look falsely normal — intracellular MMA + Homocysteine outrank serum B12.",
                        why: why, day: day))
                }
                if gid == "lct-mcm6", gLow.contains("cc"),
                   let dairy = diet.hasAnyItem(matching: ["whey concentrate", "milk", "ice cream", "ricotta", "cottage cheese"],
                                               excluding: ["lactose-free", "lactose free", "almond milk", "soy milk", "oat milk", "coconut milk", "milk thistle", "whey isolate"]) {
                    out.append(Insight(
                        ruleID: "lab-gene-diet-lct-mcm6", kind: .labs, severity: .improve,
                        title: "LCT/MCM6 lactase non-persistence: swap \(dairy)",
                        detail: "Your active diet plan includes \(dairy). Swap high-lactose dairy/whey concentrate for whey isolate, aged hard cheeses, Greek yogurt/kefir, or lactase enzyme while keeping calcium intake strong.",
                        why: why, day: day))
                }
            }

            // 4. Category 3 — Priority Shifts (CYP1A2/COMT caffeine, ALDH2 alcohol, APOE sat-fat)
            if entry.gene.actionCategory == .priorityShift {
                if gid == "cyp1a2" {
                    let caff = diet.totalNutrients[.caffeine] ?? 0
                    if caff > 200 || diet.hasLateDayCaffeine {
                        out.append(Insight(
                            ruleID: "lab-gene-diet-cyp1a2", kind: .labs, severity: .improve,
                            title: "CYP1A2 slow caffeine metabolizer: cap caffeine ≤ 200 mg morning-only",
                            detail: "Your active diet plan logs \(LabInsightsRule.number(caff)) mg/day caffeine\(diet.hasLateDayCaffeine ? " including afternoon/evening intake" : ""). Cap at ≤ 100–200 mg strictly within 1–2 hours of waking to protect sleep architecture and blood pressure.",
                            why: why, day: day))
                    }
                }
                if gid == "comt", gLow.contains("aa"),
                   let catechol = diet.hasSupplement(matching: ["egcg", "green tea extract", "quercetin"]) {
                    out.append(Insight(
                        ruleID: "lab-gene-diet-comt", kind: .labs, severity: .improve,
                        title: "COMT Met/Met: avoid catechol supplement (\(catechol))",
                        detail: "High-dose catechol flavonoids (EGCG, quercetin) further inhibit slow COMT clearance and can worsen sleep or anxiety.",
                        why: why, day: day))
                }
                if gid == "aldh2",
                   (preferences.drinksAlcoholRegularly || (diet.totalNutrients[.alcohol] ?? 0) > 0 || latestDraw?.alcohol5d == true) {
                    out.append(Insight(
                        ruleID: "lab-gene-diet-aldh2", kind: .labs, severity: .fix,
                        title: "ALDH2 deficiency: eliminate alcohol exposure",
                        detail: "Alcohol intake is active alongside ALDH2 (\(entry.row.genotype)), causing toxic acetaldehyde accumulation. Never use H2 blockers or antihistamines to mask facial flushing.",
                        why: why, day: day))
                }
                if gid == "apoe", gLow.contains("e4"), diet.totalSatFatGrams > 25 {
                    out.append(Insight(
                        ruleID: "lab-gene-diet-apoe", kind: .labs, severity: .improve,
                        title: "APOE e4 hyper-absorber: lower dietary saturated fat",
                        detail: "Your active diet plan provides \(LabInsightsRule.number(diet.totalSatFatGrams)) g saturated fat/day. APOE e4 carriers hyper-respond to saturated fat with sharper ApoB rises; favor olive oil, nuts, avocado, fatty fish, and soluble fiber.",
                        why: why, day: day))
                }
            }

            // 5. Category 4 — Change-Nothing Mandate (stay 100% silent UNLESS a forbidden genotype-chasing stack is logged!)
            if entry.gene.changeNothingMandate || entry.gene.actionCategory == .changeNothing {
                if let violation = changeNothingViolation(entry: entry, diet: diet, byMarker: byMarker, day: day, why: why) {
                    out.append(violation)
                }
            }
        }

        // Epistatic 2x2 matches that represent actionable bottlenecks or urgent stops
        for ep in evaluateEpistaticGrid(results: latestResults, genotypes: genotypes, preferences: preferences) {
            // Skip silent/reassuring 2x2 cells so Room-for-Improvement stays quiet when clean
            if ep.id.hasSuffix("-silent") || ep.id.hasSuffix("-unexpressed") || ep.id.hasSuffix("-benign-low-b12") { continue }
            out.append(Insight(
                ruleID: "lab-gene-\(ep.id)", kind: .labs, severity: ep.isUrgentSafetyStop ? .fix : .improve,
                title: "\(ep.geneName): \(ep.condition)",
                detail: "\(ep.interpretation) \(ep.action)",
                why: "Epistatic gene × bloodwork rule", day: drawDay ?? today))
        }

        return out
    }

    private static func shouldEmitMandatoryContraAlert(gene: LabGene, genotypeLower: String) -> Bool {
        if gene.actionCategory == .hardContraindication { return true }
        if gene.id == "apoe" { return genotypeLower.contains("e4") || genotypeLower.contains("e2/e2") }
        if gene.id == "hfe" { return genotypeLower.contains("c282y") && genotypeLower.contains("homozygous") }
        return false
    }

    private static func nutrientSwapInsights(entry: GenotypeEntry, diet: DietSnapshot, byMarker: [String: Double],
                                             preferences: LabPreferences, day: ISODate, why: String) -> [Insight] {
        let gid = entry.gene.id
        var items: [Insight] = []
        let swapLines = entry.gene.formSubstitutions.map { "Swap \($0.replaceOrAvoid) → \($0.useInstead)" }

        switch gid {
        case "mthfr", "mtr-mtrr":
            let badSupp = diet.hasSupplement(matching: ["folic acid", "cyanocobalamin"])
            let highHcy = (byMarker["homocysteine"] ?? 0) >= 10.0
            if let badSupp {
                items.append(Insight(
                    ruleID: "lab-gene-swap-\(gid)", kind: .labs, severity: .improve,
                    title: "\(entry.gene.name) form swap: replace \(badSupp)",
                    detail: LabInsightsRule.lines("Your active supplement plan includes \(badSupp).",
                                                  swapLines.isEmpty ? ["Use L-5-MTHF (methylfolate) + methylcobalamin/hydroxocobalamin + riboflavin."] : swapLines),
                    why: why, day: day))
            } else if highHcy {
                items.append(Insight(
                    ruleID: "lab-gene-swap-\(gid)", kind: .labs, severity: .improve,
                    title: "\(entry.gene.name) active homocysteine bottleneck",
                    detail: LabInsightsRule.lines("Homocysteine is elevated alongside \(entry.gene.name) (\(entry.row.genotype)).",
                                                  swapLines),
                    why: why, day: day))
            }

        case "hfe":
            let ironSuppName = diet.hasSupplement(matching: ["iron", "ferrous", "ferric", "heme"])
            let ironMg = diet.supplementNutrients[.iron] ?? 0
            let vitCMg = diet.supplementNutrients[.vitaminC] ?? 0
            if ironSuppName != nil || ironMg > 0 || vitCMg > 500 {
                let culprit = ironSuppName ?? (ironMg > 0 ? "supplemental iron (\(LabInsightsRule.number(ironMg)) mg)" : "high-dose Vitamin C (\(LabInsightsRule.number(vitCMg)) mg)")
                items.append(Insight(
                    ruleID: "lab-gene-swap-hfe", kind: .labs, severity: .fix,
                    title: "HFE safety rule: stop \(culprit)",
                    detail: LabInsightsRule.lines("Supplemental iron and > 500 mg Vitamin C accelerate iron absorption in HFE (\(entry.row.genotype)).",
                                                  swapLines.isEmpty ? ["Switch to iron-free formulas and monitor TSAT + Ferritin."] : swapLines),
                    why: why, day: day))
            }

        case "fads1-f2":
            let epaDha = (diet.totalNutrients[.epa] ?? 0) + (diet.totalNutrients[.dha] ?? 0)
            let plantOnly = ((diet.totalNutrients[.ala] ?? 0) > 0.5 || diet.hasAnyItem(matching: ["flax", "chia", "walnut", "hemp"]) != nil) && epaDha < 250
            let lowO3 = (byMarker["omega-3-index"] ?? 10) < 8.0
            if plantOnly || lowO3 {
                items.append(Insight(
                    ruleID: "lab-gene-swap-fads1-f2", kind: .labs, severity: .improve,
                    title: "FADS1/FADS2: use preformed EPA + DHA instead of plant ALA",
                    detail: LabInsightsRule.lines("Slow delta-5/delta-6 desaturase conversion limits ALA → EPA/DHA.", swapLines),
                    why: why, day: day))
            }

        case "bco1":
            if preferences.isSmoker, let beta = diet.hasSupplement(matching: ["beta-carotene", "beta carotene"]) {
                items.append(Insight(
                    ruleID: "lab-gene-swap-bco1", kind: .labs, severity: .fix,
                    title: "BCO1 + smoker safety rule: stop \(beta)",
                    detail: "High-dose isolated beta-carotene supplements are contraindicated in smokers (ATBC/CARET lung-risk stop-line).",
                    why: why, day: day))
            }

        case "pemt":
            if (diet.supplementNutrients[.choline] ?? 0) > 500 {
                items.append(Insight(
                    ruleID: "lab-gene-swap-pemt", kind: .labs, severity: .improve,
                    title: "PEMT: favor whole-food phosphatidylcholine over > 500 mg choline pills",
                    detail: LabInsightsRule.lines("High-dose free choline salts (> 500 mg) raise TMAO; prefer whole eggs, salmon, or sunflower lecithin.", swapLines),
                    why: why, day: day))
            }

        default:
            break
        }
        return items
    }

    private static func changeNothingViolation(entry: GenotypeEntry, diet: DietSnapshot, byMarker: [String: Double],
                                               day: ISODate, why: String) -> Insight? {
        switch entry.gene.id {
        case "gstm1-gstt1":
            if let detox = diet.hasSupplement(matching: ["nac", "n-acetylcysteine", "glutathione", "milk thistle", "sulforaphane", "detox"]) {
                return Insight(
                    ruleID: "lab-gene-guardrail-gstm1-gstt1", kind: .labs, severity: .improve,
                    title: "Change-Nothing Mandate (GSTM1/GSTT1): review \(detox)",
                    detail: "GSTM1/GSTT1 null deletions are normal population variants (up to 50%) and do not justify 'detox' supplement stacks. Dose interventions strictly by liver enzymes (GGT, ALT, AST) and bilirubin.",
                    why: why, day: day)
            }
        case "sod2":
            if (diet.supplementNutrients[.manganese] ?? 0) > 2.3 || diet.hasSupplement(matching: ["manganese", "superoxide dismutase", "sod "]) != nil {
                return Insight(
                    ruleID: "lab-gene-guardrail-sod2", kind: .labs, severity: .improve,
                    title: "Change-Nothing Mandate (SOD2): avoid manganese / SOD stacks",
                    detail: "SOD2 rs4880 is an informational variant; high-dose antioxidant or manganese supplements can blunt exercise mitohormesis.",
                    why: why, day: day)
            }
        case "vdr":
            let suppVitDMcg = (diet.supplementNutrients[.vitaminD] ?? 0)
                + (diet.supplementNutrients[.vitaminD3] ?? 0) / NutrientProfile.vitaminDIUPerMcg
            if suppVitDMcg > 125 && (byMarker["vitamin-d"] ?? 50) >= 40 {
                return Insight(
                    ruleID: "lab-gene-guardrail-vdr", kind: .labs, severity: .improve,
                    title: "Change-Nothing Mandate (VDR): dose Vitamin D by serum 25(OH)D, not VDR SNP",
                    detail: "High-dose Vitamin D (> 5,000 IU / 125 mcg) is logged without low serum 25(OH)D. Dose strictly to serum 25(OH)D + PTH + Calcium.",
                    why: why, day: day)
            }
        case "lpa-gene":
            if let niacin = diet.hasSupplement(matching: ["niacin", "nicotinic acid"]) {
                return Insight(
                    ruleID: "lab-gene-guardrail-lpa-gene", kind: .labs, severity: .improve,
                    title: "Change-Nothing Mandate (LPA): stop \(niacin) for Lp(a)",
                    detail: "High-dose niacin has zero cardiovascular outcome benefit for Lp(a) and carries hepatotoxicity/glycemia risk; measure serum Lp(a) in nmol/L and target ApoB.",
                    why: why, day: day)
            }
        default:
            break
        }
        return nil
    }
}
