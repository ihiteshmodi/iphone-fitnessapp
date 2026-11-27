# Fitness iOS App — Complete Screen Inventory & Figma UI Handoff Blueprint

This document gives a complete, zero-omission map of:
1. **Part A — Current Live UI Inventory:** Every tab, screen, sub-screen, and modal sheet currently built in `app/Screens/`, what each screen displays, and how the user navigates between them.
2. **Part B — Newly Built Backend Engines, Data Stores & Editable Controls Awaiting Figma UI:** Every physiological metric, longevity model, 3-layer coaching check, live workout/HIIT haptic controller, meal-timing/cutoff rule, and editable override implemented in `FitnessCore` (`Schema v24` + `whoop.sqlite` `kAlgoVersion = 133`) that is ready for UI layout without cramming existing tabs.
3. **Part C — Editability Matrix:** Confirmation of every create / read / update / delete / override action exposed across the domain so no user-controlled item ever requires "delete-and-re-add".

---

## Part A — Current Live UI Inventory (5 Root Tabs + First-Launch Gate)

### 0. First-Launch / Database Gate (`app/FitnessApp.swift`, `app/Screens/Data/ImportDatabaseView.swift`)
- **When shown:** Only when `Documents/fitness.sqlite` does not yet exist.
- **Contents:**
  - **"Load my data"** button (when `output/fitness.sqlite` is bundled inside the `.ipa`) — copies the bundled personal database into `Documents/fitness.sqlite` and runs idempotent schema migrations (`v24`).
  - **"Import `.sqlite` file"** picker (`DataFileImporter`) — imports from Files / Google Drive / LiveContainer Inbox.
  - **"Start empty"** button — initializes an empty `Schema v24` database.
- **Automatic WHOOP DB Seeding (`WhoopBLEManager.openExistingStoreIfAvailable`):**
  - Outside `--uitesting`, if `output/whoop.sqlite` is bundled in the `.ipa`: copies it to `Documents/whoop.sqlite` on first launch, or non-destructively merges historical OpenStrap rows (`547,574` rows) into an existing `Documents/whoop.sqlite` while preserving any newer live `strap_trim` cursor.

---

### Tab 1: `Workout` (`app/Screens/Workout/WorkoutTabView.swift`)
1. **`WorkoutDayScreen` (`WorkoutDayScreen.swift`):**
   - **Header:** Plan day selector pills (e.g., Day 1..N / weekday / muscle title), Deload banner when deload mode is active, quick **`WHOOP Diag`** pill button (`WhoopDiagnosticView` sheet), **"Edit plan"** navigation link, and **"All / Remaining"** exercise filter toggle.
   - **Body:** Ordered exercise cards for the selected training day showing target sets × rep range, warm-up reference weights, working target weight (`kg`), PR/form-check badges, and logged sets for today.
   - **Drill-downs & Sheets:**
     - **`ExerciseDetailView` (`ExerciseDetailView.swift`):**
       - Set logger (`weight kg` + `reps` + 1-tap log), form-check prompt ("Did every rep have a full contraction?") when hitting top of rep range, `SessionLineChart` (weight / e1RM history with PR highlights), `MusclesWorkedCard` (`MuscleFigureView` front/back SVG anatomy), exercise instructions, and past session history.
       - **`DetailSheets.swift`:** In-place edit/delete of any logged set (`weight`, `reps`, `date`), rep-scheme override, and `MuscleEditorSheet` (custom primary/secondary muscle overrides).
     - **`EditPlanView` (`app/Screens/Plan/EditPlanView.swift`):**
       - Add/rename/reorder/delete training days, assign ISO weekdays, add exercises (`PlanAddExerciseSheet`), edit sets/reps/warm-ups (`PlanEntryEditSheet`, `PlanRepSchemeEditor`), inspect weekly plan muscle coverage (`PlanMuscleCoverageService`), and save/load whole workout splits or routines (`WorkoutLibraryViews`: `SavedWorkouts` & `Routines`, including Meridian coach presets).

---

