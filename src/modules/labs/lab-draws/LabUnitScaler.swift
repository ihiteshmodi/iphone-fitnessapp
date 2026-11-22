import Foundation

public struct LabUnitHint: Equatable {
    public let defaultUnit: String
    public let typicalLow: Double?
    public let typicalHigh: Double?
    public let summary: String
}

public struct LabScaleSuggestion: Equatable {
    public let suggestedUnit: String?
    public let suggestedFactor: Double
    public let convertedDefaultValue: Double
    public let message: String
}

public enum LabUnitScaler {
    public static func expectedHint(for marker: LabMarker, sex: LabSex) -> LabUnitHint? {
        guard let defaultUnit = marker.defaultUnit, !defaultUnit.isEmpty else { return nil }
        let span = typicalBounds(for: marker, sex: sex)
        let summary: String
        switch (span.low, span.high) {
        case let (lo?, hi?):
            summary = "Expected in \(defaultUnit) (typical \(clean(lo))–\(clean(hi)))"
        case let (lo?, nil):
            summary = "Expected in \(defaultUnit) (typical ≥ \(clean(lo)))"
        case let (nil, hi?):
            summary = "Expected in \(defaultUnit) (typical ≤ \(clean(hi)))"
        case (nil, nil):
            summary = "Expected in \(defaultUnit)"
        }
        return LabUnitHint(defaultUnit: defaultUnit, typicalLow: span.low, typicalHigh: span.high, summary: summary)
    }

    public static func checkScaleMismatch(value: Double, unit: String, marker: LabMarker, sex: LabSex) -> LabScaleSuggestion? {
        guard value > 0, value.isFinite, let defaultUnit = marker.defaultUnit else { return nil }
        let span = typicalBounds(for: marker, sex: sex)
        guard let low = span.low ?? span.high.map({ $0 * 0.1 }),
              let high = span.high ?? span.low.map({ $0 * 3.0 }), low > 0, high >= low else { return nil }
        let currentDefault = marker.toDefault(value, unit: unit) ?? value
        guard currentDefault < low / 4.0 || currentDefault > high * 4.0 else { return nil }

        let mid = (low * high).squareRoot()
        let windowLow = low * 0.65
        let windowHigh = high * 1.6

        var bestNamed: (unit: String, factor: Double, converted: Double, distance: Double)?
        for candidate in marker.units where candidate.unit != unit {
            guard let converted = marker.toDefault(value, unit: candidate.unit),
                  converted >= windowLow, converted <= windowHigh else { continue }
            let factor = candidate.toDefault ?? (converted / value)
            let distance = abs(log(converted / mid))
            if distance < (bestNamed?.distance ?? .infinity) {
                bestNamed = (candidate.unit, factor, converted, distance)
            }
        }
        if let match = bestNamed {
            let msg = "\(clean(value)) looks out of scale for \(unit) (typical \(clean(low))–\(clean(high)) \(defaultUnit)). "
                + "Did your lab report in \(match.unit)? (\(clean(value)) \(match.unit) = \(clean(match.converted)) \(defaultUnit))"
            return LabScaleSuggestion(suggestedUnit: match.unit, suggestedFactor: match.factor,
                                      convertedDefaultValue: match.converted, message: msg)
        }

        for factor in [10.0, 100.0, 1000.0, 0.1, 0.01, 0.001] {
            let converted = currentDefault * factor
            if converted >= windowLow && converted <= windowHigh {
                let scaleLabel = factor >= 1 ? "×\(Int(factor))" : "÷\(Int((1 / factor).rounded()))"
                let msg = "\(clean(value)) \(unit) looks off by \(scaleLabel) compared with typical \(clean(low))–\(clean(high)) \(defaultUnit) "
                    + "(\(scaleLabel) = \(clean(converted)) \(defaultUnit)). Check your lab's unit."
                return LabScaleSuggestion(suggestedUnit: nil, suggestedFactor: factor, convertedDefaultValue: converted, message: msg)
            }
        }
        return nil
    }

    private static func typicalBounds(for marker: LabMarker, sex: LabSex) -> (low: Double?, high: Double?) {
        let strata = marker.strata.filter { sex.allows(sex: $0.sex) && $0.pregnancy == nil && $0.requiresHRT != true }
        if let s = strata.first(where: { $0.standardLow != nil || $0.standardHigh != nil }) {
            return (s.standardLow, s.standardHigh)
        }
        if let s = strata.first(where: { $0.optimalLow != nil || $0.optimalHigh != nil }) {
            return (s.optimalLow, s.optimalHigh)
        }
        let bands = marker.visibleBands(for: sex).filter { $0.condition == nil }
        if let lab = bands.first(where: { $0.kind == "lab" && ($0.low != nil || $0.high != nil) }) {
            return (lab.unit.flatMap { marker.toDefault(lab.low ?? 0, unit: $0) }.flatMap { lab.low == nil ? nil : $0 } ?? lab.low,
                    lab.unit.flatMap { marker.toDefault(lab.high ?? 0, unit: $0) }.flatMap { lab.high == nil ? nil : $0 } ?? lab.high)
        }
        if let opt = bands.first(where: { $0.kind == "optimal" && ($0.low != nil || $0.high != nil) }) {
            return (opt.low, opt.high)
        }
        return (nil, nil)
    }

    private static func clean(_ value: Double) -> String { LabInsightsRule.number(value) }
}
