import Foundation

public struct GenotypeEntry: Equatable {
    public let gene: LabGene
    public let row: LabGenotype
    public let enteredOn: ISODate
}

/// Genotypes picked from each gene's table in the vault. "Genetics sets the prior. Bloodwork sets the dose."
public final class GeneticsService {
    private let db: Database
    private let catalogue: LabCatalogue

    public init(_ db: Database, catalogue: LabCatalogue) {
        self.db = db
        self.catalogue = catalogue
    }

    public func set(_ geneID: String, genotype: String, on day: ISODate) throws {
        guard let gene = catalogue.gene(geneID) else { throw ValidationError("\(geneID) is not in the genetics catalogue") }
        guard gene.genotypes?.contains(where: { $0.genotype == genotype }) == true else {
            throw ValidationError("\(genotype) is not in the vault's \(gene.name) table")
        }
        try db.execute("""
            INSERT INTO lab_genotypes (gene_id, genotype, entered_on) VALUES (?, ?, ?)
            ON CONFLICT(gene_id) DO UPDATE SET genotype = excluded.genotype, entered_on = excluded.entered_on
            """, [.text(geneID), .text(genotype), .text(day.string)])
    }

    public func clear(_ geneID: String) throws {
        try db.execute("DELETE FROM lab_genotypes WHERE gene_id = ?", [.text(geneID)])
    }

    public func entries() throws -> [GenotypeEntry] {
        try db.query("SELECT gene_id, genotype, entered_on FROM lab_genotypes ORDER BY gene_id").compactMap { row in
            guard let gene = catalogue.gene(row.text("gene_id")),
                  let genotype = gene.genotypes?.first(where: { $0.genotype == row.text("genotype") }),
                  let day = ISODate(row.text("entered_on")) else { return nil }
            return GenotypeEntry(gene: gene, row: genotype, enteredOn: day)
        }
    }

    /// The blood tests the entered genotypes ask for, as one order panel.
    func orderItem() throws -> OrderItem? {
        var tests: [OrderTest] = []
        var reasons: [String] = []
        for entry in try entries() {
            let added = (entry.row.addsMarkers ?? []).map { id in OrderTest(name: catalogue.marker(id)?.name ?? id, markerID: catalogue.marker(id) == nil ? nil : id) }
            guard !added.isEmpty else { continue }
            reasons.append("\(entry.gene.name) \(entry.row.genotype)")
            for test in added where !tests.contains(test) { tests.append(test) }
        }
        guard !tests.isEmpty else { return nil }
        let panel = LabPanel(id: "from-genetics", name: "From your genetics", markers: tests.compactMap(\.markerID), askFor: nil,
                             when: "conditional", trigger: nil, triggerMarkers: nil, source: nil, tag: nil)
        return OrderItem(panel: panel, tests: tests, reason: reasons.joined(separator: "; "))
    }
}
