import Foundation

public struct GenotypeEntry: Equatable {
    public let gene: LabGene
    public let row: LabGenotype
    public let enteredOn: ISODate
    public let customGenotype: String?
    public let lab: String?
    public let note: String?

    public init(gene: LabGene, row: LabGenotype, enteredOn: ISODate,
                customGenotype: String? = nil, lab: String? = nil, note: String? = nil) {
        self.gene = gene
        self.row = row
        self.enteredOn = enteredOn
        self.customGenotype = customGenotype
        self.lab = lab
        self.note = note
    }
}

public struct CustomGeneEntry: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var variant: String?
    public var genotype: String
    public var enteredOn: ISODate
    public var lab: String?
    public var note: String?

    public init(id: String, name: String, variant: String? = nil, genotype: String, enteredOn: ISODate,
                lab: String? = nil, note: String? = nil) {
        self.id = id
        self.name = name
        self.variant = variant
        self.genotype = genotype
        self.enteredOn = enteredOn
        self.lab = lab
        self.note = note
    }
}

/// Genotypes picked from each gene's table in the vault. "Genetics sets the prior. Bloodwork sets the dose."
public final class GeneticsService {
    private let db: Database
    private let catalogue: LabCatalogue

    public init(_ db: Database, catalogue: LabCatalogue) {
        self.db = db
        self.catalogue = catalogue
    }

    public func set(_ geneID: String, genotype: String, on day: ISODate,
                    customGenotype: String? = nil, lab: String? = nil, note: String? = nil) throws {
        try updateEntry(geneID: geneID, genotype: genotype, customGenotype: customGenotype, enteredOn: day, lab: lab, note: note)
    }

    public func updateEntry(geneID: String, genotype: String, customGenotype: String? = nil,
                            enteredOn: ISODate, lab: String? = nil, note: String? = nil) throws {
        guard let gene = catalogue.gene(geneID) else { throw ValidationError("\(geneID) is not in the genetics catalogue") }
        let cleanCustom = Self.clean(customGenotype)
        let matched: LabGenotype
        if let exact = Self.matchGenotype(genotype, in: gene) {
            matched = exact
        } else if cleanCustom != nil, let fallback = gene.genotypes?.first {
            matched = fallback
        } else {
            throw ValidationError("\(genotype) is not in the vault's \(gene.name) table")
        }
        if gene.id != geneID {
            try db.execute("DELETE FROM lab_genotypes WHERE gene_id = ?", [.text(geneID)])
        }
        try db.execute("""
            INSERT INTO lab_genotypes (gene_id, genotype, custom_genotype, entered_on, lab, note)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(gene_id) DO UPDATE SET
                genotype = excluded.genotype,
                custom_genotype = COALESCE(excluded.custom_genotype, lab_genotypes.custom_genotype),
                entered_on = excluded.entered_on,
                lab = COALESCE(excluded.lab, lab_genotypes.lab),
                note = COALESCE(excluded.note, lab_genotypes.note)
            """, [.text(gene.id), .text(matched.genotype), .optional(cleanCustom),
                  .text(enteredOn.string), .optional(Self.clean(lab)), .optional(Self.clean(note))])
        if customGenotype != nil || lab != nil || note != nil {
            // Explicit field replacement when updateEntry is called with optional overrides (including clearing).
            try db.execute("""
                UPDATE lab_genotypes SET custom_genotype = ?, lab = ?, note = ? WHERE gene_id = ?
                """, [.optional(cleanCustom), .optional(Self.clean(lab)), .optional(Self.clean(note)), .text(gene.id)])
        }
    }

    public func clear(_ geneID: String) throws {
        let canonical = catalogue.gene(geneID)?.id ?? geneID
        try db.execute("DELETE FROM lab_genotypes WHERE gene_id IN (?, ?)", [.text(geneID), .text(canonical)])
    }

    public func entries() throws -> [GenotypeEntry] {
        var seenGenes: Set<String> = []
        return try db.query("SELECT gene_id, genotype, custom_genotype, entered_on, lab, note FROM lab_genotypes ORDER BY gene_id").compactMap { row in
            guard let gene = catalogue.gene(row.text("gene_id")),
                  let day = ISODate(row.text("entered_on")),
                  seenGenes.insert(gene.id).inserted else { return nil }
            let custom = row.optionalText("custom_genotype")
            guard let genotype = Self.matchGenotype(row.text("genotype"), in: gene) ?? (custom != nil ? gene.genotypes?.first : nil) else {
                return nil
            }
            return GenotypeEntry(gene: gene, row: genotype, enteredOn: day,
                                 customGenotype: custom, lab: row.optionalText("lab"), note: row.optionalText("note"))
        }
    }

