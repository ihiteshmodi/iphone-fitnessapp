import Foundation

public enum LabReproductiveStatus: String, Codable, CaseIterable, Equatable {
    case premenopausal
    case postmenopausal
    case postmenopausalHRT = "postmenopausal_hrt"
    case pregnantTrimester1 = "trimester_1"
    case pregnantTrimester2 = "trimester_2"
    case pregnantTrimester3 = "trimester_3"
}

public enum LabMedicationClass: String, Codable, CaseIterable, Equatable, Hashable {
    case glp1
    case metforminOrAcidBlocker = "metformin_or_ppi"
    case thyroidHormone = "thyroid_rx"
    case cpicPrescription = "cpic_rx"
    case corticosteroid

    public var title: String {
        switch self {
        case .glp1: return "GLP-1 medication"
        case .metforminOrAcidBlocker: return "Metformin or acid blocker"
        case .thyroidHormone: return "Thyroid hormone"
        case .cpicPrescription: return "CYP2D6 / CYP2C19 prescription"
        case .corticosteroid: return "Systemic corticosteroid"
        }
    }

    public var subtitle: String {
        switch self {
        case .glp1: return "Semaglutide, tirzepatide"
        case .metforminOrAcidBlocker: return "Metformin, PPI or H2 blocker (affects B12 & ALDH2 flushing)"
        case .thyroidHormone: return "Levothyroxine, liothyronine"
        case .cpicPrescription: return "SSRIs, TCAs, clopidogrel, codeine, tramadol, tamoxifen"
        case .corticosteroid: return "Prednisone, dexamethasone"
        }
    }
}

public struct LabPreferences: Equatable {
    /// Picks the sex-specific bands.
    public var sex: LabSex
    /// True once the owner explicitly saved Male or Female (P1).
    public var isSexConfirmed: Bool
    /// True once the owner answered the initial TRT / Rx / lifestyle context checklist (editable anytime later).
    public var isContextConfirmed: Bool
    /// For calendar age in PhenoAge and age-bracketed strata.
    public var birthDate: ISODate?
    /// Drug, TRT and prescription notes are hidden unless switched on (D5).
    public var showDrugNotes: Bool
    /// Female reproductive / cycle / pregnancy modifier; nil when Male or unspecified.
    public var reproductiveStatus: LabReproductiveStatus?
    public var isEnduranceAthlete: Bool
    public var isSmoker: Bool
    public var africanAncestry: Bool
    /// Active hormone replacement (TRT, exogenous androgens, or systemic/oral HRT).
    public var onTRTOrHRT: Bool
    public var activeMedications: Set<LabMedicationClass>
    public var drinksAlcoholRegularly: Bool
    /// Suggest conditional DNA tests from bloodwork, diet, and Rx context when genotype is unlogged (default ON).
    public var reverseGeneticsEnabled: Bool
    public var oxidativeTherapyPlanned: Bool
    public var clottingRiskHistory: Bool
    public var persistentLactoseSymptoms: Bool

    public init(sex: LabSex = .male, isSexConfirmed: Bool = false, isContextConfirmed: Bool = false,
                birthDate: ISODate? = nil, showDrugNotes: Bool = false,
                reproductiveStatus: LabReproductiveStatus? = nil, isEnduranceAthlete: Bool = false, isSmoker: Bool = false,
                africanAncestry: Bool = false, onTRTOrHRT: Bool = false,
                activeMedications: Set<LabMedicationClass> = [], drinksAlcoholRegularly: Bool = false,
                reverseGeneticsEnabled: Bool = true, oxidativeTherapyPlanned: Bool = false,
                clottingRiskHistory: Bool = false, persistentLactoseSymptoms: Bool = false) {
        self.sex = sex
        self.isSexConfirmed = isSexConfirmed
        self.isContextConfirmed = isContextConfirmed
        self.birthDate = birthDate
        self.showDrugNotes = showDrugNotes
        self.reproductiveStatus = reproductiveStatus
        self.isEnduranceAthlete = isEnduranceAthlete
        self.isSmoker = isSmoker
        self.africanAncestry = africanAncestry
        self.onTRTOrHRT = onTRTOrHRT
        self.activeMedications = activeMedications
        self.drinksAlcoholRegularly = drinksAlcoholRegularly
        self.reverseGeneticsEnabled = reverseGeneticsEnabled
        self.oxidativeTherapyPlanned = oxidativeTherapyPlanned
        self.clottingRiskHistory = clottingRiskHistory
        self.persistentLactoseSymptoms = persistentLactoseSymptoms
    }
}

public final class LabSettings {
    private let db: Database

    public init(_ db: Database) { self.db = db }

