import FitnessCore
import SwiftUI

/// 7-Day Silent Haptic Alarms (`0x42` / `0x45` with RTC drift compensation) + `stepTicksPerStep` divisor inside WhoopBandView.
struct WhoopSilentAlarmsSection: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var whoop: WhoopBLEManager
    @EnvironmentObject private var session: AppSession

    @State private var schedules: [WhoopAlarmDaySchedule] = []
    @State private var stepDivisor: Double = 1.0
    @State private var editingDay: WhoopAlarmDaySchedule?
    @State private var syncBanner: String?

    private static let weekdayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel("7-day silent haptic alarms (0x42 / 0x43 / 0x45)")
                    Spacer()
                    Pill(text: "Exact + Smart", tone: .green)
                }
                Text("Tap any day's wake time to switch between Normal (Exact) wake and Smart Wake (light-sleep window).")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.muted)

                ForEach(schedules) { item in
                    HStack(spacing: 8) {
                        Text(Self.weekdayLabels[max(0, min(6, item.weekday - 1))])
                            .font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                            .frame(width: 40, alignment: .leading)
                        Button {
                            editingDay = item
                        } label: {
                            HStack(spacing: 6) {
                                Text(item.formattedHm)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(item.enabled ? Theme.green : Theme.muted)
                                Pill(
                                    text: item.mode == .smart ? "Smart \(item.smartWindowMinutes)m" : "Normal",
                                    tone: item.mode == .smart ? .amber : .grey
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("whoop-alarm-day-\(item.weekday)")
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { item.enabled },
                            set: { on in
                                var copy = item
                                copy.enabled = on
                                try? services.appDefaults.upsertAlarmSchedule(copy)
                                reload()
                            }
                        ))
                        .labelsHidden()
                        .tint(Theme.green)
                    }
                    .padding(.vertical, 2)
                }

                Button("Sync next alarm to strap (0x42)") {
                    pushNextAlarmToStrap()
                }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("whoop-push-alarm-button")

                HStack(spacing: 8) {
                    Button("Read (0x43)") {
                        _ = whoop.readStrapAlarm()
                        syncBanner = whoop.lastAlarmStatusText
                    }
                    .buttonStyle(CompactButtonStyle(ghost: true))
                    .accessibilityIdentifier("whoop-read-alarm-button")

                    Button("Disable (0x45)") {
                        _ = whoop.disableStrapAlarm()
                        syncBanner = whoop.lastAlarmStatusText
                    }
                    .buttonStyle(CompactButtonStyle(ghost: true))
                    .accessibilityIdentifier("whoop-disable-alarm-button")

                    Spacer(minLength: 4)

                    Button("Test Buzz") {
                        let sent = whoop.triggerVibrationTest(loops: 1)
                        syncBanner = sent ? "Sent wrist haptic buzz test!" : "Band offline — connect strap to test buzz."
                    }
                    .buttonStyle(CompactButtonStyle())
                    .accessibilityIdentifier("whoop-alarm-test-buzz-button")
                }

                if let status = whoop.lastAlarmStatusText ?? syncBanner {
                    Text(status).font(.system(size: 12)).foregroundColor(Theme.green)
                }
            }
            .card()
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("whoop-silent-alarms-card")

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Gen5 walk/run step filter (no HealthKit)")
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ticks per step").font(.system(size: 14, weight: .semibold)).foregroundColor(Theme.text)
                        Text("Counts strictly activity_class 1 (walk) & 2 (run)")
                            .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                    }
                    Spacer()
                    HStack(spacing: 10) {
                        Button("−") { updateDivisor(max(0.5, stepDivisor - 0.25)) }.foregroundColor(Theme.green)
                        Text(String(format: "%.2f", stepDivisor)).font(.system(size: 14, weight: .bold)).foregroundColor(Theme.text)
                        Button("+") { updateDivisor(min(30.0, stepDivisor + 0.25)) }.foregroundColor(Theme.green)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.card2).clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
            .card()
            .accessibilityIdentifier("whoop-step-divisor-card")
        }
        .onAppear(perform: reload)
        .sheet(item: $editingDay, onDismiss: reload) { item in
            AlarmDayEditorSheet(schedule: item, store: services.appDefaults)
        }
    }

    private func reload() {
        var loaded = (try? services.appDefaults.alarmSchedules()) ?? []
        if loaded.count < 7 {
            for wd in 1...7 where !loaded.contains(where: { $0.weekday == wd }) {
                let def = WhoopAlarmDaySchedule(
                    weekday: wd,
                    hour: 7,
                    minute: 0,
                    enabled: wd <= 5,
                    mode: wd <= 5 ? .exact : .smart,
                    smartWindowMinutes: wd <= 5 ? 0 : 15
                )
                try? services.appDefaults.upsertAlarmSchedule(def)
                loaded.append(def)
            }
            loaded.sort { $0.weekday < $1.weekday }
        }
        schedules = loaded
        stepDivisor = (try? services.appDefaults.load().stepTicksPerStep) ?? 1.0
    }

    private func updateDivisor(_ v: Double) {
        stepDivisor = v
        if var snap = try? services.appDefaults.load() {
            snap.stepTicksPerStep = v
            try? services.appDefaults.save(snap)
            session.didChange()
        }
    }

    private func pushNextAlarmToStrap() {
        guard let enabledFirst = schedules.first(where: \.enabled) else {
            _ = whoop.disableStrapAlarm()
            syncBanner = "All alarms off — sent 0x45 DISABLE_ALARM."
            return
        }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = enabledFirst.hour
        comps.minute = enabledFirst.minute
        comps.second = 0
        var target = Calendar.current.date(from: comps) ?? Date().addingTimeInterval(28_800)
        if target <= Date() { target = target.addingTimeInterval(86_400) }
        if let frame = try? WhoopSilentAlarmCommands.buildSetAlarmFrame(
            wallAlarmEpochSec: Int64(target.timeIntervalSince1970),
            strapClockDriftSec: whoop.strapClockDriftSec,
            profile: whoop.activeBandProfile
        ) {
            let sent = whoop.sendRawCommandFrame(frame)
            if enabledFirst.mode == .smart,
               let pollFrame = try? WhoopSilentAlarmCommands.buildSmartWakePollFrame(
                   smartWindowMinutes: enabledFirst.smartWindowMinutes,
                   profile: whoop.activeBandProfile
               ) {
                _ = whoop.sendRawCommandFrame(pollFrame)
            }
            let modeLabel = enabledFirst.mode == .smart ? "Smart \(enabledFirst.smartWindowMinutes)m" : "Normal Exact"
            syncBanner = sent
                ? "Sent 0x42 \(modeLabel) alarm (\(enabledFirst.formattedHm), RTC drift \(Int(whoop.strapClockDriftSec.rounded()))s)."
                : "Saved \(modeLabel) schedule (\(enabledFirst.formattedHm)); connect strap to push 0x42."
        }
    }
}