### Tab 2: `Diet` (`app/Screens/Diet/DietTabView.swift`)
Top segmented switcher between **`Today`**, **`Plan`**, and **`Foods`**:
1. **`DietTodayView` (`DietTodayView.swift`):**
   - Date stepper (today / past days) + **"Unconfirmed past meals"** prompt banner (`7-day` lookback for unticked real meals on non-break days: 1-tap *Ate it* or *Skipped*).
   - **`DailyTargetsView`:** Planned vs. eaten Calories, Protein (`g/lb` & floor), Carbs, Fat (`20–35%` & `0.8 g/kg` floor), Fiber, Saturated Fat, Sodium, Glycemic Load, daily food cost (`₹`), and **"What-if Multivitamin"** simulator.
   - **Planned Meal Cards:** Per-meal checkbox (ticks all on-cycle items), per-food checkboxes, supplement cycle badges (`on` / `off until date`), per-meal leucine & glycemic load summary (`MealProfileSheet`).
   - **Extras Section:** Quick-add recent extras, `DietAddExtraSheet` (by grams, pieces, or pack), `QuickAddExtraSheet` (by weighed street-food batch or raw kcal), and `ExtraDetailsFields` (custom label, morning/noon/evening/night tag, note; full edit/delete).
   - **Embedded `CheckInCard` (`app/Screens/Insights/CheckInCard.swift`):** Optional daily urine colour (`Clear`, `Pale yellow`, `Dark yellow`), heavy sweat toggle, post-meal 10-min walk checkboxes, and weekly recovery signs checklist.
2. **`DietPlanView` (`DietPlanView.swift`):**
   - Dated diet plans (`effective_from` history so editing today's plan never alters past days' logs), add/move/delete meals, `DietPlanItemSheet` (quantity + cycle rule: daily, on/off weeks, on/off days, weekday bitmask, or training days), and `SavedDietsView` (named whole-diet templates).
3. **`DietFoodsView` (`DietFoodsView.swift`):**
   - Searchable library of all foods, supplements, liquids, herbs, and multi-ingredient recipes (`DietFoodFormSheet` with macro/micronutrient/GI/omega-3-form/pack-price fields, plus `DietRecipeView` ingredient builder & scaler).

---

### Tab 3: `Body` (`app/Screens/Body/BodyTabView.swift`)
1. **Weight & Calorie Trend Section (`BodyTabView.swift`, `BodySharedViews.swift`):**
   - Quick daily weight logger (`kg`), 7-day rolling weight average vs. goal rate (`Cut` / `Maintain` / `Bulk`), daily calorie target card (`BodyCaloriesSheet` for dated calorie defaults or single-day manual kcal overrides), and `RefeedsCard` (planned/completed refeed days during cuts).
2. **Tape & Skinfold Measurements:**
   - Sites (`Waist`, `Shoulders`, `Chest`, `Arms`, `Thighs`, `Calves`, `Body Fat %`, `Body Fat mm` skinfolds) with custom unit (`in`, `cm`, `mm`, `%`) and `grow` / `reduce` target badges.
   - **`BodyHistoryListView`:** Full chronological history with in-place edit and delete for body weights, measurements, and calorie entries.
3. **`Bloodwork` Hub Entry Card (`LabsEntryCard` $\rightarrow$ `LabsView.swift`):**
   - **Top Alerts & Guides:** Sex confirmation prompt (first run), urgent Doctor Referral banners, collapsible 4-step *How Bloodwork Works* guide, and **★ Mandatory Core Tests Pending / Retest Due** card.
   - **4 Navigation Tiles (`actions`):**
     1. **`BloodworkDashboardView` (`BloodworkDashboardView.swift`):** Compact scannable status summary (out-of-range vs. optimal counts, clinical systems status pills) with drill-downs into `BloodworkInterpretationsDetailView` (patterns, discordances, genetic target notes) and `TestedMarkersListView` (latest-per-marker across all historical draws).
     2. **`PlanDrawView` (`PlanDrawView.swift`):** Next-draw planner (foundational panels, conditional follow-ups, retest-due markers, genotype-mandated confirmers, and 16-point pre-draw prep checklist).
     3. **`MarkerLibraryView` (`MarkerDetailView.swift`):** Search + quick chips (`All`, `Core`, `Logged`, `Out of range`, `Never tested`) + multi-criteria filter sheet across 80+ markers; tapping any marker opens `MarkerDetailView` (longitudinal chart, `LabRangeBar`, strata bands, causes high/low, actions, and add/edit result).
     4. **`GeneticsView` (`GeneticsView.swift`):** TRT/Rx clinical context card (`LabClinicalContextSheet`), quick filter chips (`All`, `Logged`, `Worth knowing once`, `Triggered`, `Conditional`, `Skip`), Reverse-Genetics recommendations, Active Genetic Findings, 24 vault genes grouped by 5 clinical action categories, and `GeneDetailView` (**now upgraded with in-place editing of entry date, testing lab, custom genotype wording, and notes**).
   - **Draws List & Settings (`AddDrawSheet.swift`, `LabsSettingsSheet`):**
     - Tap any draw to edit draw metadata/16 prep flags in place, or tap any marker row inside a draw to edit/delete its numeric, `<LOD`, paired BP, or qualitative result.
     - **Toolbar Share (`square.and.arrow.up`):** Exports `labs-review-YYYY-MM-DD.md` for AI clinical review.
     - **Toolbar Gear (`LabsSettingsSheet`):** Profile modifiers + **Export Blank AI JSON Template**, **Export Current Draws + Guide JSON**, **Import AI-Filled Lab/DNA JSON**, and **Saved Lab Names Rename/Clear**.

