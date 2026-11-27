import Foundation

public enum WhoopCoachingMode: String, CaseIterable, Codable, Equatable, Sendable {
    case generalHealth = "general_health"
    case maximizingVo2Max = "maximizing_vo2_max"
    case maximizingHrv = "maximizing_hrv"
    case reducingRhr = "reducing_rhr"

    public var title: String {
        switch self {
        case .generalHealth: return "General Health"
        case .maximizingVo2Max: return "Maximizing VO2 Max"
        case .maximizingHrv: return "Maximizing HRV"
        case .reducingRhr: return "Reducing RHR"
        }
    }
}

public enum Vo2LimiterMode: String, CaseIterable, Codable, Equatable, Sendable {
    case aerobicPower = "aerobic_power"
    case anaerobicBattery = "anaerobic_battery"
    case processingPower = "processing_power"

    public var title: String {
        switch self {
        case .aerobicPower: return "Aerobic Power (80/0/20)"
        case .anaerobicBattery: return "Anaerobic Battery (60/30/10)"
        case .processingPower: return "Processing Power (75/15/10)"
        }
    }
}

public enum HiitTriggerMode: String, CaseIterable, Codable, Equatable, Sendable {
    case time = "time"
    case hrThreshold = "hr_threshold"
}

public struct HiitPreset: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var mode: HiitTriggerMode
    public var workSec: Int
    public var restSec: Int
    public var rounds: Int
    public var highBpm: Int
    public var lowBpm: Int
    public var position: Int

    public init(id: String, name: String, mode: HiitTriggerMode, workSec: Int = 30, restSec: Int = 90,
                rounds: Int = 8, highBpm: Int = 170, lowBpm: Int = 130, position: Int = 1) {
        self.id = id
        self.name = name
        self.mode = mode
        self.workSec = max(5, workSec)
        self.restSec = max(5, restSec)
        self.rounds = max(1, rounds)
        self.highBpm = max(60, highBpm)
        self.lowBpm = max(40, lowBpm)
        self.position = position
    }
}

public enum WhoopAlarmMode: String, CaseIterable, Codable, Equatable, Sendable {
    case exact = "exact"
    case smart = "smart"

    public var title: String {
        switch self {
        case .exact: return "Normal (Exact)"
        case .smart: return "Smart Wake"
        }
    }
}

public struct WhoopAlarmDaySchedule: Identifiable, Codable, Equatable, Sendable {
    public var id: Int { weekday }
    /// ISO weekday: 1 = Monday ... 7 = Sunday.
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public var enabled: Bool
    public var smartWindowMinutes: Int

    public var mode: WhoopAlarmMode {
        get { smartWindowMinutes > 0 ? .smart : .exact }
        set {
            switch newValue {
            case .exact:
                smartWindowMinutes = 0
            case .smart:
                if smartWindowMinutes <= 0 { smartWindowMinutes = 15 }
            }
        }
    }

    public init(weekday: Int, hour: Int, minute: Int, enabled: Bool, mode: WhoopAlarmMode? = nil, smartWindowMinutes: Int = 0) {
        self.weekday = min(7, max(1, weekday))
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.enabled = enabled
        let clampedWindow = min(60, max(0, smartWindowMinutes))
        if let mode {
            switch mode {
            case .exact: self.smartWindowMinutes = 0
            case .smart: self.smartWindowMinutes = clampedWindow > 0 ? clampedWindow : 15
            }
        } else {
            self.smartWindowMinutes = clampedWindow
        }
    }

    public var formattedHm: String { String(format: "%02d:%02d", hour, minute) }
}

/// Converts phone wall-clock alarm targets into the WHOOP strap's own RTC frame (`strapEpoch = wallEpoch - driftSec`)
/// and builds canonical `0x42` (`SET_ALARM_TIME`), `0x43` (`GET_ALARM_TIME`), `0x45` (`DISABLE_ALARM`), and Smart-Wake `0x60` packets.
public enum WhoopSilentAlarmCommands {
    public static func strapAlarmEpochMs(wallAlarmEpochSec: Int64, strapClockDriftSec: Double) -> Int64 {
        let driftRoundedSec = strapClockDriftSec.isFinite ? Int64(strapClockDriftSec.rounded()) : 0
        return max(0, (wallAlarmEpochSec - driftRoundedSec) * 1_000)
    }

