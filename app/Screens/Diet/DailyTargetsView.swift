import FitnessCore
import SwiftUI

/// Whole-day fiber, vitamins, minerals, omegas and functional compounds against their daily targets,
/// with expandable food/meal contributors sorted highest to lowest.
struct DailyTargetsView: View {
    let day: DietDay
    var plannedMode: Bool = false

    @EnvironmentObject private var services: Services
    @State private var report: DailyTargetsBreakdownReport?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(plannedMode
                     ? "Planned items on \(Format.weekdayDate(day.date)): tap any row to see which planned foods supply it and spot gaps while building your diet."
                     : "\(Format.weekdayDate(day.date)): whole-day fiber, vitamins, minerals, omegas, and compounds. Tap any row to see contributing foods.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                if let report {
                    DailyTargetsSectionsView(report: report, showSourceLabel: true)
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(plannedMode ? "Planned daily targets" : "Daily targets")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(day.date.string)-\(plannedMode)-\(day.eatenCount)-\(day.plannedCount)") { load() }
        .errorAlert($errorMessage)
    }

    private func load() {
        do {
            report = try DailyTargetsBreakdownEvaluator.evaluate(day: day, book: try services.foods.book(), plannedMode: plannedMode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shared expandable Fiber + Vitamin/Mineral/Omega/Compound sections used by Today, Diet Plan, and Recipes.
struct DailyTargetsSectionsView: View {
    let report: DailyTargetsBreakdownReport
    let showSourceLabel: Bool
    @State private var expandedKey: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            expandableBar(
                key: "fiber",
                name: "Fiber",
                isFatSoluble: false,
                amount: report.fiberAmount,
                target: report.fiberTarget,
                unit: "g",
                progressText: "\(Format.number(report.fiberAmount, maxDecimals: 1)) / \(Format.number(report.fiberTarget, maxDecimals: 1)) g",
                contributors: report.fiberContributors,
                identifier: "target-fiber")
            .card()

            ForEach([NutrientGroup.vitamins, .minerals, .omega, .compounds], id: \.self) { group in
                let groupRows = report.nutrientRows.filter { $0.row.nutrient.group == group }
                if !groupRows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(group.rawValue).padding(.bottom, 4)
                        ForEach(groupRows) { item in
                            expandableBar(
                                key: item.id,
                                name: item.row.nutrient.title,
                                isFatSoluble: item.row.nutrient.isFatSoluble,
                                amount: item.row.amount ?? 0,
                                target: item.row.target,
                                unit: item.row.nutrient.unit,
                                progressText: item.row.formattedProgress,
                                contributors: item.contributors,
                                identifier: "target-\(item.row.nutrient.rawValue)")
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func expandableBar(key: String, name: String, isFatSoluble: Bool, amount: Double, target: Double,
                               unit: String, progressText: String, contributors: [DailyTargetContributor],
                               identifier: String) -> some View {
        let isOpen = expandedKey == key
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expandedKey = isOpen ? nil : key }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(name).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                        if isFatSoluble { Pill(text: "fat-soluble", tone: .gold) }
                        Spacer()
                        Text(progressText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(amount >= target ? Theme.green : (amount == 0 ? Theme.muted : Theme.amber))
                            .multilineTextAlignment(.trailing)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold)).foregroundColor(Theme.muted)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule().fill(amount >= target ? Theme.green : Theme.amber)
                                .frame(width: proxy.size.width * min(target > 0 ? amount / target : 0, 1))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)

            if isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    if contributors.isEmpty {
                        Text("0 \(unit) — no item supplies \(name.lowercased()).")
                            .font(.system(size: 11)).foregroundColor(Theme.muted)
                    } else {
                        ForEach(contributors) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(contributorTitle(item))
                                    .font(.system(size: 12)).foregroundColor(Theme.muted)
                                Spacer()
                                Text(contributorAmountText(item, unit: unit))
                                    .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 4)
            }
        }
    }

    private func contributorTitle(_ item: DailyTargetContributor) -> String {
        let qty = "\(Format.number(item.quantity, maxDecimals: 1)) \(item.unit)"
        if showSourceLabel {
            return "\(item.sourceLabel) · \(item.foodName) (\(qty))"
        }
        return "\(item.foodName) (\(qty))"
    }

    private func contributorAmountText(_ item: DailyTargetContributor, unit: String) -> String {
        let pct = "\(Format.number(item.percent, maxDecimals: 0))%"
        if let iu = item.vitaminDIU {
            return "\(Format.number(item.amount, maxDecimals: 1)) mcg · \(Format.grouped(iu)) IU (\(pct))"
        }
        return "\(Format.number(item.amount, maxDecimals: 2)) \(unit) · \(pct)"
    }
}
