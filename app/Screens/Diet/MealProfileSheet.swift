import FitnessCore
import SwiftUI

struct MealProfileSheet: View {
    let meal: DietMeal
    let services: Services
    @Environment(\.dismiss) private var dismiss
    @State private var report: MealProfileReport?
    @State private var expandedKey: String? = "gl"
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let report {
                        if report.isPlannedPreview {
                            Text("Showing the planned items for \(meal.name) (tick items on Today to switch to eaten amounts).")
                                .font(.system(size: 12)).foregroundColor(Theme.muted)
                        } else {
                            Text("Showing the ticked items eaten in \(meal.name). Tap Glycemic load or any amino acid to see contributing foods.")
                                .font(.system(size: 12)).foregroundColor(Theme.muted)
                        }
                        glycemicLoadCard(report)
                        aminoAcidsCard(report)
                    }
                }
                .padding(16)
            }
            .screenBackground()
            .navigationTitle("\(meal.name) profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("meal-profile-done")
                }
            }
            .onAppear(perform: load)
            .errorAlert($errorMessage)
        }
    }

    private func glycemicLoadCard(_ report: MealProfileReport) -> some View {
        let isOpen = expandedKey == "gl"
        let tone: Pill.Tone = report.glycemicBand == .low ? .green : (report.glycemicBand == .medium ? .amber : .red)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expandedKey = isOpen ? nil : "gl" }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        SectionLabel("Meal glycemic load")
                        Spacer()
                        Pill(text: "\(report.glycemicBand.rawValue) GL", tone: tone)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                            .font(.system(size: 11, weight: .bold)).foregroundColor(Theme.muted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(Format.number(report.totalGlycemicLoad, maxDecimals: 1))
                            .font(.system(size: 28, weight: .heavy)).foregroundColor(Theme.text)
                            .accessibilityIdentifier("meal-profile-gl-value")
                        Text("GL · Low < 10 · Medium 10–19 · High ≥ 20")
                            .font(.system(size: 11)).foregroundColor(Theme.muted)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.line)
                            Capsule()
                                .fill(tone == .green ? Theme.green : (tone == .amber ? Theme.amber : Theme.red))
                                .frame(width: proxy.size.width * min(report.totalGlycemicLoad / 35.0, 1))
                        }
                    }
                    .frame(height: 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("meal-profile-gl-row")

            if isOpen {
                Divider().overlay(Theme.line)
                if report.glycemicContributors.isEmpty {
                    Text("Zero net digestible carbs with a glycemic index in this meal.")
                        .font(.system(size: 12)).foregroundColor(Theme.muted)
                } else {
                    ForEach(report.glycemicContributors) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.foodName).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.text)
                                Text("\(Format.number(item.quantity, maxDecimals: 1)) \(item.unit) · GI \(Format.number(item.glycemicIndex ?? 0, maxDecimals: 0)) · \(Format.number(item.netCarbsGrams ?? 0, maxDecimals: 1)) g net carbs")
                                    .font(.system(size: 11)).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Text("\(Format.number(item.amount, maxDecimals: 1)) GL (\(Format.number(item.percent, maxDecimals: 0))%)")
                                .font(.system(size: 12, weight: .bold)).foregroundColor(Theme.green)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .card()
    }

    private func aminoAcidsCard(_ report: MealProfileReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("Per-meal amino acids (tap any row for food sources)")
                .padding(.bottom, 4)
            ForEach(report.aminoRows) { row in
                let isOpen = expandedKey == row.id
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { expandedKey = isOpen ? nil : row.id }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.nutrient.title).font(.system(size: 13, weight: .medium)).foregroundColor(Theme.text)
                                Spacer()
                                Text("\(Format.number(row.amount, maxDecimals: 2)) / \(Format.number(row.target, maxDecimals: 1)) \(row.nutrient.unit)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(row.isMet ? Theme.green : (row.amount == 0 ? Theme.muted : Theme.amber))
                                Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10, weight: .bold)).foregroundColor(Theme.muted)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.line)
                                    Capsule().fill(row.isMet ? Theme.green : Theme.amber)
                                        .frame(width: proxy.size.width * min(row.share, 1))
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("meal-amino-\(row.nutrient.rawValue)")

                    if isOpen {
                        VStack(alignment: .leading, spacing: 4) {
                            if row.contributors.isEmpty {
                                Text("0 g — no food in \(meal.name) supplies \(row.nutrient.title.lowercased()).")
                                    .font(.system(size: 11)).foregroundColor(Theme.muted)
                            } else {
                                ForEach(row.contributors) { item in
                                    HStack {
                                        Text("\(item.foodName) (\(Format.number(item.quantity, maxDecimals: 1)) \(item.unit))")
                                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                                        Spacer()
                                        Text("\(Format.number(item.amount, maxDecimals: 2)) g · \(Format.number(item.percent, maxDecimals: 0))%")
                                            .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.green)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Theme.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .card()
    }

    private func load() {
        do {
            report = try MealProfileEvaluator.evaluate(meal: meal, book: try services.foods.book())
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
