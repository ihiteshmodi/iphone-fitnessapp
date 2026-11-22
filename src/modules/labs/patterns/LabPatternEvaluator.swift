import Foundation

public struct LabNonBloodContext: Equatable {
    public let dailyCalories: Double?
    public let calorieMultiplier: Double?
    public let recentSets14d: Int
    public let hadDeload14d: Bool
    public let waistInches: Double?

    public var isInCalorieCut: Bool { (calorieMultiplier ?? 1.0) < 0.98 }

    public static func load(from db: Database, on drawDate: ISODate) throws -> LabNonBloodContext {
        let entryRow = try db.query("SELECT calories, multiplier FROM calorie_entries WHERE logged_on = ?", [.text(drawDate.string)]).first
        let defRow = try db.query("""
            SELECT calories, multiplier FROM calorie_defaults WHERE effective_from <= ? ORDER BY effective_from DESC LIMIT 1
            """, [.text(drawDate.string)]).first
        let kcal = entryRow?.double("calories") ?? defRow?.double("calories")
        let mult = entryRow?.double("multiplier") ?? defRow?.double("multiplier")

        let start14 = drawDate.adding(days: -14).string
        let setRows = try db.query("""
            SELECT sets_count, has_deload FROM (
                SELECT COUNT(*) AS sets_count, COALESCE(MAX(is_deload), 0) AS has_deload
                FROM set_logs WHERE performed_on >= ? AND performed_on <= ?
            )
            """, [.text(start14), .text(drawDate.string)])
        let sets14 = setRows.first?.int("sets_count") ?? 0
        let deload14 = (setRows.first?.int("has_deload") ?? 0) == 1

        let waist = try db.query("""
            SELECT inches FROM body_measurements
            WHERE LOWER(site) LIKE 'waist%' AND measured_on <= ?
            ORDER BY measured_on DESC, id DESC LIMIT 1
            """, [.text(drawDate.string)]).first?.optionalDouble("inches")

        return LabNonBloodContext(dailyCalories: kcal, calorieMultiplier: mult,
                                  recentSets14d: sets14, hadDeload14d: deload14, waistInches: waist)
    }
}

public struct LabPatternMatch: Equatable, Identifiable {
    public let id: String
    public let name: String
    public let drawDate: ISODate
    public let matchedPhenotypes: [LabPhenotype]
    public let stage: LabProgressionStage?
    public let lookAlikes: [LabLookAlike]
    public let contextNotes: [String]
    public let interventions: LabInterventions
    public let escalation: LabEscalation
}

public struct LabDiscordanceAlert: Equatable, Identifiable {
    public let id: String
    public let title: String
    public let detail: String
}

public enum LabPatternEvaluator {
    public static func evaluate(drawID: Int, draws: LabDrawService, catalogue: LabCatalogue,
                                preferences: LabPreferences, context: LabNonBloodContext? = nil) throws -> [LabPatternMatch] {
        let allResults = try draws.results(inDraw: drawID)
        let drawDraft = try draws.draws().first { $0.id == drawID }?.draft
        guard let drawDate = allResults.first?.date ?? drawDraft?.date else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: allResults.map { ($0.markerID, $0) })

