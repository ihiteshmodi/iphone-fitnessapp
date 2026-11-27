import Foundation

public struct LabJsonImportSummary: Equatable, Sendable {
    public let drawsCreated: Int
    public let drawsUpdated: Int
    public let resultsImported: Int
    public let genotypesImported: Int
    public let customGenesImported: Int
    public let markerOverridesImported: Int
}

/// Generates a self-documenting AI-fillable JSON template for Bloodwork + Draw Prep + Genetics + Marker Overrides
/// and idempotently imports/updates AI-completed JSON reports without creating duplicate draws or results.
public final class LabJsonTemplateService {
    private let db: Database
    private let catalogue: LabCatalogue

    public init(db: Database, catalogue: LabCatalogue) {
        self.db = db
        self.catalogue = catalogue
    }

    // MARK: - Wire DTOs

    public struct TemplateEnvelope: Codable {
        public var schema_version: Int? = 1
        public var instructions_for_ai: [String]?
        public var draws: [DrawItem]?
        public var genotypes: [GenotypeItem]?
        public var custom_genes: [CustomGeneItem]?
        public var marker_overrides: [MarkerOverrideItem]?
        public var marker_guide: [MarkerGuideItem]?
        public var gene_guide: [GeneGuideItem]?
    }

    public struct DrawItem: Codable {
        public var draw_date: String
        public var draw_time: String?
        public var lab: String?
        public var fasted_hours: Double?
        public var trained_72h: Bool?
        public var alcohol_5d: Bool?
        public var biotin_stopped: Bool?
        public var iron_stopped: Bool?
        public var ill_recently: Bool?
        public var cycle_day: Int?
        public var cycle_phase: String?
        public var poor_sleep: Bool?
        public var acute_stress: Bool?
        public var recent_vaccine_or_surgery: Bool?
        public var meds_noted: String?
        public var note: String?
        public var results: [ResultItem]
    }

    public struct ResultItem: Codable {
        public var marker_id: String
        public var value: Double?
        public var text_value: String?
        public var value_operator: String?
        public var secondary_value: Double?
        public var custom_to_default: Double?
        public var specimen: String?
        public var assay: String?
        public var unit: String?
        public var lab_low: Double?
        public var lab_high: StringOrDouble?
    }

    public enum StringOrDouble: Codable {
        case double(Double)

        public var doubleValue: Double? {
            switch self {
            case .double(let d): return d
            }
        }

        public init(_ d: Double) { self = .double(d) }