---

### Tab 4: `Progress` (`app/Screens/Progress/ProgressTabView.swift`)
- **`ProgressVolumeSection`:** Weekly hard-set volume per `MuscleRegion` (primary = `1.0`, secondary = `0.5` sets) against `10–20` set hypertrophy landmarks (or custom per-muscle min/max overrides), with front/back `MuscleFigureView` heatmaps.
- **Strength & Measurement Trends:** Key lift progression summaries and `MeasurementDetailView` per-site charts with tolerance bands (`MeasurementTolerance`).
- **`RoomForImprovementView` (`app/Screens/Insights/RoomForImprovementView.swift`):** Actionable daily, setup, nutrition, training, and lab insights with 1-tap *Dismiss for today*, *Accept*, or *Not applicable* (with custom note).

---

### Tab 5: `More` (`app/Screens/More/MoreTabView.swift`)
- **Training & Diet Knobs:** History start date, day label mode (Day number vs. Weekday), Deload toggle & multipliers (`weight ×`, `reps ×`, ignore deload in PRs), Nutrition rules (`protein g/lb`, `protein floor g`, `fat %`, `fat floor g/kg`), and per-muscle weekly set target overrides.
- **`BreakModeCard`:** Start/end/edit vacation or illness break periods so missed logs never penalize averages.
- **Tools & Libraries:**
  - **`LibraryView` (`More/Library/`):** Full Exercise Library browser & editor (`LibraryExerciseFormView`).
  - **`SupplementsView` (`Screens/Supplements/SupplementsView.swift`):** Meridian Supplement Library reference browser (evidence tiers, dosing, forms, interactions).
  - **`EditPastDataView`:** Unified date-jumper to inspect/correct historical sets, weights, measurements, or diet logs.
  - **Export Diet for AI Review:** Generates `diet-review-YYYY-MM-DD.md` via item-bound `ShareSheet`.
  - **Database Backup / Restore:** Export `fitness-YYYY-MM-DD.sqlite` (`PRAGMA wal_checkpoint(TRUNCATE)` standalone snapshot) or import/restore from backup.
  - **`WhoopBandView` (`WhoopBandView.swift`) & `WhoopDiagnosticView` (`WhoopDiagnosticView.swift`):**
    - BLE scan/pair/reconnect, live BPM, battery `%`, wrist state, sync provenance (`Imported History` vs. `Synced by FitnessApp` row counts + `strap_trim` cursor), manual sync trigger, `Export whoop.sqlite`, `Merge OpenStrap DB`, and full protocol/packet/SQLite diagnostic inspector.

---

## Part B — Newly Built Backend Engines & Features Awaiting Figma UI Layout

Everything below is **100% implemented, persisted, and unit-tested (`823` passing tests)** in `FitnessCore` and wired into `Services`, deliberately held back from cramming existing screens so you can design clean, dedicated Figma layouts first.

