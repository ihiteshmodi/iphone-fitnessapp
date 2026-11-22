import Foundation

/// The ten PhenoAge inputs, in the units the lab reports use.
public struct PhenoAgeInputs: Equatable {
    public var ageYears: Double
    public var albuminGdL: Double
    public var creatinineMgdL: Double
    public var glucoseMgdL: Double
    /// nil when the lab reported "below the detection limit"; then hsCRPBelowLimit holds that limit.
    public var hsCRPmgL: Double?
    public var hsCRPBelowLimit: Double?
    public var lymphocytePercent: Double
    public var mcvFL: Double
    public var rdwCVPercent: Double
    public var alpUL: Double
    public var wbcK: Double

    public init(ageYears: Double, albuminGdL: Double, creatinineMgdL: Double, glucoseMgdL: Double, hsCRPmgL: Double?,
                hsCRPBelowLimit: Double? = nil, lymphocytePercent: Double, mcvFL: Double, rdwCVPercent: Double, alpUL: Double, wbcK: Double) {
        self.ageYears = ageYears
        self.albuminGdL = albuminGdL
        self.creatinineMgdL = creatinineMgdL
        self.glucoseMgdL = glucoseMgdL
        self.hsCRPmgL = hsCRPmgL
        self.hsCRPBelowLimit = hsCRPBelowLimit
        self.lymphocytePercent = lymphocytePercent
        self.mcvFL = mcvFL
        self.rdwCVPercent = rdwCVPercent
        self.alpUL = alpUL
        self.wbcK = wbcK
    }
}

public enum PhenoAgeInput: String, CaseIterable, Equatable {
    case age, albumin, creatinine, glucose, hsCRP, lymphocytes, mcv, rdw, alp, wbc

    /// Catalogue marker id and the unit the formula's conversions start from.
    public var marker: (id: String, unit: String)? {
        switch self {
        case .age: return nil
        case .albumin: return ("albumin", "g/dL")
        case .creatinine: return ("creatinine", "mg/dL")
        case .glucose: return ("glucose", "mg/dL")
        case .hsCRP: return ("hs-crp", "mg/L")
        case .lymphocytes: return ("lymphocyte-pct", "%")
        case .mcv: return ("mcv", "fL")
        case .rdw: return ("rdw", "%")
        case .alp: return ("alp", "U/L")
        case .wbc: return ("wbc", "x10^3/uL")
        }
    }
}

public struct PhenoAgeResult: Equatable {
    public let phenoAge: Double
    public let ageYears: Double
    public let mortalityScore: Double
    public let linearPredictor: Double
    /// hs-CRP was below the detection limit, so its value was estimated.
    public let isEstimate: Bool
}

public enum PhenoAgeOutcome: Equatable {
    case calculated(PhenoAgeResult)
    case missing([PhenoAgeInput])
}

/// Levine et al. 2018 PhenoAge, as given by the owner's research agent ("Research (owner-approved)"); the vault names the
/// inputs but gives no formula.
public enum PhenoAge {
    static let intercept = -19.9067
    static let gamma = 0.0076927

    public static func calculate(_ x: PhenoAgeInputs) -> PhenoAgeResult {
        let crp = x.hsCRPmgL ?? (x.hsCRPBelowLimit ?? 0) / 2.0.squareRoot()
        let terms: [(PhenoAgeInput, Double)] = [
            (.albumin, -0.0336 * x.albuminGdL * 10),
            (.creatinine, 0.0095 * x.creatinineMgdL * 88.42),
            (.glucose, 0.1953 * x.glucoseMgdL / 18.0182),
            (.hsCRP, 0.0954 * log(crp / 10)),
            (.lymphocytes, -0.0120 * x.lymphocytePercent),
            (.mcv, 0.0268 * x.mcvFL),
            (.rdw, 0.3306 * x.rdwCVPercent),
            (.alp, 0.00188 * x.alpUL),
            (.wbc, 0.0554 * x.wbcK),
            (.age, 0.0804 * x.ageYears),
        ]
        let xb = intercept + terms.reduce(0) { $0 + $1.1 }
        // -ln(1 - M), used directly so a very small M does not underflow.
        let hazard = exp(xb) * (exp(120 * gamma) - 1) / gamma
        let mortality = 1 - exp(-hazard)
        let age = 141.50225 + log(0.00553 * hazard) / 0.090165
        return PhenoAgeResult(phenoAge: age, ageYears: x.ageYears, mortalityScore: mortality, linearPredictor: xb,
                              isEstimate: x.hsCRPmgL == nil)
    }

    /// Only from one draw, so the inputs were measured together (the vault: compare like with like).
    public static func forDraw(_ drawID: Int, draws: LabDrawService, birthDate: ISODate) throws -> PhenoAgeOutcome {
        let results = try draws.results(inDraw: drawID)
        let drawDate = try draws.draws().first { $0.id == drawID }?.draft.date
        guard let day = results.first?.date ?? drawDate else { return .missing(PhenoAgeInput.allCases) }
        var values: [PhenoAgeInput: Double] = [:]
        var crpBelowLimit = false
        for input in PhenoAgeInput.allCases {
            guard let (id, unit) = input.marker else { continue }
            let acceptedUnits: Set<String> = input == .wbc ? [unit, "x 10^9/L"] : [unit]
            guard let result = results.first(where: {
                $0.markerID == id && (acceptedUnits.contains($0.unit) || ($0.defaultUnit.map(acceptedUnits.contains) ?? false))
            }) else { continue }
            values[input] = acceptedUnits.contains(result.unit) ? result.value : result.defaultValue
            if input == .hsCRP && result.valueOperator == .belowLimit { crpBelowLimit = true }
        }
        let missing = PhenoAgeInput.allCases.filter { $0 != .age && values[$0] == nil }
        guard missing.isEmpty else { return .missing(missing) }
        let age = Double(day.days(since: birthDate)) / 365.25
        let hsCRPVal = values[.hsCRP]!
        return .calculated(calculate(PhenoAgeInputs(ageYears: age, albuminGdL: values[.albumin]!, creatinineMgdL: values[.creatinine]!,
                                                    glucoseMgdL: values[.glucose]!, hsCRPmgL: crpBelowLimit ? nil : hsCRPVal,
                                                    hsCRPBelowLimit: crpBelowLimit ? hsCRPVal : nil,
                                                    lymphocytePercent: values[.lymphocytes]!, mcvFL: values[.mcv]!,
                                                    rdwCVPercent: values[.rdw]!, alpUL: values[.alp]!, wbcK: values[.wbc]!)))
    }

    /// The ten inputs with only their formula units, for tests and for a catalogue that lacks them.
    public static var inputCatalogue: LabCatalogue {
        let json = "{\"markers\": [" + PhenoAgeInput.allCases.compactMap(\.marker).map {
            "{\"id\": \"\($0.id)\", \"name\": \"\($0.id)\", \"units\": [{\"unit\": \"\($0.unit)\", \"default\": true}]}"
        }.joined(separator: ",") + "]}"
        return try! LabCatalogue(data: Data(json.utf8))
    }
}