    public static func buildSetAlarmFrame(
        seq: UInt8 = 1,
        wallAlarmEpochSec: Int64,
        strapClockDriftSec: Double = 0,
        slot: UInt8 = 1,
        profile: WhoopBandProfile = .gen5
    ) throws -> [UInt8] {
        let strapMs = strapAlarmEpochMs(wallAlarmEpochSec: wallAlarmEpochSec, strapClockDriftSec: strapClockDriftSec)
        if profile.isGen5 {
            return try WhoopCommands.cmdSetAlarmGen5(seq: seq, epochMs: strapMs, slot: slot)
        }
        return WhoopCommands.cmdSetAlarmGen4Rev1(seq: seq, epochMs: strapMs)
    }

    /// Spec §2.4: Gen5 `getAlarmTime` (`0x43`) uses `[0x04, id=1]`, Gen4 uses `[0x01]`.
    public static func buildGetAlarmFrame(seq: UInt8 = 1, slot: UInt8 = 1, profile: WhoopBandProfile = .gen5) -> [UInt8] {
        let payload: [UInt8] = profile.isGen5 ? [0x04, slot] : [0x01]
        return WhoopCommands.buildCommand(seq: seq, opcode: WhoopCmd.getAlarmTime, payload: payload, profile: profile)
    }

    public static func buildDisableAlarmFrame(seq: UInt8 = 1, slot: UInt8? = nil, profile: WhoopBandProfile = .gen5) -> [UInt8] {
        WhoopCommands.cmdDisableAlarm(seq: seq, slot: slot, profile: profile)
    }

    /// Spec §2.3.5: Smart-wake window arms `ENTER_HIGH_FREQ_SYNC (0x60)` at `intervalSeconds = 61 s` (Gen5 rejects `<= 60 s`)
    /// so the phone monitors light sleep staging inside `[wake - smartWindow, wake]` and triggers wrist haptics at light sleep!
    public static func buildSmartWakePollFrame(seq: UInt8 = 2, smartWindowMinutes: Int, profile: WhoopBandProfile = .gen5) throws -> [UInt8]? {
        guard smartWindowMinutes > 0 else { return nil }
        let durSec = min(7200, max(300, smartWindowMinutes * 60 + 600))
        return try WhoopCommands.enterHighFreqSync(seq: seq, intervalSeconds: 61, durationSeconds: durSec, profile: profile)
    }
}

public struct AppDefaultsSnapshot: Equatable, Sendable {
    public var defaultMealTimes: [String: String]
    public var fallbackMealTimeHm: String
    public var mealToSleepWarnHours: Double
    public var mealToSleepOptimalMinHours: Double
    public var mealToSleepOptimalMaxHours: Double
    public var caffeineMaxMg: Double
    public var caffeineCutoffHm: String
    public var alcoholCutoffHours: Double
    public var hardTrainingCutoffHours: Double
    public var oneMileTrialMaxHr: Int?
    public var manualHrZoneBounds: [Int]?
    public var zone2FloorBpm: Int
    public var zone2CeilingBpm: Int
    public var whoopCoachingMode: WhoopCoachingMode
    public var vo2LimiterMode: Vo2LimiterMode
    public var stepTicksPerStep: Double
    public var sleepRestHours: Double
    public var sleepLiftingHours: Double
    public var sleepEnduranceHours: Double
    public var targetWakeHm: String
    public var warmupPercents: [Double]
    public var requireCleanFormForPR: Bool
    public var deloadScheduleWeeks: Int