        var out: [LabPatternMatch] = []
        for pattern in catalogue.patterns {
            guard let engine = pattern.engine else { continue }
            guard matchesPrimarySignature(engine.primarySignature, results: byID, catalogue: catalogue, preferences: preferences, draw: drawDraft) else {
                continue
            }
            let matchedPhenos = engine.phenotypes.filter { pheno in
                !pheno.rules.isEmpty && pheno.rules.allSatisfy { rule in
                    matchesConditionText(target: rule.target, text: rule.condition, scale: rule.scaleFactor,
                                         results: byID, catalogue: catalogue, preferences: preferences, draw: drawDraft)
                }
            }
            let stage = engine.progressionStaging.first
            let filteredInterventions = LabInterventions(
                tier1Foundations: engine.interventions.tier1Foundations,
                tier2Nutrition: engine.interventions.tier2Nutrition,
                tier3Supplements: engine.interventions.tier3Supplements,
                tier4Peptides: preferences.showDrugNotes ? engine.interventions.tier4Peptides : [],
                whatNotToDo: engine.interventions.whatNotToDo)

            let notes = buildContextNotes(nonBloodInputs: engine.nonBloodInputs, context: context)
            out.append(LabPatternMatch(id: engine.slug, name: pattern.name, drawDate: drawDate,
                                       matchedPhenotypes: matchedPhenos, stage: stage,
                                       lookAlikes: engine.differentialLookAlikes, contextNotes: notes,
                                       interventions: filteredInterventions, escalation: engine.escalation))
        }
        return out
    }

    public static func discordances(in results: [LabResult], catalogue: LabCatalogue, preferences: LabPreferences) -> [LabDiscordanceAlert] {
        let byID = Dictionary(uniqueKeysWithValues: results.map { ($0.markerID, $0) })
        func val(_ id: String) -> Double? {
            guard let r = byID[id] else { return nil }
            return r.defaultValue ?? r.value
        }

        var alerts: [LabDiscordanceAlert] = []
        if let ldl = val("ldl-c"), let apob = val("apob"), ldl <= 100, apob >= 90 {
            alerts.append(LabDiscordanceAlert(
                id: "discordance-apob-ldl",
                title: "ApoB and LDL-C disagree",
                detail: "LDL-C (\(LabInsightsRule.number(ldl)) mg/dL) looks normal, while ApoB (\(LabInsightsRule.number(apob)) mg/dL) shows elevated atherogenic particle count — guide risk by ApoB."))
        }
        if let cr = val("creatinine"), let cys = val("cystatin-c"), let crMarker = catalogue.marker("creatinine") {
            let crStatus = LabReader.read(result: byID["creatinine"]!, marker: crMarker, preferences: preferences).status
            if crStatus == .high && cys <= 0.85 {
                alerts.append(LabDiscordanceAlert(
                    id: "discordance-cr-cystatin-muscle",
                    title: "Elevated creatinine with optimal Cystatin C",
                    detail: "Creatinine (\(LabInsightsRule.number(cr))) is above optimal while Cystatin C (\(LabInsightsRule.number(cys)) mg/L) is clean — points to lean muscle mass or creatine intake rather than reduced kidney filtration."))
            } else if crStatus == .optimal && cys > 1.0 {
                alerts.append(LabDiscordanceAlert(
                    id: "discordance-cr-cystatin-masked",
                    title: "Normal creatinine masking elevated Cystatin C",
                    detail: "Cystatin C (\(LabInsightsRule.number(cys)) mg/L) signals reduced kidney filtration that serum creatinine missed."))
            }
        }
        if preferences.sex == .male, let tt = val("total-testosterone"), let shbg = val("shbg"), let ft = val("free-testosterone"),
           tt >= 400, shbg > 50, ft < 12 {
            alerts.append(LabDiscordanceAlert(
                id: "discordance-shbg-free-t",
                title: "High SHBG masking low Free Testosterone",
                detail: "Total Testosterone (\(LabInsightsRule.number(tt)) ng/dL) sits in range, but elevated SHBG (\(LabInsightsRule.number(shbg)) nmol/L) leaves bioavailable Free Testosterone low (\(LabInsightsRule.number(ft)) pg/mL)."))
        }
        if let a1c = val("hba1c"), a1c < 5.5,
           (val("fasting-insulin").map { $0 >= 8 } ?? false) || (val("homa-ir").map { $0 >= 1.5 } ?? false) {
            alerts.append(LabDiscordanceAlert(
                id: "discordance-a1c-insulin",
                title: "Normal HbA1c masking rising insulin resistance",
                detail: "HbA1c (\(LabInsightsRule.number(a1c))%) is still normal because elevated insulin is compensating — act on fasting insulin / HOMA-IR early."))
        }
        if let ferr = val("ferritin"), let tsat = val("tsat"), let crp = val("hs-crp"),
           ferr >= 70, tsat < 20, crp >= 1.5 {
            alerts.append(LabDiscordanceAlert(
                id: "discordance-ferritin-inflammation",
                title: "Inflammation inflating ferritin while iron saturation is low",
                detail: "hs-CRP (\(LabInsightsRule.number(crp)) mg/L) is elevating ferritin (\(LabInsightsRule.number(ferr)) ng/mL) as an acute-phase reactant while TSAT (\(LabInsightsRule.number(tsat))%) indicates iron deficiency."))
        }
        return alerts
    }

    // MARK: - Private Signature Matching

    private static func matchesPrimarySignature(_ sig: LabPrimarySignature, results: [String: LabResult],
                                                catalogue: LabCatalogue, preferences: LabPreferences, draw: LabDrawDraft?) -> Bool {
        guard !sig.conditions.isEmpty else { return false }
        let matched = sig.conditions.filter { cond in
            matchesConditionText(target: cond.target, text: cond.state, scale: cond.scaleFactor,
                                 results: results, catalogue: catalogue, preferences: preferences, draw: draw)
        }.count
        switch sig.operator.uppercased() {
        case "OR":
            return matched >= (sig.minMatches ?? 1)
        case "N_OF_M":
            return matched >= (sig.minMatches ?? 2)
        default:
            return matched == sig.conditions.count
        }
    }

    private static func matchesConditionText(target: String?, text: String, scale: Double, results: [String: LabResult],
                                             catalogue: LabCatalogue, preferences: LabPreferences, draw: LabDrawDraft?) -> Bool {
        guard let target, let res = results[target], let marker = catalogue.marker(target) else { return false }
        let val = res.defaultValue ?? res.value
        let reading = LabReader.read(result: res, marker: marker, preferences: preferences, draw: draw)
        let lowText = text.lowercased()

        // Explicit numeric comparisons first (< N, <= N, > N, >= N, A - B)
        if let (op, bound) = extractSingleComparison(from: text, scale: scale) {
            switch op {
            case "<": return val < bound
            case "<=": return val <= bound
            case ">": return val > bound
            case ">=": return val >= bound
            default: break
            }
        }
        if let (lo, hi) = extractRangeBounds(from: text, scale: scale), !lowText.contains("normal"), !lowText.contains("low"), !lowText.contains("elevated") {
            return val >= lo && val <= hi
        }

        // Semantic state keywords combined with LabReader reading
        if lowText.hasPrefix("normal") || lowText.contains("mid-range normal") {
            if reading.status == .optimal { return true }
            if let st = reading.activeStratum, let sLo = st.standardLow, let sHi = st.standardHigh {
                return val >= sLo && val <= sHi
            }
            let labBands = marker.visibleBands(for: preferences.sex).filter { $0.kind == "lab" }
            if let lb = labBands.first, let bLo = lb.low, let bHi = lb.high { return val >= bLo && val <= bHi }
            return reading.status == .optimal || reading.status == .disputed
        }
        if lowText.contains("impaired") || lowText.contains("low or low-normal") || lowText.hasPrefix("low") {
            if reading.status == .low { return true }
            if let (_, bound) = extractUnderBound(from: lowText, scale: scale) { return val < bound }
            return false
        }
        if lowText.contains("elevated") || lowText.contains("high-normal or elevated") || lowText.hasPrefix("high") {
            if reading.status == .high { return true }
            if let (_, bound) = extractAboveBound(from: lowText, scale: scale) { return val > bound }
            return false
        }
        return false
    }

    private static func extractSingleComparison(from text: String, scale: Double) -> (String, Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(<=|>=|<|>)\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let opRange = Range(match.range(at: 1), in: trimmed),
              let numRange = Range(match.range(at: 2), in: trimmed),
              let num = Double(trimmed[numRange]) else { return nil }
        return (String(trimmed[opRange]), num * scale)
    }

    private static func extractUnderBound(from text: String, scale: Double) -> (String, Double)? {
        let pattern = #"(?:under|<|<=|below)\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let num = Double(text[numRange]) else { return nil }
        return ("<", num * scale)
    }

    private static func extractAboveBound(from text: String, scale: Double) -> (String, Double)? {
        let pattern = #"(?:above|>|>=|over)\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numRange = Range(match.range(at: 1), in: text),
              let num = Double(text[numRange]) else { return nil }
        return (">", num * scale)
    }

    private static func extractRangeBounds(from text: String, scale: Double) -> (Double, Double)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let pattern = #"^([0-9]+(?:\.[0-9]+)?)\s*[-–]\s*([0-9]+(?:\.[0-9]+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let r1 = Range(match.range(at: 1), in: trimmed),
              let r2 = Range(match.range(at: 2), in: trimmed),
              let lo = Double(trimmed[r1]), let hi = Double(trimmed[r2]) else { return nil }
        return (lo * scale, hi * scale)
    }

    private static func buildContextNotes(nonBloodInputs: [String], context: LabNonBloodContext?) -> [String] {
        guard let context else { return [] }
        let joined = nonBloodInputs.joined(separator: " ").lowercased()
        var notes: [String] = []
        if joined.contains("caloric") || joined.contains("dietary") {
            if let kcal = context.dailyCalories {
                let phase = context.isInCalorieCut ? "in a calorie cut (×\(LabInsightsRule.number(context.calorieMultiplier ?? 1)))" : "at/above maintenance"
                notes.append("Diet log around draw: target \(LabInsightsRule.number(kcal)) kcal/day (\(phase)).")
            }
        }
        if joined.contains("training") || joined.contains("athletic") {
            if context.recentSets14d > 0 {
                let deloadText = context.hadDeload14d ? " (includes deload sets)" : ""
                notes.append("Training log: \(context.recentSets14d) working sets logged in the 14 days before draw\(deloadText).")
            }
        }
        if joined.contains("waist"), let waist = context.waistInches {
            notes.append("Latest logged waist measurement: \(LabInsightsRule.number(waist)) in.")
        }
        return notes
    }
}
