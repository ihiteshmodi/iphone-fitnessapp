import Foundation

public enum LabStatus: Equatable {
    case optimal
    /// Inside some of the vault's optimal bands but not all: the vault disagrees with itself here, so no flag (D1).
    case disputed
    case low
    case high
    /// The marker has no optimal band for this person.
    case noOptimalBand
    /// The typed unit has no factor to the bands' unit.
    case notComparable
}

public struct LabReading: Equatable {
    public let value: Double?
    public let unit: String?
    public let status: LabStatus
    /// Every band (except conditional ones) this value falls in, in catalogue order.
    public let bands: [LabBand]
    public let optimalBands: [LabBand]
    public let disputes: [String]
    /// Both names when the value sits exactly on a boundary two bands share (D3).
    public let edgeLabels: [String]
    /// Every doctor line crossed, most urgent first (D2).
    public let doctorLines: [LabDoctorLine]
}

public enum LabReader {
    public static func read(value typed: Double, unit: String, marker: LabMarker, sex: LabSex) -> LabReading {
        guard let value = marker.toDefault(typed, unit: unit) else {
            return LabReading(value: nil, unit: nil, status: .notComparable, bands: [], optimalBands: [], disputes: [], edgeLabels: [], doctorLines: [])
        }
        let applicable = marker.bands.filter { applies($0.sex, to: sex) && $0.condition == nil }
        let containing = applicable.filter { band in bounds(of: band, in: marker).map { contains($0, value, band) } ?? false }
        let optimal = applicable.filter { $0.kind == "optimal" && bounds(of: $0, in: marker) != nil }
        let doctor = marker.doctor
            .filter { applies($0.sex, to: sex) && $0.requires == nil }
            .filter { line in
                guard let op = line.op, let limit = line.value else { return false }
                return converted(limit, line.unit, marker).map { crosses(value, op, $0) } ?? false
            }
            .sorted { $0.urgency < $1.urgency }
        return LabReading(value: value, unit: marker.defaultUnit, status: status(value, optimal, marker), bands: containing,
                          optimalBands: optimal, disputes: Array(Set(optimal.compactMap(\.dispute))).sorted(),
                          edgeLabels: edgeLabels(value, containing.filter { $0.kind != "lab" && $0.dispute == nil }, marker),
                          doctorLines: doctor)
    }

    private static func status(_ value: Double, _ optimal: [LabBand], _ marker: LabMarker) -> LabStatus {
        guard !optimal.isEmpty else { return .noOptimalBand }
        let inside = optimal.filter { band in bounds(of: band, in: marker).map { contains($0, value, band) } ?? false }
        if inside.count == optimal.count { return .optimal }
        if !inside.isEmpty { return .disputed }
        let lows = optimal.compactMap { bounds(of: $0, in: marker)?.low }
        let highs = optimal.compactMap { bounds(of: $0, in: marker)?.high }
        if let lowest = lows.min(), value < lowest, highs.allSatisfy({ value < $0 }) { return .low }
        if let highest = highs.max(), value > highest { return .high }
        return .disputed
    }

    private static func edgeLabels(_ value: Double, _ bands: [LabBand], _ marker: LabMarker) -> [String] {
        guard bands.count >= 2, Set(bands.map(\.label)).count >= 2 else { return [] }
        let onEdge = bands.contains { band in
            guard let b = bounds(of: band, in: marker) else { return false }
            return b.low == value || b.high == value
        }
        return onEdge ? bands.map(\.label) : []
    }

    /// Band limits in the marker's default unit; nil when the band has no unit or no stated factor (D4).
    private static func bounds(of band: LabBand, in marker: LabMarker) -> (low: Double?, high: Double?)? {
        guard let unit = band.unit else { return nil }
        let low = band.low.flatMap { marker.toDefault($0, unit: unit) }
        let high = band.high.flatMap { marker.toDefault($0, unit: unit) }
        if (band.low != nil && low == nil) || (band.high != nil && high == nil) { return nil }
        return (low, high)
    }

    private static func converted(_ value: Double, _ unit: String?, _ marker: LabMarker) -> Double? {
        unit.flatMap { marker.toDefault(value, unit: $0) }
    }

    private static func contains(_ b: (low: Double?, high: Double?), _ value: Double, _ band: LabBand) -> Bool {
        let aboveLow = b.low.map { band.lowInclusive == false ? value > $0 : value >= $0 } ?? true
        let belowHigh = b.high.map { band.highInclusive == false ? value < $0 : value <= $0 } ?? true
        return aboveLow && belowHigh
    }

    private static func crosses(_ value: Double, _ op: String, _ limit: Double) -> Bool {
        switch op {
        case ">": return value > limit
        case ">=": return value >= limit
        case "<": return value < limit
        case "<=": return value <= limit
        default: return false
        }
    }

    private static func applies(_ bandSex: LabSex?, to sex: LabSex) -> Bool {
        bandSex == nil || bandSex == .any || bandSex == sex
    }
}