    public init(
        defaultMealTimes: [String: String] = [
            "Breakfast": "09:00",
            "Brunch": "12:30",
            "Lunch": "13:30",
            "Snack": "17:00",
            "Pre-Workout": "17:30",
            "Post-Workout": "19:30",
            "Dinner": "20:00",
        ],
        fallbackMealTimeHm: String = "19:30",
        mealToSleepWarnHours: Double = 3.0,
        mealToSleepOptimalMinHours: Double = 4.0,
        mealToSleepOptimalMaxHours: Double = 6.0,
        caffeineMaxMg: Double = 100.0,
        caffeineCutoffHm: String = "12:00",
        alcoholCutoffHours: Double = 3.0,
        hardTrainingCutoffHours: Double = 2.5,
        oneMileTrialMaxHr: Int? = nil,
        manualHrZoneBounds: [Int]? = nil,
        zone2FloorBpm: Int = 110,
        zone2CeilingBpm: Int = 140,
        whoopCoachingMode: WhoopCoachingMode = .generalHealth,
        vo2LimiterMode: Vo2LimiterMode = .aerobicPower,
        stepTicksPerStep: Double = 1.0,
        sleepRestHours: Double = 7.0,
        sleepLiftingHours: Double = 7.5,
        sleepEnduranceHours: Double = 8.0,
        targetWakeHm: String = "07:00",
        warmupPercents: [Double] = [0.50, 0.70, 0.85],
        requireCleanFormForPR: Bool = true,
        deloadScheduleWeeks: Int = 5
    ) {
        self.defaultMealTimes = defaultMealTimes
        self.fallbackMealTimeHm = fallbackMealTimeHm
        self.mealToSleepWarnHours = mealToSleepWarnHours
        self.mealToSleepOptimalMinHours = mealToSleepOptimalMinHours
        self.mealToSleepOptimalMaxHours = mealToSleepOptimalMaxHours
        self.caffeineMaxMg = caffeineMaxMg
        self.caffeineCutoffHm = caffeineCutoffHm
        self.alcoholCutoffHours = alcoholCutoffHours
        self.hardTrainingCutoffHours = hardTrainingCutoffHours
        self.oneMileTrialMaxHr = oneMileTrialMaxHr
        self.manualHrZoneBounds = manualHrZoneBounds
        self.zone2FloorBpm = zone2FloorBpm
        self.zone2CeilingBpm = zone2CeilingBpm
        self.whoopCoachingMode = whoopCoachingMode
        self.vo2LimiterMode = vo2LimiterMode
        self.stepTicksPerStep = min(30.0, max(0.5, stepTicksPerStep))
        self.sleepRestHours = sleepRestHours
        self.sleepLiftingHours = sleepLiftingHours
        self.sleepEnduranceHours = sleepEnduranceHours
        self.targetWakeHm = targetWakeHm
        self.warmupPercents = warmupPercents
        self.requireCleanFormForPR = requireCleanFormForPR
        self.deloadScheduleWeeks = max(3, deloadScheduleWeeks)
    }
}

/// Single editable persistence store for all training, diet cutoff, WHOOP coaching, HIIT preset, and silent alarm defaults.
public final class AppDefaultsStore {
    private let db: Database
    private static let mealPrefix = "app_default.meal_time."

    public init(_ db: Database) {
        self.db = db
    }