struct AlarmDayEditorSheet: View {
    let schedule: WhoopAlarmDaySchedule
    let store: AppDefaultsStore
    @Environment(\.dismiss) private var dismiss
    @State private var timeDate = Date()
    @State private var mode: WhoopAlarmMode = .exact
    @State private var smartWindow = 15

    var body: some View {
        NavigationStack {
            Form {
                Section("Alarm Mode (OpenStrap Edge compatible)") {
                    Picker("Mode", selection: $mode) {
                        ForEach(WhoopAlarmMode.allCases, id: \.rawValue) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("whoop-alarm-mode-picker")

                    if mode == .exact {
                        Text("Normal (Exact): buzzes strictly at your target wake time in the strap's RTC clock frame.")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                    } else {
                        Text("Smart Wake: arms 61s high-frequency sync (0x60) inside your window to wake you in light sleep before the latest time.")
                            .font(.system(size: 12)).foregroundColor(Theme.muted)
                    }
                }

                Section(mode == .smart ? "Latest wake time & window" : "Exact wake time") {
                    DatePicker("Wake time", selection: $timeDate, displayedComponents: .hourAndMinute)
                    if mode == .smart {
                        Stepper("Smart window: \(smartWindow) min", value: $smartWindow, in: 5...60, step: 5)
                            .accessibilityIdentifier("whoop-alarm-smart-window-stepper")
                    }
                }
            }
            .navigationTitle("Edit Alarm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: timeDate)
                        try? store.upsertAlarmSchedule(WhoopAlarmDaySchedule(
                            weekday: schedule.weekday,
                            hour: comps.hour ?? 7,
                            minute: comps.minute ?? 0,
                            enabled: schedule.enabled,
                            mode: mode,
                            smartWindowMinutes: mode == .smart ? max(5, smartWindow) : 0
                        ))
                        dismiss()
                    }
                    .accessibilityIdentifier("whoop-alarm-save-button")
                }
            }
            .onAppear {
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = schedule.hour
                comps.minute = schedule.minute
                timeDate = Calendar.current.date(from: comps) ?? Date()
                mode = schedule.mode
                smartWindow = schedule.smartWindowMinutes > 0 ? schedule.smartWindowMinutes : 15
            }
        }
    }
}