### 1. Daily Recovery, Sleep, Strain & Telemetry Hub (`src/modules/whoop/analytics/`, `kAlgoVersion = 133`)
** Suggested Figma placement:** Dedicated **`Recovery` / `Band` tab** (or top hub card on `Body` / `Workout` with drill-downs).
- **Morning Readiness / Recovery Card (`WhoopReadinessAndStrainEngine.readinessComposite`):**
  - Headline `1–100%` score + Green (`67–100`) / Yellow (`34–66`) / Red (`1–33`) ring, calibration badge (`Calibrating <14d` vs. `Calibrated`), morning-freeze lock indicator, and 4 glass-box contributor bars:
    - **Headline HRV (`sleepSessionRmssdDetail`):** Nightly 5-min mean RMSSD (`ms`) + `ln(RMSSD)` vs. 28-day self-excluded baseline + confidence `%` (or refusal badge if overcounted / timing jitter).
    - **Nocturnal RHR (`nocturnalRhr`):** Lowest 30-min `>=90%`-covered sleep trough (`bpm`) + `P1` nadir vs. 28-day baseline (abstains cleanly if `TST < 3h`).
    - **Respiration Rate (`rsaRespRate`):** Lomb–Scargle nocturnal breaths/min (`brpm`) vs. 28-day baseline.
    - **Skin Temperature (`consistentSkinTempUnit` + `evaluateTempIllness`):** Nightly deviation (`°C` on Gen5) + **Cycle-Aware Illness Banner** (`normal`, `luteal_confound`, or `elevated` when `z >= 2.0` for `>= 2` consecutive settled nights).
- **4-Stage Sleep & Nap Timeline (`WhoopSleepAndNapEngine.stageSleepWindow`, `detectNaps`):**
  - Hypnogram ribbon (`Wake`, `Light`, `Deep`, `REM`, `Unobserved`), `TST`, `Time in Bed`, `WASO`, `Efficiency %` (over observed seconds), `Sustained Awakenings`, and Gen5 lie-in trim badge (`bandOffsetTrimSec`).
  - **Editable Controls to Design in Figma:**
    - *Edit Sleep Onset / Wake Time* sheet (`WhoopAnalyticsStore.upsertSleepOverride` / `deleteSleepOverride`).
    - *Pending Nap Suggestions* banner + *Add / Edit Manual Nap* sheet (`WhoopAnalyticsStore.upsertNap`, `updateNapSpan`, `deleteNap`, `updateProposalStatus`).
- **Day Strain, HR Zones & Daily Energy (`computeDailyStrain`, `computeCtlAtlTsb`, `trainingZones`, `computeDailyEnergy`):**
  - `0.0–21.0` Day Strain gauge (`Exercise Net TRIMP` vs. `Quiet-Waking Living TRIMP`, never debited by afternoon sitting), `CTL / ATL / TSB` load ratio chart, 5-Zone HR breakdown (`Manual` / `1-Mile` / `Karvonen` / `Observed` / `Tanaka`), and `Total = Basal (Mifflin–St Jeor) + Active (Keytel HR-flex + Cadence)` kcal bar.

---

### 2. Steps (Zero-HealthKit Gen5 Filter) & Weekly Longevity Suite (`src/modules/whoop/longevity/`)
**Suggested Figma placement:** Longevity section inside `Body` (next to Bloodwork PhenoAge) or inside the `Recovery` tab.
- **Filtered Band Steps Card (`WhoopStepsEngine.countStepsFromDatabase`):**
  - Displays pure WHOOP 5.0 locomotion steps (`activity_class ∈ {1 walk, 2 run}` + sleep-bout coherence filter) and current `stepTicksPerStep` divisor (`0.5–30.0`, editable in Settings).
- **Weekly `VO2 Max` & `Fitness Age` Card (`WhoopLongevityEngines.computeFitnessAge`):**
  - `VO2 Max (mL/kg/min)` with estimator pill (`Nes 2011 · Waist cm` vs. `Uth 2004 · HR Ratio` ± `SEE`), weekly HUNT1 `PAI (0–15)` from normalized `0–21` Strain, and `Fitness Age` (`Δ years younger/older`, `.estimate` at 4–5 RHR days vs. `.ready` at `6+` days).
- **Weekly `Vitality (0–100)` & `Body Age` Card (`WhoopLongevityEngines.computeVitality`):**
  - Gompertz all-cause mortality `Body Age` (`20–90 yr`) + `0–100 Vitality` gauge + per-factor protective/aging breakdown (`RHR`, `Sleep Duration`, `Sleep Consistency`, `HRV vs. Age Norm`, `Steps`).
