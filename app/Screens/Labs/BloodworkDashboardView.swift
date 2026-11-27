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

/// Scannable Bloodwork Dashboard Hub: compact summary & drill-down cards instead of one long scrolling dump.
struct BloodworkDashboardView: View {
    @ObservedObject var model: LabsModel

    private var snapshot: LabLatestSnapshot {
        model.dashboard?.snapshot ?? .empty
    }

    private var hub: LabDashboardHubSummary {
        LabDashboardHubSummary.build(from: snapshot)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summaryCard
                interpretationsHubCard
                quickBucketsCard
                systemsHubSection
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Bloodwork Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load() }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Latest-per-marker snapshot")
                Spacer()
                Pill(text: "\(hub.totalTested) tested · ★ \(hub.coreTestedCount) Core", tone: .gold)
            }
            Text("Uses strictly the newest logged value for each marker across your draws — older superseded values are ignored.")
                .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Pill(text: "\(hub.optimalCount) optimal", tone: .green)
                if hub.inLabSuboptimalCount > 0 { Pill(text: "\(hub.inLabSuboptimalCount) in lab · not optimal", tone: .amber) }
                if hub.outOfRangeCount > 0 { Pill(text: "\(hub.outOfRangeCount) high / low", tone: .red) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-dashboard-summary")
    }

    private var interpretationsHubCard: some View {
        NavigationLink {
            BloodworkInterpretationsDetailView(model: model, snapshot: snapshot)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    SectionLabel("Combined interpretations")
                    Spacer()
                    Pill(text: hub.activeInterpretationCount == 0 ? "All clear" : "\(hub.activeInterpretationCount) active",
                         tone: hub.activeInterpretationCount == 0 ? .green : .amber)
                    Image(systemName: "chevron.right").font(.system(size: 12)).foregroundColor(Theme.muted)
                }
                if hub.activeInterpretationCount == 0 {
                    Text("No multi-marker discordances or red-flag combinations triggered · \(hub.cleanCheckCount) companion pairs checked & clear.")
                        .font(.system(size: 13)).foregroundColor(Theme.green)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("\(snapshot.activePatterns.count) pattern engines · \(snapshot.discordances.count + snapshot.simplePatterns.count) cross-marker alerts · \(hub.cleanCheckCount) clean companion checks.")
                        .font(.system(size: 13)).foregroundColor(Theme.text)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("labs-dashboard-interpretations")
    }

    private var quickBucketsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Open tested markers")

            if !hub.attentionRows.isEmpty {
                NavigationLink {
                    TestedMarkersListView(model: model, initialFilter: .needsAttention)
                } label: {
                    hubRow(
                        icon: "exclamationmark.circle.fill",
                        iconColor: hub.outOfRangeCount > 0 ? Theme.red : Theme.amber,
                        title: "Needs attention (\(hub.attentionRows.count))",
                        subtitle: "\(hub.outOfRangeCount) out of lab range · \(hub.inLabSuboptimalCount) in lab but outside optimal")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("labs-dashboard-open-attention")
                Divider().overlay(Theme.line)
            }

            NavigationLink {
                TestedMarkersListView(model: model, initialFilter: .core)
            } label: {
                hubRow(
                    icon: "star.fill",
                    iconColor: Theme.gold,
                    title: "★ Core tested markers (\(hub.coreTestedCount))",
                    subtitle: "Foundational Tier-1 markers with latest readings & mini range bars")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("labs-dashboard-open-core")

            Divider().overlay(Theme.line)

            NavigationLink {
                TestedMarkersListView(model: model, initialFilter: .all)
            } label: {
                hubRow(
                    icon: "list.bullet.clipboard",
                    iconColor: Theme.green,
                    title: "All tested markers (\(hub.totalTested))",
                    subtitle: "Search and filter every logged marker across all draws")
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("labs-dashboard-open-all-tested")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private var systemsHubSection: some View {
        if hub.chapterSummaries.isEmpty {
            Text("No bloodwork results logged yet. Tap + Add a draw on Bloodwork to get started.")
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
                .card()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Tested by system (\(hub.chapterSummaries.count))")
                ForEach(Array(hub.chapterSummaries.enumerated()), id: \.element.id) { idx, item in
                    if idx > 0 { Divider().overlay(Theme.line) }
                    NavigationLink {
                        TestedMarkersListView(model: model, fixedChapter: item.chapter, initialFilter: .all)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(item.chapter)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.text)
                                    if item.coreCount > 0 {
                                        Pill(text: "★ \(item.coreCount)", tone: .gold)
                                    }
                                }
                                Text("\(item.rows.count) tested\(item.latestDate.map { " · latest \(Format.longDate($0))" } ?? "")")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.muted)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                if item.outOfRangeCount > 0 { Pill(text: "\(item.outOfRangeCount) high/low", tone: .red) }
                                if item.inLabSuboptimalCount > 0 { Pill(text: "\(item.inLabSuboptimalCount) subopt", tone: .amber) }
                                if item.attentionCount == 0 { Pill(text: "\(item.optimalCount) optimal", tone: .green) }
                            }
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.muted)
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("labs-dashboard-chapter-\(item.chapter)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func hubRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.text)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.leading)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12))
                .foregroundColor(Theme.muted)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct BloodworkInterpretationsDetailView: View {
    @ObservedObject var model: LabsModel
    let snapshot: LabLatestSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !snapshot.activePatterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Multi-marker pattern engines (\(snapshot.activePatterns.count))")
                        ForEach(snapshot.activePatterns) { match in
                            NavigationLink { PatternDetailView(match: match, showDrugNotes: model.showDrugNotes) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(match.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.amber)
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                if !snapshot.discordances.isEmpty || !snapshot.simplePatterns.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Cross-marker alerts (\(snapshot.discordances.count + snapshot.simplePatterns.count))")
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                if !snapshot.epistaticMatches.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Gene × bloodwork rules (\(snapshot.epistaticMatches.count))")
                        ForEach(snapshot.epistaticMatches) { ep in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("• \(ep.geneName): \(ep.condition)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(ep.isUrgentSafetyStop ? Theme.red : Theme.green)
                                Text("\(ep.interpretation) \(ep.action)").font(.system(size: 12)).foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                }

                if !snapshot.cleanCompanionChecks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Checked & clear companion pairs (\(snapshot.cleanCompanionChecks.count))")
                        ForEach(snapshot.cleanCompanionChecks) { check in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("✓ \(check.title)").font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                                Text(check.summary).font(.system(size: 11)).foregroundColor(Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                    .accessibilityIdentifier("labs-dashboard-clean-checks")
                }

                if snapshot.activePatterns.isEmpty && snapshot.discordances.isEmpty && snapshot.simplePatterns.isEmpty
                    && snapshot.epistaticMatches.isEmpty && snapshot.cleanCompanionChecks.isEmpty {
                    Text("No multi-marker interpretations yet. Log markers across draws to evaluate companion pairs and pattern engines.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                        .card()
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Interpretations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TestedMarkersListView: View {
    @ObservedObject var model: LabsModel
    var fixedChapter: String? = nil
    @State private var filter: TestedDashboardFilter
    @State private var search = ""

    init(model: LabsModel, fixedChapter: String? = nil, initialFilter: TestedDashboardFilter = .all) {
        self.model = model
        self.fixedChapter = fixedChapter
        _filter = State(initialValue: initialFilter)
    }

    private var snapshot: LabLatestSnapshot {
        model.dashboard?.snapshot ?? .empty
    }

    private var filteredRows: [LabTestedMarkerRow] {
        snapshot.testedRows.filter { row in
            if let fixedChapter, row.marker.chapter != fixedChapter { return false }
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
                return row.needsAttention
            case .inLabNotOptimal:
                return row.isInLabSuboptimal
            case .optimal:
                return row.isOptimalOrWithinLab
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
                filterControls
                if filteredRows.isEmpty {
                    Text("No tested markers match this filter.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.muted)
                        .card()
                } else {
                    ForEach(chapters, id: \.self) { chapter in
                        VStack(alignment: .leading, spacing: 10) {
                            if fixedChapter == nil {
                                SectionLabel(chapter)
                            }
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
        .navigationTitle(fixedChapter ?? "Tested Markers")
        .navigationBarTitleDisplayMode(.inline)
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
