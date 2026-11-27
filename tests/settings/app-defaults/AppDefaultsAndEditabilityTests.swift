import XCTest
@testable import FitnessCore

final class AppDefaultsAndEditabilityTests: XCTestCase {
    func testRetroactiveMealAteAtUsesDefaultMealTimeAndEvaluatesLastMealToSleepGap() throws {
        let db = try Database.inMemory()
        let defaults = AppDefaultsStore(db)
        try defaults.setDefaultMealTime("12:30", forMeal: "Brunch")
        try defaults.setDefaultMealTime("20:00", forMeal: "Dinner")

        let foods = FoodLibrary(db)
        let riceID = try foods.add(FoodDraft(name: "Jasmine Rice", kind: .food, unit: "g", baseQuantity: 100,
                                             protein: 7, carbs: 80, fat: 0.5, fiber: 1, satFat: 0.1, sodium: 0))
        let plan = DietPlanService(db)
        let yesterday = try XCTUnwrap(ISODate("2026-11-26"))
        let today = try XCTUnwrap(ISODate("2026-11-27"))
        try plan.addItem(foodID: riceID, quantity: 81.25, meal: "Dinner", from: yesterday) // 65g carbs

        let diet = DietDayService(db)
        // Confirming yesterday's unlogged Dinner on today's morning uses Dinner's default time ("20:00"), never today's clock.
        try diet.confirmRetroactiveMeal("Dinner", on: yesterday, confirmedOn: today, ateAtOverride: nil)
        XCTAssertEqual(try diet.mealAteAt("Dinner", on: yesterday), "20:00")

        // User edits yesterday's Dinner ate_at to 21:30 in place.
        try diet.setMealAteAt("21:30", meal: "Dinner", on: yesterday)
        XCTAssertEqual(try diet.mealAteAt("Dinner", on: yesterday), "21:30")

        // Check-in flags for caffeine before noon and alcohol within 3h are editable and nullable.
        let checkIn = CheckInService(db)
        try checkIn.setCaffeineBeforeNoon(true, on: yesterday)
        try checkIn.setNoAlcoholWithin3h(false, on: yesterday)
        let ci = try checkIn.day(yesterday)
        XCTAssertEqual(ci.caffeineBeforeNoon, true)
        XCTAssertEqual(ci.noAlcoholWithin3h, false)

        // Sleep onset at 23:45 on 2026-11-26 -> gap = 2.25h (< 3.0h warning) + alcohol violation.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        let sleepOnset = Int64(cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 23, minute: 45))!.timeIntervalSince1970)
        let reportWarn = try LastMealToSleepEvaluator(db: db, calendar: cal).evaluate(day: yesterday, sleepOnsetEpochSec: sleepOnset)
        XCTAssertEqual(reportWarn.status, .tooCloseWarning)
        XCTAssertEqual(try XCTUnwrap(reportWarn.gapHours), 2.25, accuracy: 0.01)
        XCTAssertEqual(reportWarn.lastMealCarbsGrams, 65.0, accuracy: 0.1)
        XCTAssertEqual(reportWarn.alcoholWithinCutoff, true)
        XCTAssertEqual(reportWarn.caffeineCompliant, true)

        // Update Dinner ate_at in place to 19:15 (gap = 4.5h -> optimal 4..6h window) and clear alcohol violation.
        try diet.setMealAteAt("19:15", meal: "Dinner", on: yesterday)
        try checkIn.setNoAlcoholWithin3h(true, on: yesterday)
        let reportOptimal = try LastMealToSleepEvaluator(db: db, calendar: cal).evaluate(day: yesterday, sleepOnsetEpochSec: sleepOnset)
        XCTAssertEqual(reportOptimal.status, .optimal)
        XCTAssertEqual(try XCTUnwrap(reportOptimal.gapHours), 4.5, accuracy: 0.01)
        XCTAssertEqual(reportOptimal.alcoholWithinCutoff, false)
    }

