import Foundation

/// Plain-English walkthrough and ★ Mandatory Core Tests tracker so users know exactly where to start.
public struct CoreBloodworkItem: Equatable, Identifiable {
    public enum State: Equatable {
        case neverTested
        case retestDue(from: ISODate)
        case upToDate(lastTested: ISODate)
    }

    public let id: String
    public let title: String
    public let markerIDs: [String]
    public let onceInLifetime: Bool
    public let state: State

    public var isPending: Bool {
        switch state {
        case .neverTested, .retestDue: return true
        case .upToDate: return false
        }
    }
}

public struct CoreBloodworkStep: Equatable, Identifiable {
    public let number: Int
    public let title: String
    public let detail: String
    public var id: Int { number }
}

public struct CoreBloodworkSummary: Equatable {
    public let items: [CoreBloodworkItem]
    public let steps: [CoreBloodworkStep]

    public var neverTested: [CoreBloodworkItem] {
        items.filter {
            if case .neverTested = $0.state { return true }
            return false
        }
    }

    public var retestDue: [CoreBloodworkItem] {
        items.filter {
            if case .retestDue = $0.state { return true }
            return false
        }
    }

    public var upToDateCount: Int {
        items.count - neverTested.count - retestDue.count
    }

    public var pendingCount: Int {
        neverTested.count + retestDue.count
    }
}

public enum CoreBloodworkGuide {
    /// Extra once/baseline core markers highlighted alongside `when == "first"` panels.
    private static let supplementalCoreIDs: Set<String> = ["lpa", "homocysteine"]

    private struct Spec {
        let id: String
        let title: String
        let markerIDs: [String]
        let minimumCovered: Int
        let onceInLifetime: Bool
        let sex: LabSex?
    }