    public static func validHm(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ":")
        guard parts.count == 2,
              let h = Int(parts[0]), (0...23).contains(h),
              let m = Int(parts[1]), (0...59).contains(m) else {
            throw ValidationError("Time must be HH:MM (00:00–23:59)")
        }
        return String(format: "%02d:%02d", h, m)
    }

    public func load() throws -> AppDefaultsSnapshot {
        let rows = Dictionary(uniqueKeysWithValues: try db.query("SELECT key, value FROM settings WHERE key LIKE 'app_default.%'")
            .map { ($0.text("key"), $0.text("value")) })

        var snap = AppDefaultsSnapshot()
        for (k, v) in rows where k.hasPrefix(Self.mealPrefix) {
            let meal = String(k.dropFirst(Self.mealPrefix.count))
            if !meal.isEmpty { snap.defaultMealTimes[meal] = v }
        }
        if let v = rows["app_default.fallback_meal_hm"] { snap.fallbackMealTimeHm = v }
        if let v = rows["app_default.meal_sleep_warn_h"].flatMap(Double.init) { snap.mealToSleepWarnHours = v }
        if let v = rows["app_default.meal_sleep_opt_min_h"].flatMap(Double.init) { snap.mealToSleepOptimalMinHours = v }
        if let v = rows["app_default.meal_sleep_opt_max_h"].flatMap(Double.init) { snap.mealToSleepOptimalMaxHours = v }
        if let v = rows["app_default.caffeine_max_mg"].flatMap(Double.init) { snap.caffeineMaxMg = v }
        if let v = rows["app_default.caffeine_cutoff_hm"] { snap.caffeineCutoffHm = v }
        if let v = rows["app_default.alcohol_cutoff_h"].flatMap(Double.init) { snap.alcoholCutoffHours = v }
        if let v = rows["app_default.hard_training_cutoff_h"].flatMap(Double.init) { snap.hardTrainingCutoffHours = v }
        if let v = rows["app_default.one_mile_max_hr"].flatMap(Int.init), v > 0 { snap.oneMileTrialMaxHr = v }
        if let v = rows["app_default.manual_hr_zones"] {
            let parsed = v.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            if parsed.count == 5 { snap.manualHrZoneBounds = parsed }
        }
        if let v = rows["app_default.zone2_floor_bpm"].flatMap(Int.init) { snap.zone2FloorBpm = v }
        if let v = rows["app_default.zone2_ceiling_bpm"].flatMap(Int.init) { snap.zone2CeilingBpm = v }
        if let v = rows["app_default.whoop_coaching_mode"].flatMap(WhoopCoachingMode.init(rawValue:)) { snap.whoopCoachingMode = v }
        if let v = rows["app_default.vo2_limiter_mode"].flatMap(Vo2LimiterMode.init(rawValue:)) { snap.vo2LimiterMode = v }
        if let v = rows["app_default.step_ticks_per_step"].flatMap(Double.init), v.isFinite {
            snap.stepTicksPerStep = min(30.0, max(0.5, v))
        }
        if let v = rows["app_default.sleep_rest_h"].flatMap(Double.init) { snap.sleepRestHours = v }
        if let v = rows["app_default.sleep_lifting_h"].flatMap(Double.init) { snap.sleepLiftingHours = v }
        if let v = rows["app_default.sleep_endurance_h"].flatMap(Double.init) { snap.sleepEnduranceHours = v }
        if let v = rows["app_default.target_wake_hm"] { snap.targetWakeHm = v }
        if let v = rows["app_default.warmup_percents"] {
            let parsed = v.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if !parsed.isEmpty { snap.warmupPercents = parsed }
        }
        if let v = rows["app_default.require_clean_form_pr"] { snap.requireCleanFormForPR = (v == "1") }
        if let v = rows["app_default.deload_schedule_weeks"].flatMap(Int.init) { snap.deloadScheduleWeeks = max(3, v) }
        return snap
    }

    public func save(_ snap: AppDefaultsSnapshot) throws {
        let fallbackHm = try Self.validHm(snap.fallbackMealTimeHm)
        let cafHm = try Self.validHm(snap.caffeineCutoffHm)
        let wakeHm = try Self.validHm(snap.targetWakeHm)
        if let bounds = snap.manualHrZoneBounds {
            guard bounds.count == 5 else { throw ValidationError("Manual HR zones require 5 BPM bounds") }
            for i in 0..<bounds.count {
                guard bounds[i] >= 30 && bounds[i] <= 240 else { throw ValidationError("HR zone bound out of range") }
                if i > 0, bounds[i] <= bounds[i - 1] {
                    throw ValidationError("Manual HR zone bounds must be strictly ascending")
                }
            }
        }
        let clampedTicks = min(30.0, max(0.5, snap.stepTicksPerStep))

        try db.transaction {
            try db.execute("DELETE FROM settings WHERE key LIKE 'app_default.%'")
            for (meal, hm) in snap.defaultMealTimes {
                let valid = try Self.validHm(hm)
                try put("\(Self.mealPrefix)\(meal)", valid)
            }
            try put("app_default.fallback_meal_hm", fallbackHm)
            try put("app_default.meal_sleep_warn_h", String(snap.mealToSleepWarnHours))
            try put("app_default.meal_sleep_opt_min_h", String(snap.mealToSleepOptimalMinHours))
            try put("app_default.meal_sleep_opt_max_h", String(snap.mealToSleepOptimalMaxHours))
            try put("app_default.caffeine_max_mg", String(snap.caffeineMaxMg))
            try put("app_default.caffeine_cutoff_hm", cafHm)
            try put("app_default.alcohol_cutoff_h", String(snap.alcoholCutoffHours))
            try put("app_default.hard_training_cutoff_h", String(snap.hardTrainingCutoffHours))
            if let maxHr = snap.oneMileTrialMaxHr, maxHr > 0 {
                try put("app_default.one_mile_max_hr", String(maxHr))
            }
            if let bounds = snap.manualHrZoneBounds {
                try put("app_default.manual_hr_zones", bounds.map(String.init).joined(separator: ","))
            }
            try put("app_default.zone2_floor_bpm", String(snap.zone2FloorBpm))
            try put("app_default.zone2_ceiling_bpm", String(snap.zone2CeilingBpm))
            try put("app_default.whoop_coaching_mode", snap.whoopCoachingMode.rawValue)
            try put("app_default.vo2_limiter_mode", snap.vo2LimiterMode.rawValue)
            try put("app_default.step_ticks_per_step", String(clampedTicks))
            try put("app_default.sleep_rest_h", String(snap.sleepRestHours))
            try put("app_default.sleep_lifting_h", String(snap.sleepLiftingHours))
            try put("app_default.sleep_endurance_h", String(snap.sleepEnduranceHours))
            try put("app_default.target_wake_hm", wakeHm)
            try put("app_default.warmup_percents", snap.warmupPercents.map { String($0) }.joined(separator: ","))
            try put("app_default.require_clean_form_pr", snap.requireCleanFormForPR ? "1" : "0")
            try put("app_default.deload_schedule_weeks", String(max(3, snap.deloadScheduleWeeks)))
        }
    }

    public func defaultMealTime(forMeal meal: String) throws -> String {
        let snap = try load()
        if let exact = snap.defaultMealTimes[meal] { return exact }
        if let ci = snap.defaultMealTimes.first(where: { $0.key.caseInsensitiveCompare(meal) == .orderedSame })?.value {
            return ci
        }
        let lower = meal.lowercased()
        if lower.contains("breakfast") || lower.contains("morning") { return "09:00" }
        if lower.contains("brunch") { return "12:30" }
        if lower.contains("lunch") || lower.contains("meal 1") { return "13:30" }
        if lower.contains("snack") || lower.contains("pre") { return "17:00" }
        if lower.contains("dinner") || lower.contains("supper") || lower.contains("night") { return "20:00" }
        return snap.fallbackMealTimeHm
    }

    public func setDefaultMealTime(_ hm: String, forMeal meal: String) throws {
        let valid = try Self.validHm(hm)
        let trimmedMeal = meal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMeal.isEmpty else { throw ValidationError("Meal name cannot be empty") }
        try put("\(Self.mealPrefix)\(trimmedMeal)", valid)
    }

    // MARK: HIIT Presets CRUD

    public func hiitPresets() throws -> [HiitPreset] {
        try db.query("SELECT * FROM hiit_presets ORDER BY position ASC, name ASC").map { row in
            HiitPreset(
                id: row.text("id"),
                name: row.text("name"),
                mode: HiitTriggerMode(rawValue: row.text("mode")) ?? .time,
                workSec: row.int("work_sec"),
                restSec: row.int("rest_sec"),
                rounds: row.int("rounds"),
                highBpm: row.int("high_bpm"),
                lowBpm: row.int("low_bpm"),
                position: row.int("position")
            )
        }
    }

    public func upsertHiitPreset(_ preset: HiitPreset) throws {
        let cleanName = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ValidationError("Preset name cannot be empty") }
        guard preset.highBpm > preset.lowBpm else {
            throw ValidationError("Upper HR threshold must exceed lower recovery threshold")
        }
        try db.execute("""
            INSERT INTO hiit_presets (id, name, mode, work_sec, rest_sec, rounds, high_bpm, low_bpm, position)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                mode = excluded.mode,
                work_sec = excluded.work_sec,
                rest_sec = excluded.rest_sec,
                rounds = excluded.rounds,
                high_bpm = excluded.high_bpm,
                low_bpm = excluded.low_bpm,
                position = excluded.position
            """, [
                .text(preset.id), .text(cleanName), .text(preset.mode.rawValue),
                .int(Int64(max(5, preset.workSec))), .int(Int64(max(5, preset.restSec))),
                .int(Int64(max(1, preset.rounds))), .int(Int64(preset.highBpm)),
                .int(Int64(preset.lowBpm)), .int(Int64(preset.position)),
            ])
    }

    public func deleteHiitPreset(id: String) throws {
        try db.execute("DELETE FROM hiit_presets WHERE id = ?", [.text(id)])
    }

    // MARK: 7-Day Silent Alarms CRUD

    public func alarmSchedules() throws -> [WhoopAlarmDaySchedule] {
        try db.query("SELECT * FROM whoop_alarm_schedules ORDER BY weekday ASC").map { row in
            WhoopAlarmDaySchedule(
                weekday: row.int("weekday"),
                hour: row.int("hour"),
                minute: row.int("minute"),
                enabled: row.int("enabled") == 1,
                smartWindowMinutes: row.int("smart_window_minutes")
            )
        }
    }

    public func upsertAlarmSchedule(_ alarm: WhoopAlarmDaySchedule) throws {
        guard (1...7).contains(alarm.weekday) else { throw ValidationError("Weekday must be 1 (Mon) .. 7 (Sun)") }
        try db.execute("""
            INSERT INTO whoop_alarm_schedules (weekday, hour, minute, enabled, smart_window_minutes)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(weekday) DO UPDATE SET
                hour = excluded.hour,
                minute = excluded.minute,
                enabled = excluded.enabled,
                smart_window_minutes = excluded.smart_window_minutes
            """, [
                .int(Int64(alarm.weekday)),
                .int(Int64(alarm.hour)),
                .int(Int64(alarm.minute)),
                .int(alarm.enabled ? 1 : 0),
                .int(Int64(alarm.smartWindowMinutes)),
            ])
    }

    public func deleteAlarmSchedule(weekday: Int) throws {
        try db.execute("DELETE FROM whoop_alarm_schedules WHERE weekday = ?", [.int(Int64(weekday))])
    }

    private func put(_ key: String, _ value: String) throws {
        try db.execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                       [.text(key), .text(value)])
    }
}

