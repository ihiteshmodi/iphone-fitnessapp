import FitnessCore
import SwiftUI

struct CustomGeneSheet: View {
    let existing: CustomGeneEntry?
    let service: GeneticsService?
    let today: ISODate
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var variant = ""
    @State private var genotype = ""
    @State private var enteredDate = Date()
    @State private var lab = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Custom gene / SNP") {
                    TextField("Gene name (e.g. COMT)", text: $name)
                    TextField("Variant / rsID (optional)", text: $variant)
                    TextField("Genotype (e.g. Met/Met)", text: $genotype)
                    DatePicker("Test date", selection: $enteredDate, displayedComponents: .date)
                    TextField("Testing lab (optional)", text: $lab)
                    TextField("Notes (optional)", text: $note)
                }
                if let existing {
                    Section {
                        Button("Delete custom gene", role: .destructive) {
                            try? service?.deleteCustomGene(existing.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add Custom Gene" : "Edit Custom Gene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let id = existing?.id ?? name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "-")
                            try service?.upsertCustomGene(CustomGeneEntry(
                                id: id, name: name, variant: variant, genotype: genotype,
                                enteredOn: ISODate(date: enteredDate), lab: lab, note: note
                            ))
                            dismiss()
                        } catch {
                            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
                        }
                    }
                }
            }
            .onAppear {
                if let existing {
                    name = existing.name
                    variant = existing.variant ?? ""
                    genotype = existing.genotype
                    enteredDate = Format.date(from: existing.enteredOn)
                    lab = existing.lab ?? ""
                    note = existing.note ?? ""
                } else {
                    enteredDate = Format.date(from: today)
                }
            }
            .errorAlert($errorMessage)
        }
    }
}

struct MarkerPersonalOverrideSheet: View {
    let marker: LabMarker
    let existing: LabMarkerOverride?
    let service: LabMarkerOverrideService
    @Environment(\.dismiss) private var dismiss
    @State private var lowText = ""
    @State private var highText = ""
    @State private var unit = ""
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Personal optimal target for \(marker.name)") {
                    TextField("Optimal low (optional)", text: $lowText).keyboardType(.decimalPad)
                    TextField("Optimal high (optional)", text: $highText).keyboardType(.decimalPad)
                    if !marker.units.isEmpty {
                        Picker("Unit", selection: $unit) {
                            ForEach(marker.units, id: \.unit) { Text($0.unit).tag($0.unit) }
                        }
                    } else {
                        TextField("Unit", text: $unit)
                    }
                    TextField("Coach / clinical note (optional)", text: $note)
                }
                if existing != nil {
                    Section {
                        Button("Clear personal target override", role: .destructive) {
                            try? service.deleteOverride(for: marker.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Personal Target")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let lo = lowText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Format.decimal(lowText)
                            let hi = highText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : Format.decimal(highText)
                            try service.setOverride(LabMarkerOverride(
                                markerID: marker.id,
                                optimalLow: lo,
                                optimalHigh: hi,
                                unit: unit.isEmpty ? (marker.defaultUnit ?? "") : unit,
                                note: note.isEmpty ? nil : note
                            ))
                            dismiss()
                        } catch {
                            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
                        }
                    }
                }
            }
            .onAppear {
                lowText = existing?.optimalLow.map { Format.number($0) } ?? ""
                highText = existing?.optimalHigh.map { Format.number($0) } ?? ""
                unit = existing?.unit ?? marker.defaultUnit ?? marker.units.first?.unit ?? ""
                note = existing?.note ?? ""
            }
            .errorAlert($errorMessage)
        }
    }
}

/// Bulk JSON Lab Tests & Genetics Inserter Sheet (paste raw JSON or export AI template for all 115 markers).
struct LabJsonInserterSheet: View {
    let db: Database
    let catalogue: LabCatalogue
    let today: ISODate
    @Environment(\.dismiss) private var dismiss

    @State private var jsonText = ""
    @State private var importBanner: String?
    @State private var sharedFile: LabShareItem?
    @State private var errorMessage: String?

    struct LabShareItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Bulk JSON Lab Tests Inserter (115 Markers)") {
                    Text("Paste an AI-filled or manual JSON payload below to bulk-insert draws, lab results, genotypes, custom SNPs, and personal overrides.")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)

                    HStack {
                        Button("Load Sample Payload") {
                            jsonText = """
                            {
                              "schema_version": 1,
                              "draws": [
                                {
                                  "draw_date": "\(today.string)",
                                  "lab": "Metropolis",
                                  "fasted_hours": 12,
                                  "results": [
                                    { "marker_id": "apob", "value": 71.0, "unit": "mg/dL" },
                                    { "marker_id": "hs-crp", "value": 0.6, "unit": "mg/L" }
                                  ]
                                }
                              ]
                            }
                            """
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .accessibilityIdentifier("labs-json-load-sample")

                        Spacer()

                        Button("Export Blank AI Template") {
                            if let data = try? LabJsonTemplateService(db: db, catalogue: catalogue).exportTemplateJSON(includeExistingDraws: false) {
                                let url = FileManager.default.temporaryDirectory.appendingPathComponent("labs-ai-template.json")
                                try? data.write(to: url, options: .atomic)
                                sharedFile = LabShareItem(url: url)
                            }
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                    }

                    TextEditor(text: $jsonText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 190)
                        .accessibilityIdentifier("labs-json-text-editor")

                    Button("Insert JSON Lab Results") {
                        insertJson()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityIdentifier("labs-json-insert-confirm")

                    if let importBanner {
                        Text(importBanner)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Theme.green)
                            .accessibilityIdentifier("labs-json-import-banner")
                    }
                }
            }
            .navigationTitle("JSON Lab Inserter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("labs-json-done-button")
                }
            }
            .sheet(item: $sharedFile) { item in ShareSheet(items: [item.url]) }
            .errorAlert($errorMessage)
        }
    }

    private func insertJson() {
        let trimmed = jsonText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Paste a JSON payload first (or tap Load Sample Payload)."
            return
        }
        do {
            let summary = try LabJsonTemplateService(db: db, catalogue: catalogue).importFilledJSON(Data(trimmed.utf8))
            importBanner = "Imported \(summary.resultsImported) marker result(s) (\(summary.drawsCreated) new draw, \(summary.drawsUpdated) updated) ✓"
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }
}