    func testGeneticsCustomGenesMarkerOverridesAndSavedLabNamesAreEditableInPlace() throws {
        let db = try Database.inMemory()
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let catalogueData = try Data(contentsOf: root.appendingPathComponent("output/labs-catalogue.json"))
        let catalogue = try LabCatalogue(data: catalogueData)

        let genetics = GeneticsService(db, catalogue: catalogue)
        let oct1 = try XCTUnwrap(ISODate("2026-10-01"))
        let sep15 = try XCTUnwrap(ISODate("2026-09-15"))

        let mthfr = try XCTUnwrap(catalogue.gene("mthfr"))
        let firstVariant = try XCTUnwrap(mthfr.genotypes?.first?.genotype)
        try genetics.set("mthfr", genotype: firstVariant, on: oct1)

        // Update in place with custom genotype text, new date, lab, and note.
        try genetics.updateEntry(
            geneID: "mthfr",
            genotype: firstVariant,
            customGenotype: "C677T TT + A1298C WT",
            enteredOn: sep15,
            lab: "MapMyGenome",
            note: "Clinical panel"
        )
        let updated = try XCTUnwrap(try genetics.entries().first(where: { $0.gene.id == "mthfr" }))
        XCTAssertEqual(updated.enteredOn, sep15)
        XCTAssertEqual(updated.customGenotype, "C677T TT + A1298C WT")
        XCTAssertEqual(updated.lab, "MapMyGenome")
        XCTAssertEqual(updated.note, "Clinical panel")

        // Custom gene outside the 24-gene catalogue: add, update in place, delete.
        try genetics.upsertCustomGene(CustomGeneEntry(
            id: "comt",
            name: "COMT",
            variant: "rs4680",
            genotype: "Val158Met Met/Met",
            enteredOn: oct1,
            lab: "23andMe",
            note: "Slow COMT"
        ))
        try genetics.upsertCustomGene(CustomGeneEntry(
            id: "comt",
            name: "COMT",
            variant: "rs4680",
            genotype: "Val158Met Met/Met",
            enteredOn: sep15,
            lab: "MapMyGenome",
            note: "Verified slow COMT"
        ))
        let custom = try genetics.customGenes()
        XCTAssertEqual(custom.count, 1)
        XCTAssertEqual(custom[0].enteredOn, sep15)
        XCTAssertEqual(custom[0].lab, "MapMyGenome")
        XCTAssertEqual(custom[0].note, "Verified slow COMT")
        try genetics.deleteCustomGene("comt")
        XCTAssertTrue(try genetics.customGenes().isEmpty)

        // Personal marker optimal range override respected by LabReader, editable and clearable.
        let overrides = LabMarkerOverrideService(db)
        try overrides.setOverride(LabMarkerOverride(markerID: "ferritin", optimalLow: 80, optimalHigh: 130, unit: "ng/mL", note: "Coach iron block"))
        let draws = LabDrawService(db, catalogue: catalogue)
        let drawID = try draws.addDraw(LabDrawDraft(date: oct1, lab: "Helthians"))
        _ = try draws.addResult(drawID: drawID, markerID: "ferritin", value: 65, unit: "ng/mL")
        let ferritinMarker = try XCTUnwrap(catalogue.marker("ferritin"))
        let ferritinResult = try XCTUnwrap(try draws.results(inDraw: drawID).first)
        let readingWithOverride = LabReader.read(
            result: ferritinResult,
            marker: ferritinMarker,
            preferences: LabPreferences(sex: .male),
            personalOverride: try overrides.override(for: "ferritin")
        )
        XCTAssertEqual(readingWithOverride.status, .low)

        // Rename saved lab name across draws without deleting draws.
        try draws.renameSavedLab(from: "Helthians", to: "Healthians Labs")
        XCTAssertEqual(try draws.savedLabNames(), ["Healthians Labs"])
    }