public enum LastMealToSleepStatus: String, Equatable, Sendable {
    case noMealTimestamp = "no_meal_timestamp"
    case noSleepOnset = "no_sleep_onset"
    case tooCloseWarning = "too_close_warning"   // < mealToSleepWarnHours (default < 3.0 h)
    case acceptable = "acceptable"               // >= warn, outside optimal 4..6 h
    case optimal = "optimal"                     // inside [optimalMin, optimalMax] (default 4..6 h)
}

public struct LastMealToSleepReport: Equatable, Sendable {
    public let day: ISODate
    public let lastMealLabel: String?
    public let lastMealHm: String?
    public let gapHours: Double?
    public let status: LastMealToSleepStatus
    public let lastMealCarbsGrams: Double
    public let caffeineCompliant: Bool?
    public let alcoholWithinCutoff: Bool?

    public init(day: ISODate, lastMealLabel: String?, lastMealHm: String?, gapHours: Double?,
                status: LastMealToSleepStatus, lastMealCarbsGrams: Double,
                caffeineCompliant: Bool?, alcoholWithinCutoff: Bool?) {
        self.day = day
        self.lastMealLabel = lastMealLabel
        self.lastMealHm = lastMealHm
        self.gapHours = gapHours
        self.status = status
        self.lastMealCarbsGrams = lastMealCarbsGrams
        self.caffeineCompliant = caffeineCompliant
        self.alcoholWithinCutoff = alcoholWithinCutoff
    }
}

