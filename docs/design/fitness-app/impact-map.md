# Impact map: Fitness app (offline iPhone app)

## Vision
An offline iPhone app that replaces the weekly "notes app → spreadsheet → Python notebook → screenshot" loop with one place to log training and get next week's three workouts.

## Role and goal
| Role | Goal (pain → benefit) |
|---|---|
| Lifter (single user, 3 training days per week) | Pain: retyping a week of notes into a spreadsheet, running a notebook, screenshotting results. Benefit: log sets once, see Day 1/2/3 targets instantly, on the phone. |
| Customer | Same person (no revenue). No accounts, no backend. |
| Developer | Domain rules (progression, calories) live in one pure Swift package with tests, so the plan logic is easy to change. |

## Capabilities → features (from the notebook + spreadsheet)
| # | Capability | Feature | Source in notebook / sheet |
|---|---|---|---|
| F1 | Planning | View workout for Day 1/2/3 (sets, rep range, muscle, instructions, working weight, 75%/90% warm-ups, recommendation) | `make_exercise_analysis`, `V5Fullbody_JMK` |
| F2 | Planning | Deload mode (working weight × weight multiplier, default 1; min reps × reps multiplier, default 0.75; no recommendation) | `isdeload`, `deloadweightmultiplier = 1`, `deloadrepsmultiplier = 0.75` |
| F2b | Planning | Exercise detail: instructions, target, last-sessions chart with trend (Improving / Flat / Declining), history, inline set logging (Whoop/Bevel-style day → list → detail) | user UI direction |
| F3 | Planning | Baseline date filter (only history on/after 2026-08-31 counts) | `dategreaterthan` |
| F4 | Planning | Edit the plan in the app: add/delete days, name days by number or weekday, build a day from the library, create new exercises inline, reorder, change sets and rep range | user decision (replaces editing V5 in Excel) |
| F4b | Planning | Exercise library: add/rename exercises, set muscle, write and edit how-to instructions | user decision |
| F5 | Logging | Log sets: date, exercise, weight kg, reps | `Master Sheet` Category=Exercise |
| F6 | Logging | Log body weight and body measurements | `Master Sheet` Category=Weight / Body Measurement |
| F7 | Nutrition | Calorie target: 7-day vs previous-7-day body weight → maintenance estimate, phase, new target, cutting macros; editable calories, goal multiplier and macro rules (protein g/lb, fat %) | `CalorieTracker` |
| F8 | Progress | Measurement progress vs targets (signed, direction-aware); tap a site to edit current and target, log or fix readings, add sites | `analyze_body_measurement_progress` |
| F9 | Progress | Volume progression per muscle, per exercise | `analyse_and_plot_progression_per_muscle` |
| F10 | Data | Import/Export the single SQLite file (manual Drive upload via Files/share sheet) | user decision |
| F11 | Settings | Independent settings: deload (toggle, weight and reps multipliers), history start date (affects all progress views), day naming (numbers or weekdays) | user feedback on mockups |

Out of scope for now: Google sign-in, backend, restore-from-Drive automation, reminders, lbs display (notebook comments say lbs is not required).

## Decisions already confirmed by the user
- Offline, no login, no backend. One SQLite file on the phone.
- Weekly backup = user exports the file and uploads to Drive by hand.
- One-time seed DB built from the spreadsheet (Master Sheet, V5Fullbody_JMK, Exercise mapping), containing all history, which the user places in the app.
- Native Swift/SwiftUI, shipped as an unsigned `.ipa` for LiveContainer.
- Calories are typed in by the user.

## Open guesses (flagged, not blocking)
1. Muscle taxonomy comes from the mapping sheet. Exercises that only exist in the log (104 names) get the most frequent muscle label from the log.
2. Measurement direction (grow/shrink) is inferred from the sign of `target − current`; no per-site config.
3. "Heaviest set" ties (same weight and reps) are broken by the most recent date.
4. Weeks: the plan has Week 1 only; the app treats the plan as a repeating week.
5. Trend rule (Improving / Flat / Declining) is new, not in the notebook: estimated 1RM (Epley) of each session's best set over the last 5 sessions; ±2% band is "Flat". Tunable.
6. Exercise names match case-insensitively and after trimming (Excel VLOOKUP behaves that way; pandas did not). Spelling variants such as "Tricep Pushdown" vs "Triceps Pushdown" stay separate exercises.