    private static let orderedSpecs: [Spec] = [
        Spec(id: "cbc", title: "CBC with Differential",
             markerIDs: ["hemoglobin", "hematocrit", "rbc", "wbc", "platelets", "mcv", "rdw", "neutrophils", "lymphocytes"],
             minimumCovered: 3, onceInLifetime: false, sex: nil),
        Spec(id: "cmp", title: "CMP (Liver & Kidney Panel)",
             markerIDs: ["creatinine", "egfr", "bun", "alt", "ast", "alp", "total-bilirubin", "albumin", "sodium", "potassium", "calcium"],
             minimumCovered: 4, onceInLifetime: false, sex: nil),
        Spec(id: "lipid-panel", title: "Standard Lipid Panel",
             markerIDs: ["total-cholesterol", "ldl-c", "hdl-c", "triglycerides"],
             minimumCovered: 3, onceInLifetime: false, sex: nil),
        Spec(id: "apob", title: "ApoB", markerIDs: ["apob"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "lpa", title: "Lp(a) (once in a lifetime)", markerIDs: ["lpa"], minimumCovered: 1, onceInLifetime: true, sex: nil),
        Spec(id: "glucose", title: "Fasting Glucose", markerIDs: ["glucose"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "hba1c", title: "HbA1c", markerIDs: ["hba1c"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "fasting-insulin", title: "Fasting Insulin", markerIDs: ["fasting-insulin"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "hs-crp", title: "hs-CRP", markerIDs: ["hs-crp"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "homocysteine", title: "Homocysteine", markerIDs: ["homocysteine"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "tsh", title: "TSH", markerIDs: ["tsh"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "free-t4", title: "Free T4", markerIDs: ["free-t4"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "free-t3", title: "Free T3", markerIDs: ["free-t3"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "ferritin", title: "Ferritin", markerIDs: ["ferritin"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "iron-panel", title: "Iron Panel (Iron, TIBC & TSAT)",
             markerIDs: ["serum-iron", "tibc", "tsat"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "vitamin-d", title: "Vitamin D (25-OH)", markerIDs: ["vitamin-d"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        Spec(id: "b12", title: "Vitamin B12", markerIDs: ["b12"], minimumCovered: 1, onceInLifetime: false, sex: nil),
        // Male core hormones
        Spec(id: "total-testosterone", title: "Total Testosterone", markerIDs: ["total-testosterone"], minimumCovered: 1, onceInLifetime: false, sex: .male),
        Spec(id: "free-testosterone", title: "Free Testosterone", markerIDs: ["free-testosterone"], minimumCovered: 1, onceInLifetime: false, sex: .male),
        Spec(id: "estradiol", title: "Estradiol (Sensitive)", markerIDs: ["estradiol"], minimumCovered: 1, onceInLifetime: false, sex: .male),
        Spec(id: "shbg", title: "SHBG", markerIDs: ["shbg"], minimumCovered: 1, onceInLifetime: false, sex: .male),
        Spec(id: "lh-fsh-male", title: "LH & FSH", markerIDs: ["lh", "fsh"], minimumCovered: 1, onceInLifetime: false, sex: .male),
        // Female core hormones
        Spec(id: "estradiol-female", title: "Estradiol", markerIDs: ["estradiol"], minimumCovered: 1, onceInLifetime: false, sex: .female),
        Spec(id: "progesterone", title: "Progesterone", markerIDs: ["progesterone"], minimumCovered: 1, onceInLifetime: false, sex: .female),
        Spec(id: "lh-fsh-female", title: "LH & FSH", markerIDs: ["lh", "fsh"], minimumCovered: 1, onceInLifetime: false, sex: .female),
        Spec(id: "total-testosterone-female", title: "Total Testosterone", markerIDs: ["total-testosterone"], minimumCovered: 1, onceInLifetime: false, sex: .female),
        Spec(id: "shbg-female", title: "SHBG", markerIDs: ["shbg"], minimumCovered: 1, onceInLifetime: false, sex: .female),
    ]

    public static let walkthroughSteps: [CoreBloodworkStep] = [
        CoreBloodworkStep(
            number: 1,
            title: "Start with ★ Mandatory Core Tests (skip the rest for now)",
            detail: "You never need to order all 80+ markers at once. Check the ★ Core Tests card first to see which foundational tests you haven't done yet or are due to retest."
        ),
        CoreBloodworkStep(
            number: 2,
            title: "Open Plan Draw 3–4 days before your blood test",
            detail: "Pick your draw date and morning time (7–9 AM fasted) to get your exact prep timeline — stopping biotin 72h out, heavy lifting 48–72h out, and fasting 10–12h with water."
        ),
        CoreBloodworkStep(
            number: 3,
            title: "Tap + Add a Draw when your PDF report arrives",
            detail: "Markers page is a read-only reference library. Enter your numbers via + Add a Draw — the app auto-converts units and calculates ratios, Globulin, and PhenoAge."
        ),
        CoreBloodworkStep(
            number: 4,
            title: "Check Visual Range Bars & only add follow-ups when flagged",
            detail: "Green on the bar = optimal. Extra follow-up tests in Plan Draw only matter when a core marker lands outside optimal or a retest date becomes due."
        ),
    ]

    public static func coreMarkerIDs(catalogue: LabCatalogue, sex: LabSex) -> Set<String> {
        var ids = Set<String>()
        for panel in catalogue.panels where panel.when == "first" && sex.allows(sex: nil, tag: panel.tag, showDrugNotes: false) {
            for mid in panel.markers {
                if let marker = catalogue.marker(mid), marker.applies(to: sex) {
                    ids.insert(marker.id)
                }
            }
        }
        for mid in supplementalCoreIDs {
            if let marker = catalogue.marker(mid), marker.applies(to: sex) {
                ids.insert(marker.id)
            }
        }
        return ids
    }

    public static func isCoreMarker(_ markerID: String, catalogue: LabCatalogue, sex: LabSex) -> Bool {
        coreMarkerIDs(catalogue: catalogue, sex: sex).contains(markerID)
    }

    public static func summarize(catalogue: LabCatalogue, draws: LabDrawService, sex: LabSex, today: ISODate) throws -> CoreBloodworkSummary {
        let planner = DrawPlanner(catalogue: catalogue, draws: draws, sex: sex)
        let retestsByMarker = Dictionary(uniqueKeysWithValues: try planner.retests().map { ($0.marker.id, $0) })

        var items: [CoreBloodworkItem] = []
        for spec in orderedSpecs {
            if let requiredSex = spec.sex, sex != .any, requiredSex != sex { continue }
            let presentMarkers = spec.markerIDs.filter { catalogue.marker($0)?.applies(to: sex) == true }
            guard !presentMarkers.isEmpty else { continue }
            let threshold = min(spec.minimumCovered, presentMarkers.count)

            var latestDates: [ISODate] = []
            var earliestDue: ISODate?
            for mid in presentMarkers {
                if let latest = try draws.history(of: mid).first {
                    latestDates.append(latest.date)
                    if !spec.onceInLifetime, let dueFrom = retestsByMarker[mid]?.from, dueFrom <= today {
                        if let currentEarliest = earliestDue {
                            if dueFrom < currentEarliest { earliestDue = dueFrom }
                        } else {
                            earliestDue = dueFrom
                        }
                    }
                }
            }

            let state: CoreBloodworkItem.State
            if latestDates.count < threshold {
                state = .neverTested
            } else if let dueFrom = earliestDue {
                state = .retestDue(from: dueFrom)
            } else {
                state = .upToDate(lastTested: latestDates.max()!)
            }

            items.append(CoreBloodworkItem(id: spec.id, title: spec.title, markerIDs: presentMarkers,
                                           onceInLifetime: spec.onceInLifetime, state: state))
        }

        return CoreBloodworkSummary(items: items, steps: walkthroughSteps)
    }
}