- **ACSM Treadmill `VO2 Max` Calculator & Log (`AcsmTreadmillVo2Service`):**
  - Interactive calculator + historical log list (`speed km/h`, `incline %`, `duration min`, optional submaximal `steady HR` + `RHR` + `Max HR` $\rightarrow$ `VO2` & `%HRR`-scaled `Estimated VO2 Max`, with full in-place edit & delete).

---

### 3. 3-Layer WHOOP Coaching & 90-Day Mode Switcher (`src/modules/whoop/coaching/WhoopCoachingEngine.swift`)
**Suggested Figma placement:** Mode selector pill at top of `Recovery` / `Progress` + contextual cards on `Workout` & `Diet`.
- **Mode Switcher (`WhoopCoachingMode` in `AppDefaultsStore`):**
  - Segmented/pill selector: **`General Health`** (default) · **`Maximizing VO2 Max`** · **`Maximizing HRV`** · **`Reducing RHR`**.
- **Layer 1 Static Principles Carousel / Drawer (`WhoopCoachingEngine.layer1Principles`):**
  - Lightweight non-graded tip cards (Diurnal Stress, Cardio Modality Vehicle Matching, Fueling by Intensity, `+5%` Ceiling, Strides & Tempo definitions, Optional Pre-Bed Protein).
- **Layer 2 Daily & Weekly Checks (`WhoopCoachingEvaluation`):**
  - **Red Recovery Context Override Banner:** Distinguishes *"Single Red day from `<3h` late meal / short sleep — keep normal strain"* (`keepNormalStrainOverride = true`) vs. *"3+ Consecutive Red Days — take Rest / Deload"* (`deloadTriggered = true`).
  - **Tonight's Sleep Planner:** `Dynamic Sleep Need` (`7.0h` rest / `7.5h` lifting / `8.0h` endurance + debt − valid nap credit) $\rightarrow$ **`Target Bedtime (HH:MM)`** backward from `targetWakeHm`, plus `>= 2h` wake-drift jet-lag indicator.
  - **Weekly Cardio & Strength Audit:** Zone 2 minutes (`150 min` floor $\rightarrow$ `300 min` build target, `110–140 bpm` or `110–130 bpm`), Gray-Zone session flags, Intensity Split bar, `+5%` progression guard, `1 hard : 2 easy` spacing check, same-day cardio/lifting `<3h` interference warning, and `3.0 h/wk` lifting longevity benchmark progress bar.
- **Layer 3 Goal-Specific Widgets (shown only when that mode is active):**
  - **Mode A (`Maximizing VO2 Max`):** `1-Mile Time Trial` Max HR calibration prompt, `50 min/wk >85% HRmax` progress ring, `7 h/wk` (`420 min`) ceiling bar, and `10K under (180 − age)` Limiter Picker (`Aerobic Power 80/0/20`, `Anaerobic Battery 60/30/10`, `Processing Power 75/15/10`).
  - **Mode B (`Maximizing HRV`):** Weekly `90–180 min` Zone 3–5 Long Endurance tracker (with `longEnduranceExempt` toggle suppressing Gray-Zone warnings) + **4-Day Post-Endurance Rebound Stepper** (`Day 1` 35–50% HRV drop check $\rightarrow$ `Day 2` 50m flush $\rightarrow$ `Days 3–4` supercompensation + `>2` rest-day plasma-volume guard).
  - **Mode C (`Reducing RHR`):** **Today's Step-Adjusted Easy Cardio Prescription** (`<5k` steps $\rightarrow$ `40m`, `5k–10k` $\rightarrow$ `25m`, `>10k` $\rightarrow$ `0m` + `30m` secondary day at `110–130 bpm`), **Strict Noon Caffeine Badge**, and **3-Week Microcycle Indicator** (`Wk 1` `1.0x` $\rightarrow$ `Wk 2` `1.10x` $\rightarrow$ `Wk 3` `0.50x` Zone-2 deload).

---