/// Evaluates Last-Meal-to-Sleep gap (`< 3 h` warning, `4–6 h` optimal), last-meal carbohydrate load,
/// and caffeine/alcohol check-in flags so autonomic readiness suppression can distinguish lifestyle timing from training fatigue.
public final class LastMealToSleepEvaluator {
    private let db: Database
    private let calendar: Calendar

    public init(db: Database, calendar: Calendar = .current) {
        self.db = db
        self.calendar = calendar
    }

    public func evaluate(day: ISODate, sleepOnsetEpochSec: Int64?) throws -> LastMealToSleepReport {
        let defaults = try AppDefaultsStore(db).load()
        let diet = DietDayService(db)
        let checkIn = try CheckInService(db).day(day)
        let dietDay = try diet.day(day)

        struct TimedIntake {
            let label: String
            let hm: String
            let epochSec: Int64
            let carbs: Double
        }

        var timed: [TimedIntake] = []
        for meal in dietDay.meals {
            let eatenLines = meal.lines.filter { $0.state == .eaten }
            guard !eatenLines.isEmpty else { continue }
            if let hm = try diet.mealAteAt(meal.name, on: day),
               let epoch = Self.epochForHm(hm, on: day, calendar: calendar) {
                let carbs = eatenLines.reduce(0.0) { $0 + $1.nutrition.carbs }
                timed.append(TimedIntake(label: meal.name, hm: hm, epochSec: epoch, carbs: carbs))
            }
        }
        for extra in dietDay.extras {
            if let hm = extra.ateAt,
               let epoch = Self.epochForHm(hm, on: day, calendar: calendar) {
                timed.append(TimedIntake(label: extra.displayName, hm: hm, epochSec: epoch, carbs: extra.nutrition.carbs))
            }
        }

        let alcoholViolation = checkIn.noAlcoholWithin3h.map { !$0 }
        guard let latest = timed.max(by: { $0.epochSec < $1.epochSec }) else {
            return LastMealToSleepReport(
                day: day, lastMealLabel: nil, lastMealHm: nil, gapHours: nil,
                status: .noMealTimestamp, lastMealCarbsGrams: 0,
                caffeineCompliant: checkIn.caffeineBeforeNoon,
                alcoholWithinCutoff: alcoholViolation
            )
        }
        guard let sleepOnset = sleepOnsetEpochSec else {
            return LastMealToSleepReport(
                day: day, lastMealLabel: latest.label, lastMealHm: latest.hm, gapHours: nil,
                status: .noSleepOnset, lastMealCarbsGrams: latest.carbs,
                caffeineCompliant: checkIn.caffeineBeforeNoon,
                alcoholWithinCutoff: alcoholViolation
            )
        }

        let gapHours = Double(sleepOnset - latest.epochSec) / 3600.0
        let status: LastMealToSleepStatus
        if gapHours < defaults.mealToSleepWarnHours {
            status = .tooCloseWarning
        } else if gapHours >= defaults.mealToSleepOptimalMinHours && gapHours <= defaults.mealToSleepOptimalMaxHours {
            status = .optimal
        } else {
            status = .acceptable
        }
        return LastMealToSleepReport(
            day: day, lastMealLabel: latest.label, lastMealHm: latest.hm, gapHours: gapHours,
            status: status, lastMealCarbsGrams: latest.carbs,
            caffeineCompliant: checkIn.caffeineBeforeNoon,
            alcoholWithinCutoff: alcoholViolation
        )
    }

    private static func epochForHm(_ hm: String, on day: ISODate, calendar: Calendar) -> Int64? {
        let parts = hm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let dp = day.string.split(separator: "-").compactMap { Int($0) }
        guard dp.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = dp[0]
        comps.month = dp[1]
        comps.day = dp[2]
        comps.hour = h
        comps.minute = m
        comps.second = 0
        return calendar.date(from: comps).map { Int64($0.timeIntervalSince1970) }
    }
}
