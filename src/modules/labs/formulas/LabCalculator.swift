import Foundation

/// Works out the catalogue's formula markers from one draw's results. A value the lab printed always wins,
/// and a calculated marker can feed another (A/G uses globulin, which may itself be calculated).
struct LabCalculator {
    let catalogue: LabCatalogue

    func calculate(from stored: [LabResult]) -> [LabResult] {
        guard let first = stored.first else { return [] }
        let formulas = catalogue.markers.enumerated().filter { $0.element.formula != nil }
        var known = stored
        var added: [LabResult] = []
        var progressed = true
        while progressed {
            progressed = false
            for (index, marker) in formulas where !known.contains(where: { $0.markerID == marker.id }) {
                guard let value = value(of: marker, from: known) else { continue }
                let result = LabResult(id: -(first.drawID * 10_000 + index + 1), drawID: first.drawID, date: first.date, markerID: marker.id,
                                       value: value, unit: marker.defaultUnit ?? "", labLow: nil, labHigh: nil,
                                       defaultValue: value, defaultUnit: marker.defaultUnit, isCalculated: true)
                known.append(result)
                added.append(result)
                progressed = true
            }
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
