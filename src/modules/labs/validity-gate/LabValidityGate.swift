import Foundation

public enum LabValidityKind: String, Equatable {
    case circadianTiming
    case fasting
    case biotinInterference
    case trainingWashout
    case alcoholWashout
    case ironSupplement
    case illnessOrVaccine
    case sleepOrStress
    case assayPitfall
    case urineDilutionMasking
    case urineConcentrationArtifact
    case urineContamination
}

public struct LabValidityWarning: Equatable {
    public let kind: LabValidityKind
    public let title: String
    public let detail: String
    public let recommendsRedraw: Bool

    public init(kind: LabValidityKind, title: String, detail: String, recommendsRedraw: Bool = false) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.recommendsRedraw = recommendsRedraw
    }
}

public enum LabValidityGate {
    private static let morningHormones: Set<String> = [
        "total-testosterone", "free-testosterone", "cortisol", "acth", "tsh", "lh", "fsh", "prolactin", "cortisol-dhea-ratio",
    ]
    private static let fastingSensitive: Set<String> = [
        "glucose", "fasting-insulin", "triglycerides", "homa-ir", "tg-hdl", "total-testosterone", "free-testosterone",
        "cortisol", "serum-iron", "tsat",
    ]
    private static let biotinImmunoassayTargets: Set<String> = [
        "tsh", "free-t4", "free-t3", "total-testosterone", "estradiol", "cortisol", "pth", "hs-troponin", "vitamin-d",
    ]
    private static let trainingConfounded: Set<String> = [
        "ck", "ast", "alt", "hs-crp", "creatinine", "egfr", "ferritin", "total-testosterone", "free-testosterone",
        "free-t3", "reverse-t3", "ft3-rt3", "wbc",
    ]
    private static let alcoholConfounded: Set<String> = [
        "total-testosterone", "free-testosterone", "ferritin", "triglycerides", "ggt", "ast", "alt", "cortisol",
    ]
    private static let ironConfounded: Set<String> = ["ferritin", "serum-iron", "tsat", "tibc"]
    private static let illnessConfounded: Set<String> = [
        "hs-crp", "esr", "ferritin", "wbc", "neutrophils", "lymphocytes", "monocytes", "platelets",
        "free-t3", "reverse-t3", "ft3-rt3", "albumin", "tpo-antibodies", "tg-antibodies",
    ]
    private static let sleepStressConfounded: Set<String> = [
        "cortisol", "acth", "total-testosterone", "free-testosterone", "glucose", "fasting-insulin", "reverse-t3", "prolactin",
    ]

    public static func evaluate(result: LabResult, marker: LabMarker, draw: LabDrawDraft,
                                sameDrawResults: [LabResult] = [], catalogue: LabCatalogue, sex: LabSex) -> [LabValidityWarning] {
        var warnings: [LabValidityWarning] = []
        let id = marker.id
        let pa = marker.preAnalytic

        if let timeText = draw.time, let (hour, minute) = parseHourMinute(timeText), needsMorningWindow(id: id, preAnalytic: pa) {
            if hour > 10 || (hour == 10 && minute > 30) || hour < 5 {
                let window = pa?.timingWindow ?? catalogue.globalProtocols?.recommendedDrawWindow ?? "7:00–10:00 AM"
                warnings.append(LabValidityWarning(
                    kind: .circadianTiming,
                    title: "Drawn outside morning window (\(timeText))",
                    detail: "Expected \(window). Late-day draws lower testosterone and shift cortisol/TSH — confirm on a morning redraw before acting.",
                    recommendsRedraw: true))
            }
        }

        let exempt = Set(catalogue.globalProtocols?.fastingExemptMarkers ?? [])
        let requiresFast = !exempt.contains(id) && (pa?.fastingRequired == true || (pa == nil && fastingSensitive.contains(id)))
        if requiresFast, let fasted = draw.fastedHours, fasted < 8 {
            warnings.append(LabValidityWarning(
                kind: .fasting,
                title: "Drawn after only \(LabInsightsRule.number(fasted)) h fasted",
                detail: "Recommended 10–12 h water-only fast. Food raises glucose, insulin, and triglycerides and lowers morning testosterone.",
                recommendsRedraw: true))
        }

        let assayLower = result.assay?.lowercased() ?? ""
        let isMassSpecOrDialysis = assayLower.contains("lc-ms") || assayLower.contains("dialysis")
        if draw.biotinStopped == false, !isMassSpecOrDialysis,
           biotinImmunoassayTargets.contains(id) || hasWashoutKeyword(pa, "biotin") {
            warnings.append(LabValidityWarning(
                kind: .biotinInterference,
                title: "Biotin was not paused 72 h beforehand",
                detail: "Biotin interferes with streptavidin-biotin immunoassays (can falsely lower TSH and falsely raise Free T4/T3 or hormones).",
                recommendsRedraw: true))
        }

        if draw.trainedHard72h == true, trainingConfounded.contains(id) || hasWashoutKeyword(pa, "training") || hasWashoutKeyword(pa, "exercise") {
            warnings.append(LabValidityWarning(
                kind: .trainingWashout,
                title: "Hard training within 72 hours of draw",
                detail: "Intense training transiently raises CK, AST, ALT, hs-CRP, ferritin, and creatinine, and lowers testosterone/Free T3.",
                recommendsRedraw: false))
        }

        if draw.alcohol5d == true, alcoholConfounded.contains(id) || hasWashoutKeyword(pa, "alcohol") {
            warnings.append(LabValidityWarning(
                kind: .alcoholWashout,
                title: "Alcohol within 5 days of draw",
                detail: "Recent alcohol elevates triglycerides, GGT, transaminases, and ferritin and blunts morning testosterone.",
                recommendsRedraw: false))
        }

        if draw.ironStopped == false, ironConfounded.contains(id) {
            warnings.append(LabValidityWarning(
                kind: .ironSupplement,
                title: "Iron supplement not paused 3–5 days before draw",
                detail: "Recent oral iron transiently inflates serum iron, transferrin saturation, and ferritin.",
                recommendsRedraw: true))
        }

        if draw.illRecently == true || draw.recentVaccineOrSurgery == true,
           illnessConfounded.contains(id) || hasWashoutKeyword(pa, "illness") || hasWashoutKeyword(pa, "infection") {
            warnings.append(LabValidityWarning(
                kind: .illnessOrVaccine,
                title: "Recent illness, vaccination, or injury",
                detail: "Acute-phase inflammation elevates hs-CRP and ferritin for 2–4 weeks and suppresses T4-to-T3 conversion.",
                recommendsRedraw: true))
        }

        if draw.poorSleep == true || draw.acuteStress == true,
           sleepStressConfounded.contains(id) || hasWashoutKeyword(pa, "stress") || hasWashoutKeyword(pa, "sleep") {
            warnings.append(LabValidityWarning(
                kind: .sleepOrStress,
                title: "Poor sleep or acute stress before draw",
                detail: "A single poor night or acute stressor shifts morning cortisol, blood sugar, and lowers morning testosterone 10–15%.",
                recommendsRedraw: false))
        }

        if assayLower == "immunoassay", let pitfall = preferredMassSpecPitfall(marker: marker, sex: sex) {
            warnings.append(LabValidityWarning(
                kind: .assayPitfall,
                title: "Standard immunoassay used where sensitive assay is preferred",
                detail: pitfall,
                recommendsRedraw: true))
        }

        if id.hasPrefix("urine-"), id != "urine-specific-gravity" {
            warnings += evaluateUrineValidity(result: result, markerID: id, sameDrawResults: sameDrawResults)
        }
        return warnings
    }