/// Centralized AppDefaultsStore editor screen reachable from MoreTabView.
struct AppDefaultsView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @State private var snap = AppDefaultsSnapshot()
    @State private var breakfastHm = "09:00"
    @State private var brunchHm = "12:30"
    @State private var lunchHm = "13:30"
    @State private var dinnerHm = "20:00"
    @State private var manualZonesText = ""
    @State private var savedBanner = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Default meal times (retroactive guard)") {
                HStack { Text("Breakfast"); Spacer(); TextField("HH:MM", text: $breakfastHm).multilineTextAlignment(.trailing) }
                HStack { Text("Brunch"); Spacer(); TextField("HH:MM", text: $brunchHm).multilineTextAlignment(.trailing) }
                HStack { Text("Lunch"); Spacer(); TextField("HH:MM", text: $lunchHm).multilineTextAlignment(.trailing) }
                HStack { Text("Dinner"); Spacer(); TextField("HH:MM", text: $dinnerHm).multilineTextAlignment(.trailing) }
            }

            Section("Pre-sleep & stimulant cutoffs") {
                Stepper("Meal-to-sleep warn: \(Format.number(snap.mealToSleepWarnHours, maxDecimals: 1))h",
                        value: $snap.mealToSleepWarnHours, in: 1.5...5.0, step: 0.5)
                Stepper("Caffeine max: \(Int(snap.caffeineMaxMg)) mg",
                        value: $snap.caffeineMaxMg, in: 0...400, step: 25)
                HStack {
                    Text("Caffeine cutoff (HH:MM)")
                    Spacer()
                    TextField("12:00", text: $snap.caffeineCutoffHm).multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("Target daily wake (HH:MM)")
                    Spacer()
                    TextField("07:00", text: $snap.targetWakeHm).multilineTextAlignment(.trailing)
                }
            }

            Section("Dynamic sleep need (hours)") {
                Stepper("Rest day: \(Format.number(snap.sleepRestHours, maxDecimals: 1))h",
                        value: $snap.sleepRestHours, in: 5.5...10.0, step: 0.25)
                Stepper("Lifting day: \(Format.number(snap.sleepLiftingHours, maxDecimals: 1))h",
                        value: $snap.sleepLiftingHours, in: 6.0...10.5, step: 0.25)
                Stepper("Endurance day: \(Format.number(snap.sleepEnduranceHours, maxDecimals: 1))h",
                        value: $snap.sleepEnduranceHours, in: 6.5...11.0, step: 0.25)
            }

            Section("Heart rate zones") {
                Stepper("Zone 2 floor: \(snap.zone2FloorBpm) bpm", value: $snap.zone2FloorBpm, in: 90...140, step: 2)
                Stepper("Zone 2 ceiling: \(snap.zone2CeilingBpm) bpm", value: $snap.zone2CeilingBpm, in: 120...165, step: 2)
                TextField("Manual 5 bounds (e.g. 112,134,154,172,185)", text: $manualZonesText)
            }

            if savedBanner {
                Section {
                    Text("Saved defaults ✓").foregroundColor(Theme.green)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Defaults & Cutoffs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .accessibilityIdentifier("app-defaults-save")
            }
        }
        .onAppear(perform: load)
        .errorAlert($errorMessage)
    }

    private func load() {
        guard let loaded = try? services.appDefaults.load() else { return }
        snap = loaded
        breakfastHm = loaded.defaultMealTimes["Breakfast"] ?? "09:00"
        brunchHm = loaded.defaultMealTimes["Brunch"] ?? "12:30"
        lunchHm = loaded.defaultMealTimes["Lunch"] ?? "13:30"
        dinnerHm = loaded.defaultMealTimes["Dinner"] ?? "20:00"
        manualZonesText = loaded.manualHrZoneBounds?.map(String.init).joined(separator: ",") ?? ""
    }

    private func save() {
        do {
            var copy = snap
            copy.defaultMealTimes["Breakfast"] = breakfastHm
            copy.defaultMealTimes["Brunch"] = brunchHm
            copy.defaultMealTimes["Lunch"] = lunchHm
            copy.defaultMealTimes["Dinner"] = dinnerHm
            let trimmedZones = manualZonesText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedZones.isEmpty {
                copy.manualHrZoneBounds = nil
            } else {
                copy.manualHrZoneBounds = trimmedZones.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            }
            try services.appDefaults.save(copy)
            savedBanner = true
            session.didChange()
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }
}