        public init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) {
                self = .double(d)
                return
            }
            if let s = try? c.decode(String.self), let d = Double(s.trimmingCharacters(in: .whitespaces)) {
                self = .double(d)
                return
            }
            throw DecodingError.typeMismatch(Double.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected number"))
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .double(let d): try c.encode(d)
            }
        }
    }

    public struct GenotypeItem: Codable {
        public var gene_id: String
        public var genotype: String
        public var custom_genotype: String?
        public var entered_on: String
        public var lab: String?
        public var note: String?
    }

    public struct CustomGeneItem: Codable {
        public var id: String
        public var name: String
        public var variant: String?
        public var genotype: String
        public var entered_on: String
        public var lab: String?
        public var note: String?
    }

    public struct MarkerOverrideItem: Codable {
        public var marker_id: String
        public var optimal_low: Double?
        public var optimal_high: Double?
        public var unit: String
        public var note: String?
    }

    public struct MarkerGuideItem: Codable {
        public var marker_id: String
        public var name: String
        public var chapter: String
        public var aliases: [String]
        public var default_unit: String?
        public var allowed_units: [String]
        public var sample: String?
        public var qualitative_values: [String]?
        public var needs_lab_range: Bool
    }

    public struct GeneGuideItem: Codable {
        public var gene_id: String
        public var name: String
        public var allowed_genotypes: [String]
    }

    // MARK: - Export

    public func exportTemplateJSON(includeExistingDraws: Bool = false) throws -> Data {
        let drawsService = LabDrawService(db, catalogue: catalogue)
        let geneticsService = GeneticsService(db, catalogue: catalogue)
        let overrideService = LabMarkerOverrideService(db)

        let drawItems: [DrawItem]
        if includeExistingDraws {
            drawItems = try drawsService.draws().map { draw in
                let rawResults = try drawsService.results(inDraw: draw.id).filter { !$0.isCalculated }
                return DrawItem(
                    draw_date: draw.draft.date.string,
                    draw_time: draw.draft.time,
                    lab: draw.draft.lab,
                    fasted_hours: draw.draft.fastedHours,
                    trained_72h: draw.draft.trainedHard72h,
                    alcohol_5d: draw.draft.alcohol5d,
                    biotin_stopped: draw.draft.biotinStopped,
                    iron_stopped: draw.draft.ironStopped,
                    ill_recently: draw.draft.illRecently,
                    cycle_day: draw.draft.cycleDay,
                    cycle_phase: draw.draft.cyclePhase,
                    poor_sleep: draw.draft.poorSleep,
                    acute_stress: draw.draft.acuteStress,
                    recent_vaccine_or_surgery: draw.draft.recentVaccineOrSurgery,
                    meds_noted: draw.draft.medsNoted,
                    note: draw.draft.note,
                    results: rawResults.map { r in
                        ResultItem(
                            marker_id: r.markerID,
                            value: r.textValue != nil && r.defaultValue == nil ? nil : r.value,
                            text_value: r.textValue,
                            value_operator: r.valueOperator?.rawValue,
                            secondary_value: r.secondaryValue,
                            custom_to_default: r.customToDefault,
                            specimen: r.specimen,
                            assay: r.assay,
                            unit: r.unit,
                            lab_low: r.labLow,
                            lab_high: r.labHigh.map(StringOrDouble.init)
                        )
                    }
                )
            }
        } else {
            drawItems = [
                DrawItem(
                    draw_date: "YYYY-MM-DD",
                    draw_time: "08:00",
                    lab: "Lab Name",
                    fasted_hours: 12.0,
                    trained_72h: false,
                    alcohol_5d: false,
                    biotin_stopped: true,
                    iron_stopped: true,
                    ill_recently: false,
                    cycle_day: nil,
                    cycle_phase: nil,
                    poor_sleep: false,
                    acute_stress: false,
                    recent_vaccine_or_surgery: false,
                    meds_noted: nil,
                    note: "Optional draw context",
                    results: [
                        ResultItem(marker_id: "apob", value: 72.0, text_value: nil, value_operator: "=", secondary_value: nil,
                                   custom_to_default: nil, specimen: nil, assay: nil, unit: "mg/dL", lab_low: 40.0, lab_high: StringOrDouble(100.0)),
                    ]
                ),
            ]
        }

        let existingGenotypes = try geneticsService.entries().map {
            GenotypeItem(gene_id: $0.gene.id, genotype: $0.row.genotype, custom_genotype: $0.customGenotype,
                         entered_on: $0.enteredOn.string, lab: $0.lab, note: $0.note)
        }
        let existingCustomGenes = try geneticsService.customGenes().map {
            CustomGeneItem(id: $0.id, name: $0.name, variant: $0.variant, genotype: $0.genotype,
                           entered_on: $0.enteredOn.string, lab: $0.lab, note: $0.note)
        }
        let existingOverrides = try overrideService.overrides().map {
            MarkerOverrideItem(marker_id: $0.markerID, optimal_low: $0.optimalLow, optimal_high: $0.optimalHigh,
                               unit: $0.unit, note: $0.note)
        }

        let markerGuide: [MarkerGuideItem] = catalogue.markers.filter { !$0.computed }.map { m in
            let qualValues = Array(Set(m.bands.flatMap { $0.values ?? [] })).sorted()
            return MarkerGuideItem(
                marker_id: m.id,
                name: m.name,
                chapter: m.chapter,
                aliases: m.aliases,
                default_unit: m.defaultUnit,
                allowed_units: m.units.map(\.unit),
                sample: m.sample,
                qualitative_values: qualValues.isEmpty ? nil : qualValues,
                needs_lab_range: m.needsLabRange
            )
        }

        let geneGuide: [GeneGuideItem] = catalogue.genes.map { g in
            GeneGuideItem(
                gene_id: g.id,
                name: g.name,
                allowed_genotypes: (g.genotypes ?? []).map(\.genotype)
            )
        }

        let envelope = TemplateEnvelope(
            schema_version: 1,
            instructions_for_ai: [
                "Fill `draws` with one object per blood draw date (`YYYY-MM-DD`).",
                "Use exact `marker_id` and one of `allowed_units` from `marker_guide` (skip computed ratios; the app calculates them automatically).",
                "For `<0.2` or `>100` limits of detection, set `value` to the number and `value_operator` to `\"<\"` or `\">\"`.",
                "For `blood-pressure`, put systolic in `value` and diastolic in `secondary_value` with unit `\"mmHg\"`.",
                "For qualitative tests (dipstick, ANA titer), put the printed text in `text_value`.",
                "For `genotypes`, pick `gene_id` and `genotype` from `gene_guide` (and optionally set `custom_genotype` if your DNA report uses custom nomenclature). Put non-catalogue SNPs in `custom_genes`.",
                "You may omit `marker_guide` and `gene_guide` in the returned JSON to keep the file compact.",
            ],
            draws: drawItems,
            genotypes: existingGenotypes,
            custom_genes: existingCustomGenes.isEmpty ? nil : existingCustomGenes,
            marker_overrides: existingOverrides.isEmpty ? nil : existingOverrides,
            marker_guide: markerGuide,
            gene_guide: geneGuide
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    // MARK: - Idempotent Import

    @discardableResult
    public func importFilledJSON(_ data: Data) throws -> LabJsonImportSummary {
        let envelope: TemplateEnvelope
        do {
            envelope = try JSONDecoder().decode(TemplateEnvelope.self, from: data)
        } catch {
            throw ValidationError("Invalid Lab JSON payload: \(error.localizedDescription)")
        }

        let drawsService = LabDrawService(db, catalogue: catalogue)
        let geneticsService = GeneticsService(db, catalogue: catalogue)
        let overrideService = LabMarkerOverrideService(db)

        var drawsCreated = 0
        var drawsUpdated = 0
        var resultsImported = 0
        var genotypesImported = 0
        var customGenesImported = 0
        var overridesImported = 0

        try db.transaction {
            let existingDraws = try drawsService.draws()

            for item in envelope.draws ?? [] {
                guard let drawDate = ISODate(item.draw_date) else {
                    if item.draw_date == "YYYY-MM-DD" { continue }
                    throw ValidationError("Invalid draw_date '\(item.draw_date)' (expected YYYY-MM-DD)")
                }
                let draft = LabDrawDraft(
                    date: drawDate,
                    time: item.draw_time,
                    lab: item.lab,
                    fastedHours: item.fasted_hours,
                    trainedHard72h: item.trained_72h,
                    alcohol5d: item.alcohol_5d,
                    biotinStopped: item.biotin_stopped,
                    ironStopped: item.iron_stopped,
                    illRecently: item.ill_recently,
                    cycleDay: item.cycle_day,
                    cyclePhase: item.cycle_phase,
                    poorSleep: item.poor_sleep,
                    acuteStress: item.acute_stress,
                    recentVaccineOrSurgery: item.recent_vaccine_or_surgery,
                    medsNoted: item.meds_noted,
                    note: item.note
                )

                let matchedDraw = existingDraws.first { existing in
                    existing.draft.date == drawDate &&
                    (existing.draft.lab ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ==
                    (item.lab ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                }

                let drawID: Int
                if let matchedDraw {
                    try drawsService.updateDraw(matchedDraw.id, draft)
                    drawID = matchedDraw.id
                    drawsUpdated += 1
                } else {
                    drawID = try drawsService.addDraw(draft)
                    drawsCreated += 1
                }

                let existingResults = try drawsService.results(inDraw: drawID).filter { !$0.isCalculated }
                for r in item.results {
                    guard let marker = catalogue.markerByLessonOrID(r.marker_id) ?? resolveMarkerAlias(r.marker_id) else {
                        throw ValidationError("Unknown marker_id '\(r.marker_id)'")
                    }
                    if marker.computed { continue }

                    let existingForMarker = existingResults.first { $0.markerID == marker.id }
                    let op = r.value_operator.flatMap(LabValueOperator.init(rawValue:))

                    if let textVal = r.text_value, !textVal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, r.value == nil {
                        if let existingForMarker {
                            try drawsService.deleteResult(existingForMarker.id)
                        }
                        _ = try drawsService.addQualitativeResult(
                            drawID: drawID,
                            markerID: marker.id,
                            textValue: textVal,
                            unit: r.unit ?? "",
                            specimen: r.specimen
                        )
                        resultsImported += 1
                    } else if let numVal = r.value {
                        let resolvedUnit = r.unit ?? marker.defaultUnit ?? marker.units.first?.unit ?? ""
                        if let existingForMarker {
                            try drawsService.updateResult(
                                existingForMarker.id,
                                value: numVal,
                                unit: resolvedUnit,
                                labLow: r.lab_low,
                                labHigh: r.lab_high?.doubleValue,
                                valueOperator: op,
                                secondaryValue: r.secondary_value,
                                customToDefault: r.custom_to_default,
                                specimen: r.specimen,
                                assay: r.assay
                            )
                        } else {
                            _ = try drawsService.addResult(
                                drawID: drawID,
                                markerID: marker.id,
                                value: numVal,
                                unit: resolvedUnit,
                                labLow: r.lab_low,
                                labHigh: r.lab_high?.doubleValue,
                                valueOperator: op,
                                secondaryValue: r.secondary_value,
                                customToDefault: r.custom_to_default,
                                specimen: r.specimen,
                                assay: r.assay
                            )
                        }
                        resultsImported += 1
                    }
                }
            }

            for g in envelope.genotypes ?? [] {
                guard let entered = ISODate(g.entered_on) else {
                    throw ValidationError("Invalid genotype entered_on '\(g.entered_on)'")
                }
                try geneticsService.updateEntry(
                    geneID: g.gene_id,
                    genotype: g.genotype,
                    customGenotype: g.custom_genotype,
                    enteredOn: entered,
                    lab: g.lab,
                    note: g.note
                )
                genotypesImported += 1
            }

            for cg in envelope.custom_genes ?? [] {
                guard let entered = ISODate(cg.entered_on) else {
                    throw ValidationError("Invalid custom gene entered_on '\(cg.entered_on)'")
                }
                try geneticsService.upsertCustomGene(CustomGeneEntry(
                    id: cg.id, name: cg.name, variant: cg.variant, genotype: cg.genotype,
                    enteredOn: entered, lab: cg.lab, note: cg.note
                ))
                customGenesImported += 1
            }

            for ov in envelope.marker_overrides ?? [] {
                try overrideService.setOverride(LabMarkerOverride(
                    markerID: ov.marker_id, optimalLow: ov.optimal_low, optimalHigh: ov.optimal_high,
                    unit: ov.unit, note: ov.note
                ))
                overridesImported += 1
            }
        }

        return LabJsonImportSummary(
            drawsCreated: drawsCreated,
            drawsUpdated: drawsUpdated,
            resultsImported: resultsImported,
            genotypesImported: genotypesImported,
            customGenesImported: customGenesImported,
            markerOverridesImported: overridesImported
        )
    }

    private func resolveMarkerAlias(_ raw: String) -> LabMarker? {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let exact = catalogue.markers.first(where: {
            $0.name.lowercased() == lower || $0.aliases.contains(where: { $0.lowercased() == lower })
        }) {
            return exact
        }
        let norm = Self.alnum(lower)
        guard !norm.isEmpty else { return nil }
        return catalogue.markers.first { m in
            Self.alnum(m.id) == norm ||
            Self.alnum(m.name) == norm ||
            m.aliases.contains(where: { Self.alnum($0) == norm })
        }
    }

    private static func alnum(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
