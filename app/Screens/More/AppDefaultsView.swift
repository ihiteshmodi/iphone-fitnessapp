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

/// Centralized `Defaults & Rules` screen reachable from MoreTabView.
struct AppDefaultsView: View {
    @EnvironmentObject private var services: Services
    @EnvironmentObject private var session: AppSession
    @EnvironmentObject private var whoop: WhoopBLEManager

    @State private var snap = AppDefaultsSnapshot()
    @State private var ageYearsInt = 30
    @State private var profileSex: LabSex = .male
    @State private var weightKgText = "75.0"
    @State private var syncedWaistSummary = "Log in Body → Measurements"
    @State private var oneMileMaxHrText = ""
    @State private var breakfastHm = "09:00"
    @State private var brunchHm = "12:30"
    @State private var lunchHm = "13:30"
    @State private var snackHm = "17:00"
    @State private var dinnerHm = "20:00"
    @State private var manualZonesText = ""
    @State private var warmupText = "50,70,85"
    @State private var hiitPresets: [HiitPreset] = []
    @State private var newPresetName = ""
    @State private var stepBreakdown: WhoopStepsEngine.StepBreakdown?
    @State private var deloadEnabled = false
    @State private var savedBanner = false
    @State private var errorMessage: String?

    private var computedZones: WhoopTrainingZones {
        let mileHr = Int(oneMileMaxHrText.trimmingCharacters(in: .whitespaces))
        let manual: [Int]? = {
            let parsed = manualZonesText.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            return parsed.count == 5 ? parsed : nil
        }()
        return WhoopReadinessAndStrainEngine.trainingZones(
            ageYears: Double(ageYearsInt),
            manualBounds: manual,
            oneMileMaxHr: mileHr
        )
    }

    var body: some View {
        Form {
            Section("Profile & Body Anchors (VO2, Energy & Zones)") {
                HStack {
                    Text("Name")
                    Spacer()
                    TextField("Name", text: $snap.userName)
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier("defaults-profile-name")
                }
                Stepper("Age: \(ageYearsInt) yrs (Tanaka HRmax \(Int((208.0 - 0.7 * Double(ageYearsInt)).rounded())))",
                        value: $ageYearsInt, in: 16...90)
                Picker("Sex", selection: $profileSex) {
                    Text("Male").tag(LabSex.male)
                    Text("Female").tag(LabSex.female)
                }
                HStack {
                    Text("Weight (kg)")
                    Spacer()
                    TextField("75.0", text: $weightKgText).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                Stepper("Height: \(Int(snap.heightCm.rounded())) cm", value: $snap.heightCm, in: 120...230, step: 1)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Waist (Nes VO2 · Auto-Synced)")
                        Spacer()
                        Text(syncedWaistSummary)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundColor(Theme.green)
                            .accessibilityIdentifier("defaults-auto-waist-label")
                    }
                    Text("Read-only from Body → Measurements (strictly site 'Waist', never 'Belly Button').")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)
                }
                Picker("Skin Temp Unit", selection: $snap.temperatureUnit) {
                    ForEach(TemperatureUnitPreference.allCases, id: \.rawValue) { u in
                        Text(u.label).tag(u)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Heart Rate Zones (Tanaka / 1-Mile / Karvonen / Manual)") {
                HStack {
                    Text("1-Mile Time Trial Max HR")
                    Spacer()
                    TextField("Optional BPM", text: $oneMileMaxHrText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                NavigationLink {
                    WhoopPrinciplesAndLimiterView()
                } label: {
                    Text("Run Live WHOOP Peak-HR Calibration Test ›")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.green)
                }
                .accessibilityIdentifier("defaults-open-maxhr-test")
                Stepper("Zone 2 floor: \(snap.zone2FloorBpm) bpm", value: $snap.zone2FloorBpm, in: 90...140, step: 2)
                Stepper("Zone 2 ceiling: \(snap.zone2CeilingBpm) bpm", value: $snap.zone2CeilingBpm, in: 120...165, step: 2)
                TextField("Manual Zone 1–5 bounds (e.g. 112,134,154,172,185)", text: $manualZonesText)
                let z = computedZones
                Text("Active (\(z.source)): Z1 ≥\(z.boundsBpm[0]) · Z2 ≥\(z.boundsBpm[1]) · Z3 ≥\(z.boundsBpm[2]) · Z4 ≥\(z.boundsBpm[3]) · Z5 ≥\(z.boundsBpm[4]) (max \(z.maxHrBpm) bpm)")
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.green)
            }

            Section("Gen5 Step Filter, Divisor & Category Breakdown") {
                Toggle("Strict walk/run gait filter (ignore class 0)", isOn: $snap.stepFilterGaitOnly)
                Stepper("stepTicksPerStep: \(String(format: "%.2f", snap.stepTicksPerStep))",
                        value: $snap.stepTicksPerStep, in: 0.5...30.0, step: 0.25)

                if let bd = stepBreakdown {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected steps by firmware activity_class:")
                            .font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text)
                        Text("• Class 1 (Walk): \(bd.walkSteps) · Class 2 (Run): \(bd.runSteps) · Class 0 rejected: \(bd.rejectedNonGaitTicks) ticks")
                            .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                        Text("By HR Zone: Z1 \(bd.zoneSteps[1]) · Z2 \(bd.zoneSteps[2]) · Z3 \(bd.zoneSteps[3]) · Z4 \(bd.zoneSteps[4]) · Z5 \(bd.zoneSteps[5])")
                            .font(.system(size: 11.5)).foregroundColor(Theme.green)
                    }
                    .padding(.vertical, 2)
                    .accessibilityIdentifier("defaults-step-breakdown")
                }
            }