    public func load() throws -> LabPreferences {
        var values: [String: String] = [:]
        let keys = [
            "'labs_sex'", "'labs_birth_date'", "'labs_show_drug_notes'", "'labs_reproductive_status'",
            "'labs_endurance_athlete'", "'labs_smoker'", "'labs_african_ancestry'",
            "'labs_context_confirmed'", "'labs_on_trt_hrt'", "'labs_active_medications'", "'labs_drinks_alcohol'",
            "'labs_reverse_genetics'", "'labs_oxidative_therapy'", "'labs_clotting_history'", "'labs_lactose_symptoms'",
        ].joined(separator: ", ")
        for row in try db.query("SELECT key, value FROM settings WHERE key IN (\(keys))") {
            values[row.text("key")] = row.text("value")
        }
        let sex = values["labs_sex"].flatMap(LabSex.init(rawValue:)) ?? .male
        let repro = sex == .female ? values["labs_reproductive_status"].flatMap(LabReproductiveStatus.init(rawValue:)) : nil
        let meds = Set((values["labs_active_medications"] ?? "")
            .split(separator: ",")
            .compactMap { LabMedicationClass(rawValue: String($0)) })
        return LabPreferences(sex: sex,
                              isSexConfirmed: values["labs_sex"] != nil,
                              isContextConfirmed: values["labs_context_confirmed"] == "1",
                              birthDate: values["labs_birth_date"].flatMap(ISODate.init),
                              showDrugNotes: values["labs_show_drug_notes"] == "1",
                              reproductiveStatus: repro,
                              isEnduranceAthlete: values["labs_endurance_athlete"] == "1",
                              isSmoker: values["labs_smoker"] == "1",
                              africanAncestry: values["labs_african_ancestry"] == "1",
                              onTRTOrHRT: values["labs_on_trt_hrt"] == "1",
                              activeMedications: meds,
                              drinksAlcoholRegularly: values["labs_drinks_alcohol"] == "1",
                              reverseGeneticsEnabled: values["labs_reverse_genetics"].map { $0 == "1" } ?? true,
                              oxidativeTherapyPlanned: values["labs_oxidative_therapy"] == "1",
                              clottingRiskHistory: values["labs_clotting_history"] == "1",
                              persistentLactoseSymptoms: values["labs_lactose_symptoms"] == "1")
    }

    public func setSex(_ sex: LabSex) throws {
        try save("labs_sex", sex.rawValue)
        if sex != .female { try db.execute("DELETE FROM settings WHERE key = 'labs_reproductive_status'") }
    }
    public func setBirthDate(_ day: ISODate?) throws {
        guard let day else { return try db.execute("DELETE FROM settings WHERE key = 'labs_birth_date'") }
        try save("labs_birth_date", day.string)
    }
    public func setShowDrugNotes(_ on: Bool) throws { try save("labs_show_drug_notes", on ? "1" : "0") }
    public func setReproductiveStatus(_ status: LabReproductiveStatus?) throws {
        guard let status else { return try db.execute("DELETE FROM settings WHERE key = 'labs_reproductive_status'") }
        try save("labs_reproductive_status", status.rawValue)
    }
    public func setEnduranceAthlete(_ on: Bool) throws { try save("labs_endurance_athlete", on ? "1" : "0") }
    public func setSmoker(_ on: Bool) throws { try save("labs_smoker", on ? "1" : "0") }
    public func setAfricanAncestry(_ on: Bool) throws { try save("labs_african_ancestry", on ? "1" : "0") }
    public func setOnTRTOrHRT(_ on: Bool) throws { try save("labs_on_trt_hrt", on ? "1" : "0") }
    public func setActiveMedications(_ classes: Set<LabMedicationClass>) throws {
        let joined = classes.map(\.rawValue).sorted().joined(separator: ",")
        try save("labs_active_medications", joined)
    }
    public func setDrinksAlcoholRegularly(_ on: Bool) throws { try save("labs_drinks_alcohol", on ? "1" : "0") }
    public func setReverseGeneticsEnabled(_ on: Bool) throws { try save("labs_reverse_genetics", on ? "1" : "0") }
    public func setOxidativeTherapyPlanned(_ on: Bool) throws { try save("labs_oxidative_therapy", on ? "1" : "0") }
    public func setClottingRiskHistory(_ on: Bool) throws { try save("labs_clotting_history", on ? "1" : "0") }
    public func setPersistentLactoseSymptoms(_ on: Bool) throws { try save("labs_lactose_symptoms", on ? "1" : "0") }
    public func confirmContext(onTRTOrHRT: Bool, activeMedications: Set<LabMedicationClass>, drinksAlcoholRegularly: Bool,
                               reverseGeneticsEnabled: Bool? = nil, oxidativeTherapyPlanned: Bool? = nil,
                               clottingRiskHistory: Bool? = nil, persistentLactoseSymptoms: Bool? = nil) throws {
        try setOnTRTOrHRT(onTRTOrHRT)
        try setActiveMedications(activeMedications)
        try setDrinksAlcoholRegularly(drinksAlcoholRegularly)
        if let reverseGeneticsEnabled { try setReverseGeneticsEnabled(reverseGeneticsEnabled) }
        if let oxidativeTherapyPlanned { try setOxidativeTherapyPlanned(oxidativeTherapyPlanned) }
        if let clottingRiskHistory { try setClottingRiskHistory(clottingRiskHistory) }
        if let persistentLactoseSymptoms { try setPersistentLactoseSymptoms(persistentLactoseSymptoms) }
        try save("labs_context_confirmed", "1")
    }

    private func save(_ key: String, _ value: String) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", [.text(key), .text(value)])
    }
}
