import FitnessCore
import SwiftUI

enum TestedDashboardFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case core = "★ Core"
    case needsAttention = "Needs attention"
    case inLabNotOptimal = "In lab · not optimal"
    case optimal = "Optimal"

    var id: String { rawValue }
}

/// Unified Bloodwork Dashboard: latest value per marker across all draws, Core badges, exact band status, and combined interpretations.
struct BloodworkDashboardView: View {
    @ObservedObject var model: LabsModel
    @State private var filter: TestedDashboardFilter = .all
    @State private var search = ""
    @State private var showCleanChecks = false

    private var snapshot: LabLatestSnapshot {
        model.dashboard?.snapshot ?? .empty
    }

    private var filteredRows: [LabTestedMarkerRow] {
        snapshot.testedRows.filter { row in
            let matchesSearch = search.trimmingCharacters(in: .whitespaces).isEmpty
                || row.marker.name.localizedCaseInsensitiveContains(search)
                || row.marker.chapter.localizedCaseInsensitiveContains(search)
                || row.marker.aliases.contains { $0.localizedCaseInsensitiveContains(search) }
            guard matchesSearch else { return false }
            switch filter {
            case .all:
                return true
            case .core:
                return row.isCore
            case .needsAttention:
                return [.belowLabRange, .aboveLabRange, .low, .high, .withinLabBelowOptimal, .withinLabAboveOptimal].contains(row.rangeClassification)
            case .inLabNotOptimal:
                return [.withinLabBelowOptimal, .withinLabAboveOptimal, .disputed].contains(row.rangeClassification)
            case .optimal:
                return row.rangeClassification == .optimal || row.rangeClassification == .withinLabNoOptimal
            }
        }
    }