    public func customGenes() throws -> [CustomGeneEntry] {
        try db.query("SELECT id, name, variant, genotype, entered_on, lab, note FROM lab_custom_genes ORDER BY name COLLATE NOCASE").compactMap { row in
            guard let day = ISODate(row.text("entered_on")) else { return nil }
            return CustomGeneEntry(
                id: row.text("id"),
                name: row.text("name"),
                variant: row.optionalText("variant"),
                genotype: row.text("genotype"),
                enteredOn: day,
                lab: row.optionalText("lab"),
                note: row.optionalText("note")
            )
        }
    }

    public func upsertCustomGene(_ entry: CustomGeneEntry) throws {
        let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let genotype = entry.genotype.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !name.isEmpty, !genotype.isEmpty else {
            throw ValidationError("Custom gene requires id, name, and genotype")
        }
        try db.execute("""
            INSERT INTO lab_custom_genes (id, name, variant, genotype, entered_on, lab, note)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                variant = excluded.variant,
                genotype = excluded.genotype,
                entered_on = excluded.entered_on,
                lab = excluded.lab,
                note = excluded.note
            """, [.text(id), .text(name), .optional(Self.clean(entry.variant)), .text(genotype),
                  .text(entry.enteredOn.string), .optional(Self.clean(entry.lab)), .optional(Self.clean(entry.note))])
    }

    public func deleteCustomGene(_ id: String) throws {
        try db.execute("DELETE FROM lab_custom_genes WHERE id = ? COLLATE NOCASE", [.text(id)])
    }

    private static func clean(_ text: String?) -> String? {
        guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    /// The blood tests the entered genotypes ask for, as one order panel.
    func orderItem(draws: LabDrawService? = nil) throws -> OrderItem? {
        var tests: [OrderTest] = []
        var reasons: [String] = []
        let orderedRoles: Set<String> = ["mandatory_confirmer", "outranks_genotype", "safety_gate"]

        for entry in try entries() {
            var entryTests: [OrderTest] = []
            let isBaseline = entry.row.isBaseline
            let isChangeNothing = entry.gene.actionCategory == .changeNothing || entry.gene.changeNothingMandate

            if !entry.gene.phenotypicVerifiers.isEmpty {
                for verifier in entry.gene.phenotypicVerifiers where orderedRoles.contains(verifier.role) {
                    if isBaseline && !isChangeNothing { continue }
                    switch verifier.kind {
                    case .nonLab, .pattern:
                        continue
                    case .externalLab:
                        guard !isBaseline else { continue }
                        entryTests.append(OrderTest(name: verifier.markerName, markerID: nil, drawNote: verifier.rule))
                    case .marker:
                        guard let mid = verifier.markerID else { continue }
                        // Lp(a) is genetically fixed for life; once measured, never re-order from genetics.
                        if mid == "lpa", let draws, (try? !draws.history(of: "lpa").isEmpty) == true { continue }
                        let displayName = catalogue.marker(mid)?.name ?? verifier.markerName
                        let resolvedID = catalogue.marker(mid) == nil ? nil : mid
                        entryTests.append(OrderTest(name: displayName, markerID: resolvedID, drawNote: verifier.rule))
                    }
                }
            } else {
                entryTests = (entry.row.addsMarkers ?? []).map { id in
                    OrderTest(name: catalogue.marker(id)?.name ?? id, markerID: catalogue.marker(id) == nil ? nil : id)
                }
            }

            guard !entryTests.isEmpty else { continue }
            reasons.append("\(entry.gene.name) \(entry.row.genotype)")
            for test in entryTests where !tests.contains(where: { ($0.markerID ?? $0.name) == (test.markerID ?? test.name) }) {
                tests.append(test)
            }
        }
        guard !tests.isEmpty else { return nil }
        let panel = LabPanel(id: "from-genetics", name: "From your genetics", markers: tests.compactMap(\.markerID), askFor: nil,
                             when: "conditional", trigger: nil, triggerMarkers: nil, source: nil, tag: nil)
        return OrderItem(panel: panel, tests: tests, reason: reasons.joined(separator: "; "))
    }

    private static func matchGenotype(_ raw: String, in gene: LabGene) -> LabGenotype? {
        let rows = gene.genotypes ?? []
        if let exact = rows.first(where: { $0.genotype == raw }) { return exact }
        if let ci = rows.first(where: { $0.genotype.caseInsensitiveCompare(raw) == .orderedSame }) { return ci }
        guard gene.legacyGenotypes.contains(where: { $0.caseInsensitiveCompare(raw) == .orderedSame }) else { return nil }
        let needle = raw.lowercased()
        let prefixMatches = rows.filter {
            let g = $0.genotype.lowercased()
            return g.hasPrefix(needle + " ") || g.contains("(\(needle))") || g.contains(" \(needle) ")
        }
        return prefixMatches.count == 1 ? prefixMatches[0] : rows.first
    }
}
