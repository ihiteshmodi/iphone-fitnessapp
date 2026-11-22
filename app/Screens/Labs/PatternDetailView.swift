import FitnessCore
import SwiftUI

struct PatternDetailView: View {
    let match: LabPatternMatch
    let showDrugNotes: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                headerCard
                if !match.contextNotes.isEmpty { contextCard }
                if !match.matchedPhenotypes.isEmpty { phenotypesCard }
                interventionsCard
                if !match.interventions.whatNotToDo.isEmpty { guardrailsCard }
                if !match.lookAlikes.isEmpty { lookAlikesCard }
                if hasEscalation { escalationCard }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(match.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hasEscalation: Bool {
        !match.escalation.urgentSameDay.isEmpty
            || !match.escalation.routineSoon.isEmpty
            || !match.escalation.specialists.isEmpty
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Active multi-marker pattern")
            Text(match.name).font(.system(size: 20, weight: .bold)).foregroundColor(Theme.text)
            Text("Matched on \(Format.longDate(match.drawDate)) draw")
                .font(.system(size: 12)).foregroundColor(Theme.muted)
            if let stage = match.stage {
                HStack {
                    Pill(text: stage.stage, tone: .amber)
                    if let timeline = stage.timeline, !timeline.isEmpty {
                        Text(timeline).font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                }
                Text(stage.criteria).font(.system(size: 12)).foregroundColor(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var contextCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Logged diet, training & body context")
            ForEach(match.contextNotes, id: \.self) { note in
                Text("• \(note)").font(.system(size: 13)).foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var phenotypesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Matched phenotypes")
            ForEach(match.matchedPhenotypes, id: \.name) { pheno in
                VStack(alignment: .leading, spacing: 3) {
                    Text(pheno.name).font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.green)
                    Text(pheno.interpretation).font(.system(size: 13)).foregroundColor(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var interventionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Stepped action plan")
            if !match.interventions.tier1Foundations.isEmpty {
                tierSection("1. Foundations", match.interventions.tier1Foundations)
            }
            if !match.interventions.tier2Nutrition.isEmpty {
                tierSection("2. Nutrition", match.interventions.tier2Nutrition)
            }
            if !match.interventions.tier3Supplements.isEmpty {
                let lines = match.interventions.tier3Supplements.map { item in
                    let dose = item.dose.map { " — \($0)" } ?? ""
                    let notes = item.notes.map { ": \($0)" } ?? ""
                    return "\(item.name)\(dose)\(notes)"
                }
                tierSection("3. Targeted supplements", lines)
            }
            if showDrugNotes && !match.interventions.tier4Peptides.isEmpty {
                tierSection("4. Compounds & peptides (educational only)", match.interventions.tier4Peptides)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func tierSection(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.green)
            ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                Text("• \(line)").font(.system(size: 13)).foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guardrailsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.octagon.fill").foregroundColor(Theme.red)
                SectionLabel("What not to do")
            }
            ForEach(Array(match.interventions.whatNotToDo.enumerated()), id: \.offset) { _, item in
                Text("• \(item)").font(.system(size: 13)).foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("labs-pattern-what-not-to-do")
    }

    private var lookAlikesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            DisclosureGroup("Differential look-alikes (\(match.lookAlikes.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(match.lookAlikes, id: \.condition) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.condition).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                            Text(item.howToRuleOut).font(.system(size: 12)).foregroundColor(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 6)
            }
            .font(.system(size: 13, weight: .semibold))
            .tint(Theme.green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var escalationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Medical escalation & specialists")
            if !match.escalation.specialists.isEmpty {
                Text("Specialists: \(match.escalation.specialists.joined(separator: ", "))")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.amber)
            }
            ForEach(Array(match.escalation.urgentSameDay.enumerated()), id: \.offset) { _, line in
                Text("• Urgent: \(line)").font(.system(size: 13)).foregroundColor(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(match.escalation.routineSoon.enumerated()), id: \.offset) { _, line in
                Text("• Clinical review: \(line)").font(.system(size: 13)).foregroundColor(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
