import FitnessCore
import SwiftUI

/// Amino acids, vitamins, minerals and omega-6 eaten on a day against their daily targets, plus fiber.
struct DailyTargetsView: View {
    let day: DietDay

    private var rows: [DailyTargetRow] { DailyTargetReport.rows(day.eatenProfile) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(Format.weekdayDate(day.date)): what was ticked and added. Unknown means a food has no value for it yet, so it is not a miss.")
                    .font(.system(size: 12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                fiberRow.card()
                ForEach([NutrientGroup.aminoAcids, .vitamins, .minerals, .omega], id: \.self) { group in
                    let groupRows = rows.filter { $0.nutrient.group == group }
                    if !groupRows.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionLabel(group.rawValue).padding(.bottom, 4)
                            ForEach(groupRows, id: \.nutrient) { row(for: $0) }
                        }
                        .card()
                    }
                }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle("Daily targets")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var fiberRow: some View {
        let target = max(Nutrient.fiberDailyTarget, day.total.calories / 1000 * 14)
        return bar(name: "Fiber", amount: day.total.fiber, target: target, unit: "g", identifier: "target-fiber")
    }

    private func row(for row: DailyTargetRow) -> some View {
        bar(name: row.nutrient.title, amount: row.amount, target: row.target, unit: row.nutrient.unit, identifier: "target-\(row.nutrient.rawValue)")
    }

    private func bar(name: String, amount: Double?, target: Double, unit: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.system(size: 13)).foregroundColor(Theme.text)
                Spacer()
                Text(amount.map { "\(Format.number($0, maxDecimals: 1)) / \(Format.number(target, maxDecimals: 1)) \(unit)" } ?? "unknown")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(amount == nil ? Theme.muted : ((amount ?? 0) >= target ? Theme.green : Theme.amber))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.line)
                    Capsule().fill((amount ?? 0) >= target ? Theme.green : Theme.amber)
                        .frame(width: proxy.size.width * min((amount ?? 0) / target, 1))
                }
            }
            .frame(height: 5)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
