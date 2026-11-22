import Foundation

/// Works out the catalogue's formula markers from one draw's results. A value the lab printed always wins,
/// and a calculated marker can feed another (A/G uses globulin, which may itself be calculated).
struct LabCalculator {
    let catalogue: LabCatalogue

    func calculate(from stored: [LabResult]) -> [LabResult] {
        guard let first = stored.first else { return [] }
        var known = stored
        var added: [LabResult] = []

        func appendCalculated(markerID: String, value: Double, indexOffset: Int) {
            guard value.isFinite, let marker = catalogue.marker(markerID),
                  !known.contains(where: { $0.markerID == markerID }) else { return }
            let result = LabResult(id: -(first.drawID * 10_000 + indexOffset), drawID: first.drawID, date: first.date,
                                   markerID: marker.id, value: value, unit: marker.defaultUnit ?? "",
                                   defaultValue: value, defaultUnit: marker.defaultUnit, isCalculated: true)
            known.append(result)
            added.append(result)
        }

        // Derive absolute differential counts (x 10^9/L == x10^3/uL) from WBC + % when the lab only printed %.
        if let wbc = known.first(where: { $0.markerID == "wbc" }), let wbcVal = wbc.defaultValue ?? (wbc.unit == "x10^3/uL" || wbc.unit == "x 10^9/L" ? wbc.value : nil) {
            for (pctID, absID, offset) in [("neutrophil-pct", "neutrophils", 9001),
                                           ("lymphocyte-pct", "lymphocytes", 9002),
                                           ("monocyte-pct", "monocytes", 9003)] {
                if let pct = known.first(where: { $0.markerID == pctID }) {
                    appendCalculated(markerID: absID, value: wbcVal * pct.value / 100.0, indexOffset: offset)
                }
            }
        }

        let formulas = catalogue.markers.enumerated().filter { $0.element.formula != nil }
        var progressed = true
        while progressed {
            progressed = false
            for (index, marker) in formulas where !known.contains(where: { $0.markerID == marker.id }) {
                guard let value = value(of: marker, from: known) else { continue }
                appendCalculated(markerID: marker.id, value: value, indexOffset: index + 1)
                progressed = true
            }
        }

        // Built-in clinical ratio fallbacks when a marker lacks an inline formula expression in a fixture catalogue.
        if let cort = known.first(where: { $0.markerID == "cortisol" }),
           let dhea = known.first(where: { $0.markerID == "dhea-s" }),
           let cVal = cort.defaultValue, let dVal = dhea.defaultValue, dVal > 0 {
            appendCalculated(markerID: "cortisol-dhea-ratio", value: cVal * 100.0 / dVal, indexOffset: 9010)
        }
        if let uAlb = known.first(where: { $0.markerID == "urine-albumin-conc" }),
           let uCr = known.first(where: { $0.markerID == "urine-creatinine" }), uCr.value > 0 {
            let albMgDL = uAlb.unit.lowercased() == "mg/l" ? uAlb.value / 10.0 : uAlb.value
            appendCalculated(markerID: "urine-acr", value: (albMgDL * 1000.0) / uCr.value, indexOffset: 9011)
        }
        if let fPSA = known.first(where: { $0.markerID == "free-psa" }),
           let tPSA = known.first(where: { $0.markerID == "psa" }), let tVal = tPSA.defaultValue, tVal > 0 {
            appendCalculated(markerID: "free-psa-percent", value: (fPSA.defaultValue ?? fPSA.value) / tVal * 100.0, indexOffset: 9012)
        }

        return added
    }

    private func value(of marker: LabMarker, from results: [LabResult]) -> Double? {
        guard let formula = marker.formula else { return nil }
        var inputs: [String: Double] = [:]
        for (id, unit) in formula.inputs {
            if let value = input(id, in: unit, from: results) { inputs[id] = value }
        }
        if let condition = formula.onlyIf, LabExpression.evaluate(condition, values: inputs) != 1 { return nil }
        return LabExpression.evaluate(formula.expr, values: inputs)
    }

    /// The input in the unit the formula reads it in, converted only by factors the catalogue states.
    private func input(_ id: String, in unit: String, from results: [LabResult]) -> Double? {
        guard let result = results.first(where: { $0.markerID == id }) else { return nil }
        if result.unit == unit { return result.value }
        guard let inDefault = result.defaultValue else { return nil }
        if result.defaultUnit == unit { return inDefault }
        return catalogue.marker(id)?.fromDefault(inDefault, to: unit)
    }
}