    private var chapters: [String] {
        var seen: [String] = []
        for row in filteredRows where !seen.contains(row.marker.chapter) { seen.append(row.marker.chapter) }
        return seen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summaryCard
                interpretationsCard
                filterControls
                if filteredRows.isEmpty {
                    Text(snapshot.testedRows.isEmpty
                         ? "No bloodwork results logged yet. Tap + Add a draw on Bloodwork to get started."
                         : "No tested markers match the current filter.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                        .card()
                } else {
                    ForEach(chapters, id: \.self) { chapter in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(chapter)
                            let chapterRows = filteredRows.filter { $0.marker.chapter == chapter }
                            ForEach(Array(chapterRows.enumerated()), id: \.element.id) { idx, row in
                                if idx > 0 { Divider().overlay(Theme.line) }
                                NavigationLink {
                                    MarkerDetailView(model: model, marker: row.marker)
                                } label: {
                                    testedMarkerRow(row)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("labs-dashboard-marker-\(row.marker.id)")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .searchable(text: $search, prompt: "Search tested markers")
        .navigationTitle("Bloodwork Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load() }
    }

    private var summaryCard: some View {
        let rows = snapshot.testedRows
        let coreCount = rows.filter(\.isCore).count
        let optCount = rows.filter { $0.rangeClassification == .optimal || $0.rangeClassification == .withinLabNoOptimal }.count
        let inLabSubopt = rows.filter { [.withinLabBelowOptimal, .withinLabAboveOptimal, .disputed].contains($0.rangeClassification) }.count
        let outCount = rows.filter { [.belowLabRange, .aboveLabRange, .low, .high].contains($0.rangeClassification) }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Latest-per-marker snapshot")
                Spacer()
                Pill(text: "\(rows.count) tested · ★ \(coreCount) Core", tone: .gold)
            }
            Text("Uses strictly the newest logged value for each marker across your draws — older superseded values are ignored.")
                .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Pill(text: "\(optCount) optimal", tone: .green)
                if inLabSubopt > 0 { Pill(text: "\(inLabSubopt) in lab · not optimal", tone: .amber) }
                if outCount > 0 { Pill(text: "\(outCount) high / low", tone: .red) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-dashboard-summary")
    }

    private var interpretationsCard: some View {
        let totalFindings = snapshot.activePatterns.count + snapshot.discordances.count
            + snapshot.simplePatterns.count + snapshot.epistaticMatches.filter { !$0.id.hasSuffix("-silent") && !$0.id.hasSuffix("-unexpressed") }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Combined interpretations")
                Spacer()
                Pill(text: totalFindings == 0 ? "All clear" : "\(totalFindings) active",
                     tone: totalFindings == 0 ? .green : .amber)
            }

            if totalFindings == 0 {
                Text("No multi-marker discordances or red-flag combinations triggered across your latest marker values.")
                    .font(.system(size: 13)).foregroundColor(Theme.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(snapshot.activePatterns) { match in
                NavigationLink { PatternDetailView(match: match, showDrugNotes: model.showDrugNotes) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(match.name).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amber)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(Theme.muted)
                        }
                        if !match.matchedPhenotypes.isEmpty {
                            Text(match.matchedPhenotypes.map(\.name).joined(separator: " · "))
                                .font(.system(size: 12)).foregroundColor(Theme.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            ForEach(snapshot.discordances) { disc in
                VStack(alignment: .leading, spacing: 2) {
                    Text("• \(disc.title)").font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amber)
                    Text(disc.detail).font(.system(size: 12)).foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(snapshot.simplePatterns) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text("• \(item.name)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(item.isUrgentDoctor ? Theme.red : Theme.amber)
                    Text(item.contributingSummary).font(.system(size: 11)).foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.detail).font(.system(size: 12)).foregroundColor(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(snapshot.epistaticMatches) { ep in
                VStack(alignment: .leading, spacing: 2) {
                    Text("• \(ep.geneName): \(ep.condition)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(ep.isUrgentSafetyStop ? Theme.red : Theme.green)
                    Text("\(ep.interpretation) \(ep.action)").font(.system(size: 12)).foregroundColor(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !snapshot.cleanCompanionChecks.isEmpty {
                DisclosureGroup("Checked & clear companion pairs (\(snapshot.cleanCompanionChecks.count))", isExpanded: $showCleanChecks) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(snapshot.cleanCompanionChecks) { check in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("✓ \(check.title)").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                                Text(check.summary).font(.system(size: 11)).foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 12, weight: .semibold))
                .tint(Theme.green)
                .accessibilityIdentifier("labs-dashboard-clean-checks")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-dashboard-interpretations")
    }

    private var filterControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(TestedDashboardFilter.allCases) { option in
                    let active = filter == option
                    Button(option.rawValue) { filter = option }
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(active ? Theme.green : Theme.card)
                        .foregroundColor(active ? Theme.onGreen : Theme.muted)
                        .overlay(Capsule().stroke(active ? .clear : Theme.line))
                        .clipShape(Capsule())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("labs-dashboard-filter-\(option.rawValue)")
                }
            }
        }
    }

    private func testedMarkerRow(_ row: LabTestedMarkerRow) -> some View {
        let prefs = model.preferences ?? LabPreferences(sex: model.sex, showDrugNotes: model.showDrugNotes)
        let bar = LabRangeBarModel.build(marker: row.marker, sex: model.sex, reading: row.reading, latestResult: row.result,
                                         genotypes: model.genotypes, preferences: prefs)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.marker.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        if row.isCore { Pill(text: "★ Core", tone: .gold) }
                    }
                    Text("\(Format.longDate(row.result.date))\(row.labName.map { " · \($0)" } ?? "")")
                        .font(.system(size: 11)).foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(formattedValue(row.result))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.text)
                    classificationPill(row.rangeClassification)
                }
            }
            if let bar {
                MarkerMiniRangeBar(bar: bar, status: row.reading.status)
            }
            ForEach(Array(row.interpretations.prefix(2).enumerated()), id: \.offset) { _, line in
                Text("↳ \(line)")
                    .font(.system(size: 11))
                    .foregroundColor(line.hasSuffix(": Clear") ? Theme.green : Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func formattedValue(_ result: LabResult) -> String {
        if let text = result.textValue { return text }
        if let sec = result.secondaryValue { return "\(Format.number(result.value))/\(Format.number(sec)) \(result.unit)" }
        let prefix = result.valueOperator == .belowLimit ? "< " : ""
        return "\(prefix)\(Format.number(result.value)) \(result.unit)"
    }

    private func classificationPill(_ cls: LabRangeClassification) -> some View {
        let tone: Pill.Tone = {
            switch cls {
            case .optimal, .withinLabNoOptimal: return .green
            case .withinLabBelowOptimal, .withinLabAboveOptimal, .disputed: return .amber
            case .belowLabRange, .aboveLabRange: return .red
            case .low, .high: return .gold
            case .recorded: return .grey
            }
        }()
        return Pill(text: cls.title, tone: tone)
    }
}