### 4. Live Workout Bar, Per-Exercise HR, Dual-Mode HIIT Haptics & Auto-Workout Proposals (`src/modules/whoop/workout/`)
**Suggested Figma placement:** Compact floating/collapsible bar on `WorkoutDayScreen` + HIIT sheet + Pending Proposals banner.
- **Live Workout Session Bar (`WorkoutSessionService`):**
  - Start / Finish session (`0x03` realtime HR stream), live BPM + current HR Zone pill + elapsed clock, throttled `UNUserNotificationCenter` background zone alerts (`LiveWorkoutNotificationDispatcher`), and **Post-Workout Session Editor** (edit `start_ts`, `end_ts` when stopped late, `sport`, `kind`, `longEnduranceExempt`, `notes`, or delete).
- **Per-Exercise Heart-Rate Breakdown (`WorkoutSessionService.correlateExerciseHeartRates`):**
  - Automatically pairs stamped `LoggedSet.loggedAtTs` timestamps with 1 Hz WHOOP HR to display `Avg BPM`, `Peak BPM`, and mini Zone 0–5 bar under each completed exercise! (`LoggedSet.loggedAtTs` is also editable in set details.)
- **Non-Blocking Dual-Mode HIIT Timer + Strap Haptics (`DualModeHiitEngine` + `AppDefaultsStore.hiitPresets`):**
  - Preset picker (Norwegian `4×4`, `8×200m`, Tabata, or custom HR Peak/Recover) with full add/edit/reorder/delete.
  - **Time Mode:** `workSec / restSec / rounds` countdown firing WHOOP wrist vibration (`0x13` Gen5 / `0x4F` Gen4) on every interval change while lifting/cardio screens remain interactive.
  - **HR-Threshold Mode:** Push until `>= highBpm` $\rightarrow$ strap buzzes double-pulse $\rightarrow$ recover until `<= lowBpm` (`10 s` hysteresis cooldown) $\rightarrow$ strap buzzes single-pulse for next round!
- **Auto-Detected Workout Proposals (`WhoopAutoWorkoutDetector`):**
  - Review card for unlogged `>=12 min` elevated-HR bouts (including stationary-wrist cycling rescued via `+25 bpm` 3-min cardiac onset): **Accept & Edit** (`start_ts`, `end_ts`, `sport`, `kind`, `notes`), **Dismiss**, or **Undo**.

---

### 5. Meal `ate_at` Timestamps, Journal Cutoffs, 7-Day Silent Alarms & `AppDefaultsStore` (`src/shared/settings/AppDefaultsStore.swift`)
**Suggested Figma placement:** Small time pill on meal headers (`DietTodayView`), 2 toggles in `CheckInCard`, Alarm card in `WhoopBandView`, and centralized `Defaults & Thresholds` screen in `More`.
- **Meal & Extra `ate_at` Time Pills (`DietDayService.setMealAteAt`, `confirmRetroactiveMeal`, `ExtraDetails.ateAt`):**
  - Shows `"20:00"` next to each ticked meal (pre-filled from that meal's configurable default time — never the morning-after clock when confirming yesterday's meals!), tappable to edit `"HH:MM"` in place.
- **Last-Meal-to-Sleep & Late-Carb Card (`LastMealToSleepEvaluator`):**
  - Displays exact gap (`hours`) before WHOOP sleep onset (`<3h` Amber/Red warning vs. `4–6h` Green optimal badge) + grams of carbohydrate in the last meal/extra.
- **2 New Optional Check-In Toggles (`CheckInService`):**
  - `Caffeine ≤ 100 mg & finished before 12:00 PM` (`caffeineBeforeNoon`)
  - `No alcohol within 3h of bed` (`noAlcoholWithin3h`)
- **WHOOP 7-Day Silent Haptic Alarm Scheduler (`AppDefaultsStore.alarmSchedules` + `WhoopSilentAlarmCommands`):**
  - Monday–Sunday `HH:MM` + enable toggle + smart-wake window (`0–60m`), transmitting RTC-drift-compensated `0x42` (`SET_ALARM_TIME`) / `0x45` (`DISABLE_ALARM`) frames to the strap.
- **Marker Personal Optimal Target Overrides (`LabMarkerOverrideService`):**
  - Optional `"Set personal target (low / high / note)"` sheet on `MarkerDetailView` so clinician/coach marker targets override default bands cleanly and can be edited or cleared anytime.