    private static func evaluateUrineValidity(result: LabResult, markerID: String, sameDrawResults: [LabResult]) -> [LabValidityWarning] {
        var out: [LabValidityWarning] = []
        if let sgResult = sameDrawResults.first(where: { $0.markerID == "urine-specific-gravity" }) {
            let sg = sgResult.defaultValue ?? sgResult.value
            if sg > 0, sg < 1.005 {
                out.append(LabValidityWarning(
                    kind: .urineDilutionMasking,
                    title: "Dilute urine sample (SG \(LabInsightsRule.number(sg)))",
                    detail: "Specific gravity below 1.005 dilutes trace protein, glucose, ketones, and nitrites below dipstick thresholds.",
                    recommendsRedraw: false))
            } else if sg > 1.030, markerID == "urine-protein" {
                let textLow = result.textValue?.lowercased() ?? ""
                if textLow.contains("trace") || textLow.contains("1+") || result.value > 0 {
                    out.append(LabValidityWarning(
                        kind: .urineConcentrationArtifact,
                        title: "Concentrated urine sample (SG \(LabInsightsRule.number(sg)))",
                        detail: "Specific gravity above 1.030 can cause false-positive trace protein readings in normal glomeruli.",
                        recommendsRedraw: false))
                }
            }
        }
        if markerID != "urine-squamous-cells", markerID != "urine-epithelial-cells",
           let sq = sameDrawResults.first(where: { $0.markerID == "urine-squamous-cells" || $0.markerID == "urine-epithelial-cells" }) {
            let sqVal = sq.defaultValue ?? sq.value
            let sqText = sq.textValue?.lowercased() ?? ""
            if sqVal > 5 || sqText.contains("moderate") || sqText.contains("many") {
                out.append(LabValidityWarning(
                    kind: .urineContamination,
                    title: "Elevated squamous epithelial cells",
                    detail: "Squamous cells > 5/HPF indicate collection contamination, which can falsely elevate protein, WBC, leukocyte esterase, and bacteria.",
                    recommendsRedraw: true))
            }
        }
        return out
    }

    private static func needsMorningWindow(id: String, preAnalytic: LabPreAnalytic?) -> Bool {
        if morningHormones.contains(id) { return true }
        guard let tw = preAnalytic?.timingWindow?.lowercased() else { return false }
        return tw.contains("am") || tw.contains("morning")
    }

    private static func hasWashoutKeyword(_ pa: LabPreAnalytic?, _ word: String) -> Bool {
        pa?.washouts.contains { $0.item.lowercased().contains(word) || $0.effect.lowercased().contains(word) } ?? false
    }

    private static func preferredMassSpecPitfall(marker: LabMarker, sex: LabSex) -> String? {
        for sp in marker.specimens {
            let pop = sp.targetPopulation.lowercased()
            let sexMatches = pop.contains("all")
                || (sex == .male && (pop.contains("male") || pop.contains("men")) && !pop.contains("female") && !pop.contains("women"))
                || (sex == .female && (pop.contains("female") || pop.contains("women")))
            let pref = sp.preferredAssay.lowercased()
            if sexMatches, (pref.contains("lc-ms") || pref.contains("equilibrium dialysis")), !sp.assayPitfall.isEmpty {
                return sp.assayPitfall
            }
        }
        return nil
    }

    private static func parseHourMinute(_ raw: String) -> (Int, Int)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let isPM = trimmed.contains("pm")
        let isAM = trimmed.contains("am")
        let cleaned = trimmed.replacingOccurrences(of: "am", with: "").replacingOccurrences(of: "pm", with: "").trimmingCharacters(in: .whitespaces)
        let parts = cleaned.split(separator: ":")
        guard let first = parts.first, var hour = Int(first) else { return nil }
        let minute = parts.count > 1 ? (Int(parts[1].prefix(2)) ?? 0) : 0
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}
