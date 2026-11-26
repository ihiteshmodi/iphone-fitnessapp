import Foundation

/// Proportional horizontal range bar geometry for numeric bloodwork markers.
public struct LabRangeBarModel: Equatable {
    public enum SegmentKind: String, Equatable {
        case low
        case normal
        case optimal
        case high
    }

    public struct Segment: Equatable {
        public let kind: SegmentKind
        public let startFraction: Double
        public let endFraction: Double
        public var widthFraction: Double { max(endFraction - startFraction, 0) }

        public init(kind: SegmentKind, startFraction: Double, endFraction: Double) {
            self.kind = kind
            self.startFraction = startFraction
            self.endFraction = endFraction
        }
    }

    public let unit: String
    public let domainMin: Double
    public let domainMax: Double
    public let segments: [Segment]
    public let lowLabel: String?
    public let optimalLabel: String
    public let highLabel: String?
    public let pinFraction: Double?
    public let pinText: String?
    public let geneticShiftSummary: String?

    public static func build(marker: LabMarker, sex: LabSex, reading: LabReading? = nil, latestResult: LabResult? = nil,
                             genotypes: [GenotypeEntry] = [], preferences: LabPreferences? = nil) -> LabRangeBarModel? {
        guard marker.id != "blood-pressure" else { return nil }
        if marker.units.isEmpty && !marker.isUnitlessRatio { return nil }
        let unit = reading?.unit ?? marker.defaultUnit ?? ""

        let convertedBandBound = { (val: Double?, bandUnit: String?) -> Double? in
            guard let val else { return nil }
            guard let bandUnit else { return marker.isUnitlessRatio ? val : nil }
            return marker.toDefault(val, unit: bandUnit)
        }

        let visible = marker.visibleBands(for: sex).filter { $0.condition == nil && $0.values == nil }

        // Resolve Optimal bounds (active stratum takes precedence, otherwise union of visible optimal bands).
        var optLow: Double?
        var optHigh: Double?
        if let stratum = reading?.activeStratum, (stratum.optimalLow != nil || stratum.optimalHigh != nil) {
            optLow = stratum.optimalLow
            optHigh = stratum.optimalHigh
        } else {
            let optBands = visible.filter { $0.kind == "optimal" && ($0.unit != nil || marker.isUnitlessRatio) }
            if !optBands.isEmpty {
                let hasOpenLow = optBands.contains { $0.low == nil }
                let hasOpenHigh = optBands.contains { $0.high == nil }
                if !hasOpenLow {
                    optLow = optBands.compactMap { convertedBandBound($0.low, $0.unit) }.min()
                }
                if !hasOpenHigh {
                    optHigh = optBands.compactMap { convertedBandBound($0.high, $0.unit) }.max()
                }
            }
        }

        // Resolve Standard / Lab bounds.
        var stdLow: Double? = reading?.activeStratum?.standardLow
        var stdHigh: Double? = reading?.activeStratum?.standardHigh
        if stdLow == nil || stdHigh == nil {
            let labBands = visible.filter { $0.kind == "lab" && ($0.unit != nil || marker.isUnitlessRatio) }
            if stdLow == nil { stdLow = labBands.compactMap { convertedBandBound($0.low, $0.unit) }.min() }
            if stdHigh == nil { stdHigh = labBands.compactMap { convertedBandBound($0.high, $0.unit) }.max() }
        }
        if stdLow == nil, let lLow = latestResult?.labLow {
            stdLow = marker.toDefault(lLow, unit: latestResult?.unit ?? unit) ?? lLow
        }
        if stdHigh == nil, let lHigh = latestResult?.labHigh {
            stdHigh = marker.toDefault(lHigh, unit: latestResult?.unit ?? unit) ?? lHigh
        }

        // If no optimal band exists at all, fall back to printed lab range as optimal.
        if optLow == nil && optHigh == nil {
            optLow = stdLow
            optHigh = stdHigh
        }

        // Apply active genotype optimal-range shifts (e.g. MTHFR Homocysteine < 7, APOE e4 ApoB <= 60).
        let effectivePrefs = preferences ?? LabPreferences(sex: sex)
        let geneShift = GeneticsModifierEvaluator.targetShift(
            for: marker, standardLow: optLow, standardHigh: optHigh, unit: unit,
            preferences: effectivePrefs, genotypes: genotypes)
        if let adjLow = geneShift?.adjustedOptimalLow { optLow = adjLow }
        if let adjHigh = geneShift?.adjustedOptimalHigh { optHigh = adjHigh }

        let anchors = [optLow, optHigh, stdLow, stdHigh].compactMap { $0 }
        guard let minAnchor = anchors.min(), let maxAnchor = anchors.max() else { return nil }

        let rawSpan = maxAnchor - minAnchor
        let span = rawSpan > 0 ? rawSpan : max(abs(maxAnchor) * 0.35, 1.0)
        var domainMin = optLow == nil ? 0.0 : max(0.0, minAnchor - span * 0.30)
        var domainMax = maxAnchor + span * 0.30

        let value = reading?.value ?? latestResult?.defaultValue
        if let value {
            if value < domainMin { domainMin = min(0.0, value - span * 0.1) }
            if value > domainMax { domainMax = value + span * 0.15 }
        }
        guard domainMax > domainMin else { return nil }

        let toFrac = { (x: Double) -> Double in
            min(max((x - domainMin) / (domainMax - domainMin), 0.0), 1.0)
        }

        // Build contiguous segments from domainMin -> domainMax.
        var rawSegments: [(SegmentKind, Double, Double)] = []
        var cursor = domainMin

        if let oLow = optLow {
            let lowCut = min(stdLow ?? oLow, oLow)
            if lowCut > cursor {
                rawSegments.append((.low, cursor, lowCut))
                cursor = lowCut
            }
            if oLow > cursor {
                rawSegments.append((.normal, cursor, oLow))
                cursor = oLow
            }
        }

        let optEnd = optHigh ?? domainMax
        if optEnd > cursor {
            rawSegments.append((.optimal, cursor, min(optEnd, domainMax)))
            cursor = min(optEnd, domainMax)
        }

        if let oHigh = optHigh {
            let highCut = max(stdHigh ?? oHigh, oHigh)
            if highCut > cursor {
                rawSegments.append((.normal, cursor, min(highCut, domainMax)))
                cursor = min(highCut, domainMax)
            }
            if domainMax > cursor {
                rawSegments.append((.high, cursor, domainMax))
                cursor = domainMax
            }
        }

        let segments = rawSegments.compactMap { kind, a, b -> Segment? in
            let s = toFrac(a)
            let e = toFrac(b)
            guard e > s + 1e-6 else { return nil }
            return Segment(kind: kind, startFraction: s, endFraction: e)
        }
        guard !segments.isEmpty else { return nil }

        let unitSuffix = unit.isEmpty ? "" : " \(unit)"
        let lowLabel: String? = (stdLow ?? optLow).map { "Low < \(fmt($0))" }
        let highLabel: String? = (stdHigh ?? optHigh).map { "High > \(fmt($0))" }
        let optimalLabel: String
        if let customLabel = geneShift?.adjustedLabelOverride {
            optimalLabel = customLabel
        } else {
            switch (optLow, optHigh) {
            case let (l?, h?): optimalLabel = "Optimal \(fmt(l))–\(fmt(h))\(unitSuffix)"
            case (nil, let h?): optimalLabel = "Optimal ≤ \(fmt(h))\(unitSuffix)"
            case (let l?, nil): optimalLabel = "Optimal ≥ \(fmt(l))\(unitSuffix)"
            case (nil, nil): optimalLabel = "Reference range"
            }
        }

        var pinFraction: Double?
        var pinText: String?
        if let value {
            pinFraction = min(max(toFrac(value), 0.02), 0.98)
            let statusWord: String
            switch reading?.status {
            case .optimal: statusWord = "Optimal"
            case .disputed: statusWord = "Disputed"
            case .low: statusWord = "Low"
            case .high: statusWord = "High"
            default: statusWord = "Recorded"
            }
            pinText = "You: \(fmt(value))\(unitSuffix) (\(statusWord))"
        }

        return LabRangeBarModel(unit: unit, domainMin: domainMin, domainMax: domainMax, segments: segments,
                                lowLabel: lowLabel, optimalLabel: optimalLabel, highLabel: highLabel,
                                pinFraction: pinFraction, pinText: pinText, geneticShiftSummary: geneShift?.summary)
    }

    private static func fmt(_ value: Double) -> String {
        if abs(value - value.rounded()) < 1e-6 { return String(Int(value.rounded())) }
        let one = (value * 10).rounded() / 10
        if abs(value - one) < 1e-6 { return String(format: "%.1f", value) }
        return String(format: "%.2f", value)
    }
}