- **Centralized `AppDefaultsStore` Screen (`More` $\rightarrow$ `Defaults & Cutoffs`):**
  - Single clean settings form for per-meal default times, meal-to-sleep warn/optimal hours, caffeine mg & cutoff time, alcohol & hard-training cutoffs, `1-Mile Time Trial` Max HR, manual 5-zone BPM bounds, `stepTicksPerStep`, sleep need hours (`rest` / `lifting` / `endurance`), `targetWakeHm`, warm-up `%` steps, PR clean-form toggle, and deload cycle length.

---

## Part C — Complete Domain Editability Matrix (Zero "Delete-and-Re-Add" Traps)

| Entity | Store / Service | Create | Update In Place | Clear / Delete |
|---|---|---|---|---|
| Catalogue Genotypes (`date`, `lab`, `custom_genotype`, `note`) | `GeneticsService` *(UI live in `GeneDetailView`)* | `set` | `updateEntry` | `clear` |
| Custom Genes / Non-Catalogue SNPs | `GeneticsService` | `upsertCustomGene` | `upsertCustomGene` | `deleteCustomGene` |
| Lab Draws, 16 Prep Flags & Marker Results | `LabDrawService` *(UI live in `LabsView`)* | `addDraw` / `addResult` | `updateDraw` / `updateResult` | `deleteDraw` / `deleteResult` |
| Saved Lab Names | `LabDrawService` *(UI live in `LabsSettingsSheet`)* | automatic on draw | `renameSavedLab(from:to:)` | `clearSavedLab(_:)` |
| AI Lab + Prep + Genetics JSON Template | `LabJsonTemplateService` *(UI live in `LabsSettingsSheet`)* | `exportTemplateJSON` | `importFilledJSON` (idempotent upsert) | — |
| Personal Marker Optimal Range Overrides | `LabMarkerOverrideService` | `setOverride` | `setOverride` | `deleteOverride` |
| Meal `ate_at` & Retroactive Meal Confirmations | `DietDayService` | `setMealEaten` / `confirmRetroactiveMeal` | `setMealAteAt` | `setMealAteAt(nil, ...)` |
| Extra Food `ate_at`, Label, Time Tag, Amount | `DietDayService` | `addExtra` | `updateExtra` / `updateExtraDetails` | `removeExtra` |
| Caffeine & Alcohol Cutoff Check-Ins | `CheckInService` | `setCaffeineBeforeNoon` / `setNoAlcoholWithin3h` | same (`true` / `false`) | pass `nil` |
| Lifting Set Weight, Reps, Date & `logged_at_ts` | `LogSets` | `logSets` | `updateSet(..., loggedAtTs:)` | `deleteSet` |
| Live / Logged Workout Sessions (`start_ts`, `end_ts`, `sport`, `kind`, `notes`) | `WorkoutSessionService` | `startSession` | `updateSession` (recomputes HR/zones/strain!) | `deleteSession` |
| Auto-Detected Workout & Nap Proposals | `WhoopAnalyticsStore` + `WorkoutSessionService` | `queueProposals` | `acceptWorkoutProposal` (with edited start/end/sport) / `updateProposalStatus` (undo) | `updateProposalStatus("discarded")` |
| Sleep Onset / Wake Overrides | `WhoopAnalyticsStore` | `upsertSleepOverride` | `upsertSleepOverride` | `deleteSleepOverride` |
| Manual & Accepted Daytime Naps | `WhoopAnalyticsStore` | `upsertNap` | `updateNapSpan` | `deleteNap` |
| Menstrual Cycle Start Logs (`tempIllnessFlag` luteal awareness) | `WhoopAnalyticsStore` | `upsertCycleLog` | `upsertCycleLog` | `deleteCycleLog` |
| ACSM Treadmill `VO2 Max` Logs | `AcsmTreadmillVo2Service` | `addLog` | `updateLog` | `deleteLog` |
| Dual-Mode HIIT Presets (`Time` & `HR Threshold`) | `AppDefaultsStore` | `upsertHiitPreset` | `upsertHiitPreset` | `deleteHiitPreset` |
| 7-Day Silent WHOOP Alarms (`0x42` / `0x45`) | `AppDefaultsStore` | `upsertAlarmSchedule` | `upsertAlarmSchedule` | `deleteAlarmSchedule` |
| All Thresholds, Cutoffs, Coaching Mode, Zones & `stepTicksPerStep` | `AppDefaultsStore` | `save` | `save` / `setDefaultMealTime` | reset via `save(AppDefaultsSnapshot())` |
