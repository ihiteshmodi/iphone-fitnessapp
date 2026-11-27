import FitnessCore
import SwiftUI

/// Sheet to edit a meal's `ate_at` (`HH:MM`) timestamp in place without touching food ticks.
struct MealTimePickerSheet: View {
    let date: ISODate
    let mealName: String
    let initialHm: String?
    let onSaved: () -> Void
    @EnvironmentObject private var services: Services
    @Environment(\.dismiss) private var dismiss
    @State private var pickedDate = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("\(mealName) · \(Format.longDate(date))") {
                    DatePicker("Ate at", selection: $pickedDate, displayedComponents: .hourAndMinute)
                }
                if initialHm != nil {
                    Section {
                        Button("Clear timestamp", role: .destructive) {
                            try? services.dietDays.setMealAteAt(nil, meal: mealName, on: date)
                            onSaved()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Meal Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: pickedDate)
                        let hm = String(format: "%02d:%02d", comps.hour ?? 20, comps.minute ?? 0)
                        try? services.dietDays.setMealAteAt(hm, meal: mealName, on: date)
                        onSaved()
                        dismiss()
                    }
                    .accessibilityIdentifier("diet-save-ate-at")
                }
            }
            .onAppear {
                let fallback = (try? services.appDefaults.defaultMealTime(forMeal: mealName)) ?? "19:30"
                let hm = initialHm ?? fallback
                let parts = hm.split(separator: ":").compactMap { Int($0) }
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                if parts.count == 2 {
                    comps.hour = parts[0]
                    comps.minute = parts[1]
                }
                pickedDate = Calendar.current.date(from: comps) ?? Date()
            }
        }
    }
}

/// 58pt circular Last-Meal-to-Sleep Hoop inside CheckInCard.
struct PreSleepTimingHoopRow: View {
    let date: ISODate
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @EnvironmentObject private var session: AppSession
    @State private var report: LastMealToSleepReport?
    @State private var targetBedHm = "23:00"

    var body: some View {
        Group {
            if let r = report, r.lastMealHm != nil {
                HStack(spacing: 12) {
                    let gap = r.gapHours ?? 4.5
                    let color: Color = r.status == .tooCloseWarning ? Theme.red : (r.status == .optimal ? Theme.green : Theme.amber)
                    let prog = min(1.0, max(0.15, gap / 6.0))
                    RingView(
                        progress: prog,
                        size: 56,
                        lineWidth: 5.5,
                        label: String(format: "%.1fh", max(0, gap)),
                        subLabel: "gap",
                        color: color
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(r.lastMealLabel ?? "Last meal") @ \(r.lastMealHm ?? "")")
                                .font(.system(size: 13.5, weight: .bold)).foregroundColor(Theme.text)
                            Pill(
                                text: r.status == .tooCloseWarning ? "<3h Warn" : (r.status == .optimal ? "4–6h Optimal" : "OK"),
                                tone: r.status == .tooCloseWarning ? .red : (r.status == .optimal ? .green : .amber)
                            )
                        }
                        Text("\(Format.number(r.lastMealCarbsGrams, maxDecimals: 0))g last-meal carbs · Target bed \(targetBedHm)")
                            .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .accessibilityIdentifier("checkin-meal-sleep-hoop")
            }
        }
        .task(id: "\(date.string)-\(session.revision)") {
            let defaults = (try? services.appDefaults.load()) ?? AppDefaultsSnapshot()
            let snap = try? WhoopDashboardPresenter.build(whoopDb: whoop.db, fitnessDb: services.db, on: date)
            let bedHm = snap?.sleep.targetBedtimeHm ?? "23:00"
            targetBedHm = bedHm
            let sleepEpoch = Self.bedtimeEpoch(hm: bedHm, afterMealOn: date)
            let _ = defaults
            report = try? LastMealToSleepEvaluator(db: services.db).evaluate(day: date, sleepOnsetEpochSec: sleepEpoch)
        }
    }

    private static func bedtimeEpoch(hm: String, afterMealOn day: ISODate) -> Int64? {
        let parts = hm.split(separator: ":").compactMap { Int($0) }
        let dp = day.string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, dp.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = dp[0]
        comps.month = dp[1]
        comps.day = dp[2]
        comps.hour = parts[0]
        comps.minute = parts[1]
        guard var dt = Calendar.current.date(from: comps) else { return nil }
        if parts[0] < 12 { dt = dt.addingTimeInterval(86_400) } // past-midnight bedtime belongs to tonight
        return Int64(dt.timeIntervalSince1970)
    }
}
