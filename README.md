# Offline Fitness Tracker for iPhone: workouts, PRs, body and calories

![Platform](https://img.shields.io/badge/platform-iOS%2016%2B-black)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20SQLite-F05138)
![Data](https://img.shields.io/badge/data-offline%2C%20one%20SQLite%20file-2ee887)
![Backend](https://img.shields.io/badge/backend-none-lightgrey)

> An offline iPhone app that replaces a weekly "notes → spreadsheet → Python notebook → screenshot" routine: log sets on the phone, get the next weight for every exercise, spot PRs at a glance, and track body weight, calories and measurements. No account, no server.

All screenshots below are the real app on an iPhone 15 Pro Max (iOS simulator), filled with **generated sample data** (invented weights, reps and measurements), not anyone's real training data.

### Training

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/01-workout.png" width="170"><br><sub><b>Workout day</b><br>every exercise with its target; <i>All</i> shows everything</sub></td>
    <td align="center"><img src="docs/screenshots/02-remaining.png" width="170"><br><sub><b>Remaining</b><br>hides what is already logged today</sub></td>
    <td align="center"><img src="docs/screenshots/03-exercise-pr.png" width="170"><br><sub><b>PR banner</b><br>gold banner, next weight, estimated 1RM, gold ★ dot</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/04-log-sets.png" width="170"><br><sub><b>Log sets</b><br>warm-ups as reference, one main set, earlier sessions to edit</sub></td>
    <td align="center"><img src="docs/screenshots/05-add-set.png" width="170"><br><sub><b>Add set</b><br>− / + on weight and reps, reps start mid-range</sub></td>
    <td align="center"><img src="docs/screenshots/06-form-question.png" width="170"><br><sub><b>Clean-form check</b><br>asked once when you reach the top reps</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="docs/screenshots/07-muscle-editor.png" width="170"><br><sub><b>Muscles worked</b><br>pick a whole region or single muscles</sub></td>
    <td align="center"><img src="docs/screenshots/12-edit-plan.png" width="170"><br><sub><b>Edit plan</b><br>main sets, warm-up sets, rep range</sub></td>
    <td align="center"><img src="docs/screenshots/13-library.png" width="170"><br><sub><b>Exercise library</b><br>names, muscle groups, how-to</sub></td>
  </tr>
</table>

### Body, progress and settings

<table>
  <tr>
    <td align="center"><img src="docs/screenshots/08-body.png" width="170"><br><sub><b>Body</b><br>calorie target, weekly weight, what your weight says</sub></td>
    <td align="center"><img src="docs/screenshots/09-body-calories.png" width="170"><br><sub><b>Daily calories</b><br>default from a date, edit any day</sub></td>
    <td align="center"><img src="docs/screenshots/10-progress.png" width="170"><br><sub><b>Progress</b><br>measurements with % from target, volume per muscle</sub></td>
    <td align="center"><img src="docs/screenshots/11-more.png" width="170"><br><sub><b>More</b><br>backup, deload, history start, past data</sub></td>
  </tr>
</table>

## Features

- **Workout per day:** working weight, a progression recommendation, and an **All / Remaining** filter so the last exercises are not many scrolls away.
- **Main and warm-up sets:** one main set to failure is logged and counted (the circle reads 0/1); warm-ups (0 to 3) are shown with weights as a reference and never logged.
- **PRs:** reaching the top of the rep range with clean form is a PR. It shows as a gold banner, a gold ★ on the best-set chart and a gold chip on the list, with the **next weight worked out from the estimated 1RM**.
- **Fast logging:** the reps start in the middle of the range, − / + buttons on weight (2.5 kg) and reps, log for another day, edit or delete any set, look up and fix any past day.
- **Muscle diagram:** which muscles an exercise trains, automatic and editable per exercise.
- **Body:** weigh-ins, calorie target with macros, daily calories with a default that starts on a date, and the actual deficit or surplus from your weight trend.
- **Progress:** measurements against targets (grow or reduce, % from target, colour tolerance) and volume per muscle.
- **Deload mode** (display only, scales both ends of the rep range), plan and library editing, database import, export and automatic upgrade.

## Quick Start

For developers. You need a recent Xcode (Swift 5.9 or newer, iOS 16+ SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/ihiteshmodi/iphone-fitnessapp.git
cd iphone-fitnessapp

swift test                # logic tests, no simulator needed
# Expected (last lines): Executed 431 tests, with 10 tests skipped and 0 failures (0 unexpected)
#   the 10 skipped need your own seeded database (see "Configuration")

xcodegen generate         # creates FitnessApp.xcodeproj from project.yml
# Expected: Created project at .../FitnessApp.xcodeproj

open FitnessApp.xcodeproj # pick an iPhone simulator and press Run
# Expected: the app opens on "Set up your data"; choose "Start empty" to try it
```

## Usage

### Log a workout day (in the app)

1. **Workout** tab: pick a day. Each card shows the working weight and a chip: green *Increase reps*, amber *Same weight, clean*, or gold *★ Go to 72.5*.
2. Tap **Remaining** to hide the exercises you have finished.
3. Open an exercise. Follow the warm-up weights, then tap **+ Add set**. Weight and reps have − / + buttons; tap a number to type it.
4. If the reps reach the top of the range, the app asks **"Did every rep have a full contraction?"**. Yes counts as a PR; No means the same weight next time.

Worked example (rep range 10 to 15, last session 35 kg × 15, answered Yes):

```text
Banner:        ★ PR last time · clean form — Increase weight to 40 kg
Est. 1RM:      35 × (1 + 15 / 30) = 52.5 kg
Next weight:   52.5 ÷ (1 + 10 / 30) = 39.4 → rounded to the nearest 2.5 kg = 40 kg
Do today:      40 kg   (warm-ups at 75% = 30 kg and 90% = 36 kg when 2 warm-up sets are planned)
```

### Back up or inspect your data

The live file is `Documents/fitness.sqlite` inside the app. Use **More → Export database (.sqlite)**, or in LiveContainer open the app's data folder. Then:

```bash
sqlite3 fitness.sqlite "select count(*) from set_logs;"
# one number: how many sets you have logged
sqlite3 fitness.sqlite "select performed_on, weight_kg, reps from set_logs order by id desc limit 1;"
# one row, for example: 2026-10-26|35.0|15
```

If the Files picker will not select the file inside LiveContainer, copy it into the app's `Documents` folder: it is listed on the first screen and under **More → Backup**.

### Build a seeded database from a spreadsheet

```bash
cd tools/seed-db
python3 -m venv .venv && .venv/bin/pip install openpyxl pandas pytest   # once
.venv/bin/python build_seed_db.py --xlsx "path/to/Data File.xlsx"
# Wrote .../output/fitness.seed.sqlite
.venv/bin/python -m pytest
# 69 passed
```

### Build an unsigned .ipa (for LiveContainer)

```bash
xcodegen generate
xcodebuild -project FitnessApp.xcodeproj -scheme FitnessApp -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' -derivedDataPath .derived-device \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
# ** BUILD SUCCEEDED **
mkdir -p Payload && cp -R .derived-device/Build/Products/Release-iphoneos/FitnessApp.app Payload/ && zip -qry FitnessApp.ipa Payload
```

### Run the simulator UI tests

```bash
SIM_UDID=<an iPhone simulator id> scripts/run-ui-tests.sh WorkoutFlowUITests
# ALL 7 UI TESTS PASSED  (...)
```

The runner shows a live progress bar and stops when the tests finish. It uses `output/fitness.seed.sqlite`, never your own data.

## Configuration

There are no environment variables or secrets. The app is configured by settings stored in the database (change them in the app) and by two optional build-time files.

### Settings (stored in the `settings` table)

| Setting | Where in the app | Default | Required |
|---|---|---|---|
| Count history from | More → Progress history | `2026-08-31` (seeded) | No |
| Name days by | More → Plan / Edit plan | numbers | No |
| Deload on | More → Deload week | off | No |
| Deload weight multiplier | More → Deload week | `1` | No |
| Deload reps multiplier (both ends of the rep range) | More → Deload week | `0.75` | No |
| Ignore deload sessions in progress | More → Deload week | on | No |
| Protein g per lb | Body → Macro rules | `1.2` | No |
| Fat % of calories | Body → Macro rules | `25` | No |
| Measurement tolerance | Progress → ±3% | `3` % (amber beyond it, red beyond 10%) | No |

### Build-time and launch options

| Option | What it does | Default | Required |
|---|---|---|---|
| `output/fitness.sqlite` | If present at build time it is bundled and offered as **Load my data** on first launch | absent (button hidden) | No |
| `output/fitness.seed.sqlite` | Test fixture built from the spreadsheet; used by tests, UI tests and the screenshot tour | absent (10 parity tests skip) | No |
| `-UITestImportPath <file>` | Simulator tests only: import this database at launch | unset | No |
| `-UITestInitialTab <0-3>` | Simulator tests only: start on a tab (0 Workout, 1 Body, 2 Progress, 3 More) | `0` | No |

## Reference

This app has **no server and no HTTP API**. This section documents the local database and the rules the screens follow.

### Database tables (schema version 7)

| Table | Holds |
|---|---|
| `exercises` | Library: name, muscle group, how-to |
| `plan_days`, `plan_entries` | Training days and their exercises: main `sets`, `warmup_sets` (0 to 3), min and max reps |
| `set_logs` | Every logged set: date, exercise, weight kg, reps, deload flag |
| `form_checks` | Clean-form answer per exercise per day (1 clean, 0 not clean) |
| `exercise_muscles` | Muscles chosen per exercise (no rows means automatic) |
| `body_weights`, `body_measurements`, `measurement_targets` | Weigh-ins, readings, targets with a grow or reduce direction |
| `calorie_defaults`, `calorie_entries` | Calories per day from a start date, and single-day overrides |
| `settings` | The settings above |

The schema lives in `src/shared/database/schema.sql`. Older files are upgraded in place when opened (versions 1 to 6 are covered by tests).

### Rules

| Rule | Definition |
|---|---|
| Estimated 1RM | Epley: `weight × (1 + reps ÷ 30)` |
| PR | A session reaching the top of the rep range with clean form (older sessions without an answer count as clean). Not during deload |
| Next weight after a PR | `1RM ÷ (1 + min reps ÷ 30)`, rounded to the nearest 2.5 kg, always above the weight lifted |
| Reps in Add set | Start at `ceil((min + max) ÷ 2)`, for example 8 to 16 gives 12 |
| Warm-ups | 1: 75%. 2: 75% and 90%. 3: 60%, 75% and 90% of the working weight |
| Calorie target | Maintenance = calories eaten minus the daily surplus implied by the change between the last two 7-day average weights (3,500 kcal per lb). Target = maintenance × goal multiplier |
| Measurement colour | Only the wrong direction counts: within the tolerance is green, beyond it amber, beyond 10% red |

### Errors the app shows (validation messages)

| Message | When |
|---|---|
| `Reps must be at least 1` / `Weight cannot be negative` | Adding or editing a set |
| `Pick today or an earlier date` | Logging or editing a set for a future day |
| `Warm-up sets must be between 0 and 3` | Saving a plan entry |
| `Min reps cannot exceed max reps` | Saving a plan entry |
| `Tolerance must be between 0% and 50%` | Changing the measurement tolerance |
| `Log body weight for both of the last two weeks` | Calorie target without enough weigh-ins |

## Your data is not in this repository

The repository is public, so personal data is git-ignored: the spreadsheet, the notebook, your exported database (`output/fitness.sqlite`), the test fixture and the `.ipa` (it embeds the database). Without a database the app still works: choose **Start empty** on first launch.

## Project layout

| Path | What |
|---|---|
| `src/shared/` | SQLite schema and wrapper, settings, exercise library |
| `src/modules/<capability>/<feature>/` | Domain logic per feature (planning, logging, nutrition, progress, data) |
| `tests/<capability>/<feature>/` | `.feature` scenarios and the XCTest specs that mirror them |
| `app/` | SwiftUI app (screens, theme, view models) |
| `appUITests/` | Simulator UI tests and the screenshot tours |
| `tools/seed-db/` | Python tool that builds a database from the spreadsheet |
| `tools/anatomy/` | The muscle diagram (my own drawing); `node tools/anatomy/generate-swift.js` writes the Swift data file |
| `docs/design/` | Impact maps and HTML mockups of every screen |
| `scripts/run-ui-tests.sh` | UI test runner with a live progress bar |

There is no `LICENSE` file yet, so by default all rights are reserved.