    func testAppDefaultsStorePersistsAllKnobsHiitPresetsAndStrapRtcAlarms() throws {
        let db = try Database.inMemory()
        let store = AppDefaultsStore(db)

        var snapshot = try store.load()
        snapshot.mealToSleepWarnHours = 3.5
        snapshot.caffeineMaxMg = 80
        snapshot.caffeineCutoffHm = "11:30"
        snapshot.oneMileTrialMaxHr = 194
        snapshot.manualHrZoneBounds = [115, 138, 156, 174, 186]
        snapshot.whoopCoachingMode = .maximizingVo2Max
        snapshot.vo2LimiterMode = .anaerobicBattery
        snapshot.stepTicksPerStep = 2.0
        snapshot.sleepEnduranceHours = 8.25
        snapshot.targetWakeHm = "06:45"
        try store.save(snapshot)

        let reloaded = try store.load()
        XCTAssertEqual(reloaded.mealToSleepWarnHours, 3.5, accuracy: 1e-6)
        XCTAssertEqual(reloaded.caffeineMaxMg, 80, accuracy: 1e-6)
        XCTAssertEqual(reloaded.caffeineCutoffHm, "11:30")
        XCTAssertEqual(reloaded.oneMileTrialMaxHr, 194)
        XCTAssertEqual(reloaded.manualHrZoneBounds, [115, 138, 156, 174, 186])
        XCTAssertEqual(reloaded.whoopCoachingMode, .maximizingVo2Max)
        XCTAssertEqual(reloaded.vo2LimiterMode, .anaerobicBattery)
        XCTAssertEqual(reloaded.stepTicksPerStep, 2.0, accuracy: 1e-6)
        XCTAssertEqual(reloaded.sleepEnduranceHours, 8.25, accuracy: 1e-6)
        XCTAssertEqual(reloaded.targetWakeHm, "06:45")

        // HIIT presets CRUD in place.
        let preset = HiitPreset(id: "norwegian-4x4", name: "Norwegian 4x4", mode: .time,
                                workSec: 240, restSec: 180, rounds: 4, highBpm: 178, lowBpm: 132, position: 1)
        try store.upsertHiitPreset(preset)
        var editedPreset = preset
        editedPreset.highBpm = 182
        try store.upsertHiitPreset(editedPreset)
        XCTAssertEqual(try store.hiitPresets().first?.highBpm, 182)

        // 7-day silent alarm schedule + 0x42 RTC-compensated frame builder.
        let mondayAlarm = WhoopAlarmDaySchedule(weekday: 1, hour: 6, minute: 45, enabled: true, smartWindowMinutes: 15)
        try store.upsertAlarmSchedule(mondayAlarm)
        XCTAssertEqual(try store.alarmSchedules().first(where: { $0.weekday == 1 })?.minute, 45)

        let targetWallEpoch: Int64 = 1_795_800_000
        let driftSec: Double = 12.0 // wallEpoch - strapUnix => strapRTC = wallEpoch - 12
        let setFrame = try WhoopSilentAlarmCommands.buildSetAlarmFrame(
            wallAlarmEpochSec: targetWallEpoch,
            strapClockDriftSec: driftSec,
            slot: 1,
            profile: .gen5
        )
        let decoded = try XCTUnwrap(WhoopFraming.parseFrame(setFrame, profile: .gen5))
        XCTAssertTrue(decoded.valid)
        XCTAssertEqual(decoded.opcode, WhoopCmd.setAlarmTime) // 0x42
        // Gen5 payload: [rev=0x04][slot=0x01][u32 LE strapEpoch = 1795799988][u16 subsec]...
        XCTAssertEqual(decoded.body[0], 0x04)
        XCTAssertEqual(decoded.body[1], 0x01)
        let strapEpoch = WhoopBytes.u32(decoded.body, 2)
        XCTAssertEqual(Int64(strapEpoch), targetWallEpoch - 12)
    }
}