            Section("HIIT Time & HR Presets") {
                ForEach(hiitPresets) { preset in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.name).font(.system(size: 13.5, weight: .semibold))
                            Text(preset.mode == .hrThreshold
                                 ? "HR Trigger: \(preset.highBpm) → \(preset.lowBpm) bpm ×\(preset.rounds)"
                                 : "Time: \(preset.workSec)s / \(preset.restSec)s ×\(preset.rounds)")
                                .font(.system(size: 11.5)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Button("Delete", role: .destructive) {
                            try? services.appDefaults.deleteHiitPreset(id: preset.id)
                            hiitPresets = (try? services.appDefaults.hiitPresets()) ?? []
                        }
                        .font(.system(size: 12))
                    }
                }
                HStack {
                    TextField("New preset (e.g. Norwegian 4×4)", text: $newPresetName)
                    Button("Add 4×4") {
                        let title = newPresetName.trimmingCharacters(in: .whitespaces).isEmpty ? "Norwegian 4×4" : newPresetName
                        let p = HiitPreset(id: UUID().uuidString, name: title, mode: .time, workSec: 240, restSec: 180, rounds: 4, highBpm: 168, lowBpm: 130, position: hiitPresets.count + 1)
                        try? services.appDefaults.upsertHiitPreset(p)
                        newPresetName = ""
                        hiitPresets = (try? services.appDefaults.hiitPresets()) ?? []
                    }
                    .font(.system(size: 12.5, weight: .bold))
                }
            }

            Section("Default Meal Times & Pre-Sleep Cutoffs") {
                HStack { Text("Breakfast"); Spacer(); TextField("HH:MM", text: $breakfastHm).multilineTextAlignment(.trailing) }
                HStack { Text("Brunch"); Spacer(); TextField("HH:MM", text: $brunchHm).multilineTextAlignment(.trailing) }
                HStack { Text("Lunch"); Spacer(); TextField("HH:MM", text: $lunchHm).multilineTextAlignment(.trailing) }
                HStack { Text("Snack"); Spacer(); TextField("HH:MM", text: $snackHm).multilineTextAlignment(.trailing) }
                HStack { Text("Dinner"); Spacer(); TextField("HH:MM", text: $dinnerHm).multilineTextAlignment(.trailing) }
                Stepper("Meal-to-sleep warn: \(Format.number(snap.mealToSleepWarnHours, maxDecimals: 1))h (opt 4–6h)",
                        value: $snap.mealToSleepWarnHours, in: 1.5...5.0, step: 0.5)
                Stepper("Caffeine max: \(Int(snap.caffeineMaxMg)) mg",
                        value: $snap.caffeineMaxMg, in: 0...400, step: 25)
                HStack {
                    Text("Caffeine cutoff (HH:MM)")
                    Spacer()
                    TextField("12:00", text: $snap.caffeineCutoffHm).multilineTextAlignment(.trailing)
                }
                Stepper("Alcohol cutoff: \(Format.number(snap.alcoholCutoffHours, maxDecimals: 1))h before bed",
                        value: $snap.alcoholCutoffHours, in: 1.0...6.0, step: 0.5)
                Stepper("Hard training cutoff: \(Format.number(snap.hardTrainingCutoffHours, maxDecimals: 1))h before bed",
                        value: $snap.hardTrainingCutoffHours, in: 1.5...5.0, step: 0.5)
            }

            Section("Dynamic Sleep Targets & Wake Anchor") {
                Stepper("Rest day: \(Format.number(snap.sleepRestHours, maxDecimals: 1))h",
                        value: $snap.sleepRestHours, in: 5.5...10.0, step: 0.25)
                Stepper("Lifting day: \(Format.number(snap.sleepLiftingHours, maxDecimals: 1))h",
                        value: $snap.sleepLiftingHours, in: 6.0...10.5, step: 0.25)
                Stepper("Endurance day: \(Format.number(snap.sleepEnduranceHours, maxDecimals: 1))h",
                        value: $snap.sleepEnduranceHours, in: 6.5...11.0, step: 0.25)
                HStack {
                    Text("Target daily wake (HH:MM)")
                    Spacer()
                    TextField("07:00", text: $snap.targetWakeHm).multilineTextAlignment(.trailing)
                }
            }

            Section("Warm-Up %, PR Clean-Form Rule & Deload") {
                HStack {
                    Text("Warm-up % sets")
                    Spacer()
                    TextField("50,70,85", text: $warmupText).multilineTextAlignment(.trailing)
                }
                Toggle("Require clean form for PR credit", isOn: $snap.requireCleanFormForPR)
                Stepper("Scheduled deload block: every \(snap.deloadScheduleWeeks) wks",
                        value: $snap.deloadScheduleWeeks, in: 3...8)
                Toggle("Active deload week ON", isOn: $deloadEnabled)
            }

            if savedBanner {
                Section {
                    Text("Saved Defaults & Rules ✓").foregroundColor(Theme.green)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Defaults & Rules")
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
        let today = services.clock.today()
        if let loaded = try? services.appDefaults.load() {
            snap = loaded
            breakfastHm = loaded.defaultMealTimes["Breakfast"] ?? "09:00"
            brunchHm = loaded.defaultMealTimes["Brunch"] ?? "12:30"
            lunchHm = loaded.defaultMealTimes["Lunch"] ?? "13:30"
            snackHm = loaded.defaultMealTimes["Snack"] ?? "17:00"
            dinnerHm = loaded.defaultMealTimes["Dinner"] ?? "20:00"
            oneMileMaxHrText = loaded.oneMileTrialMaxHr.map(String.init) ?? ""
            manualZonesText = loaded.manualHrZoneBounds?.map(String.init).joined(separator: ",") ?? ""
            warmupText = loaded.warmupPercents.map { "\(Int(($0 * 100.0).rounded()))" }.joined(separator: ",")
        }
        if let prefs = try? services.labSettings.load() {
            profileSex = prefs.sex
            if let bd = prefs.birthDate {
                ageYearsInt = max(16, min(90, Int((Double(today.days(since: bd)) / 365.25).rounded())))
            }
        }
        if let latestW = (try? services.logBody.recentWeights(limit: 1))?.first {
            weightKgText = Format.number(latestW.kg, maxDecimals: 1)
        }
        if let wc = try? WhoopLongevityEngines.latestWaistCm(from: services.db) {
            let waistDate = (try? services.db.query("""
                SELECT measured_on FROM body_measurements
                WHERE site = 'Waist' COLLATE NOCASE
                ORDER BY measured_on DESC, id DESC LIMIT 1
                """).first?.optionalText("measured_on")) ?? ""
            syncedWaistSummary = waistDate.isEmpty
                ? "\(Format.number(wc, maxDecimals: 1)) cm"
                : "\(Format.number(wc, maxDecimals: 1)) cm (\(waistDate))"
        } else {
            syncedWaistSummary = "Not logged (Body → Measurements)"
        }
        if let s = try? services.settings.load() {
            deloadEnabled = s.deload.enabled
        }
        var loadedPresets = (try? services.appDefaults.hiitPresets()) ?? []
        if loadedPresets.isEmpty {
            let def1 = HiitPreset(id: "norwegian-4x4", name: "Norwegian 4×4", mode: .time, workSec: 240, restSec: 180, rounds: 4, highBpm: 168, lowBpm: 130, position: 1)
            let def2 = HiitPreset(id: "hr-recovery", name: "HR 168/128 Trigger", mode: .hrThreshold, workSec: 60, restSec: 60, rounds: 6, highBpm: 168, lowBpm: 128, position: 2)
            try? services.appDefaults.upsertHiitPreset(def1)
            try? services.appDefaults.upsertHiitPreset(def2)
            loadedPresets = [def1, def2]
        }
        hiitPresets = loadedPresets

        if let db = whoop.db {
            let anchorDayStr = (try? db.query("SELECT MAX(date) AS md FROM metric_series").first?.optionalText("md")) ?? today.string
            let anchorDay = ISODate(anchorDayStr) ?? today
            if let bounds = WhoopSubstrateGates.calendarDayBounds(for: anchorDay) {
                stepBreakdown = try? WhoopStepsEngine.stepBreakdownFromDatabase(
                    whoopDb: db, startSec: bounds.dayStartSec, endSec: bounds.dayEndSec,
                    zones: computedZones, stepTicksPerStep: snap.stepTicksPerStep, filterGaitOnly: snap.stepFilterGaitOnly
                )
            }
        }
    }

    private func save() {
        do {
            let today = services.clock.today()
            var copy = snap
            copy.defaultMealTimes["Breakfast"] = breakfastHm
            copy.defaultMealTimes["Brunch"] = brunchHm
            copy.defaultMealTimes["Lunch"] = lunchHm
            copy.defaultMealTimes["Snack"] = snackHm
            copy.defaultMealTimes["Dinner"] = dinnerHm
            let mileTrimmed = oneMileMaxHrText.trimmingCharacters(in: .whitespaces)
            copy.oneMileTrialMaxHr = mileTrimmed.isEmpty ? nil : Int(mileTrimmed)
            let trimmedZones = manualZonesText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedZones.isEmpty {
                copy.manualHrZoneBounds = nil
            } else {
                copy.manualHrZoneBounds = trimmedZones.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            }
            let parsedWarmup = warmupText.split(separator: ",").compactMap { raw -> Double? in
                guard let v = Double(raw.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
                return v > 1.5 ? (v / 100.0) : v
            }
            if !parsedWarmup.isEmpty { copy.warmupPercents = parsedWarmup }

            try services.appDefaults.save(copy)

            // Sync Profile (Sex, BirthDate, Weight) & Deload toggle — Waist is read-only from Body → Measurements
            try? services.labSettings.setSex(profileSex)
            try? services.labSettings.setBirthDate(today.adding(days: -Int((Double(ageYearsInt) * 365.25).rounded())))
            if let wKg = Format.decimal(weightKgText), wKg > 20 {
                _ = try? services.logBody.logWeight(kg: wKg, on: today)
            }
            try? services.settings.setDeloadEnabled(deloadEnabled)

            savedBanner = true
            session.didChange()
        } catch {
            errorMessage = (error as? ValidationError)?.message ?? error.localizedDescription
        }
    }
}
