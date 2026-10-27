# Round 2 changes (from the first real-phone test, 26 Oct 2026)

Role: Hitesh, one user, trains 3 days a week, tracks sets, weight, calories and measurements on an iPhone.
Goal: log and correct data without leaving the app, and see what the numbers really mean.
Each item is one slice: one `.feature` file, tests first, one commit. Items are ordered by value.

## 1. Log a set for another day
- Given I am on Leg Extensions, When I tap Add set, Then the form has a Date field that starts on today.
- Given I pick yesterday and save 55 kg x 10, Then the set is stored on yesterday's date and not shown under today.
- Given I pick a future date, Then Save is refused with "Pick today or an earlier date".

## 2. Edit a logged set
- Given a set of 55 kg x 10 on 24 Oct, When I tap it and change it to 52.5 kg x 12, Then the same set is updated (it is not deleted and re-added) and the progress chart changes.
- Edit can also change the date. Delete stays available. Validation is the same as when adding.

## 3. See and fix earlier sessions on the exercise screen
- Today's list shows only today's sets (a few rows), so it does not grow with time.
- A collapsed "Earlier sessions" section lists past sessions newest first, each expandable to its sets, each set editable and deletable. "See all" shows the whole history of that exercise.

## 4. Name days by weekday actually works
- Cause today: no day has a weekday, so the label falls back to "Day 1/2/3".
- Given "Name by weekdays" is on and a day has no weekday, Then Edit plan shows "Set a weekday" on that day.
- Given Day 1 = Monday, Day 2 = Tuesday, Day 3 = Wednesday (set in the app, not hard-coded), Then the Workout tab shows Mon, Tue, Wed.

## 5. Calories: default per day, override any day, recent list
- A default daily calories value (and the existing macro rules) lives in Body settings. The default is dated: changing it applies from a start date onward and never rewrites earlier days. The start date defaults to today and can be set to yesterday or any earlier date.
- Example: the default was 2,900 until 25 Oct. On 26 Oct I change it to 3,000 with start date 26 Oct. Then 25 Oct and earlier still count as 2,900, and 26 Oct onward (including future days) count as 3,000. Starting it on 25 Oct instead makes 25 Oct count as 3,000 too.
- A day I overrode by hand keeps its override whatever the default does.
- A weekly average that spans the change mixes both values day by day, for example 3 days at 2,900 and 4 days at 3,000.
- "Recent calories" under Recent weigh-ins shows the last 7 days. Each day shows its effective value: the override if one exists, otherwise the default. Tap a day to set, change or clear an override. Macros can be overridden per day the same way.
- The weekly formula uses the 7-day average of the effective daily values.
- Example: default 2,400, Tuesday overridden to 3,000 and Friday to 1,800, so the 7-day average is 2,400.

## 6. "What your weight says": actual deficit or surplus
- Uses the notebook formula already ported (two-week weight change, 3,500 kcal per lb).
- Shows: maintenance estimate, actual daily deficit or surplus in kcal, and the plain phase (Deficit / Maintenance / Surplus), next to the planned mode.
- Assumption to confirm: within +/-100 kcal per day counts as Maintenance.
- Example: planned mode "Maintenance", average 82.0 kg last week vs 82.5 kg the week before, so the card says "You are actually in a deficit of about 400 kcal/day".

## 7. Reach and edit data older than 7 days
- "See all" on Recent weigh-ins, Recent calories and Earlier sessions.
- More tab, "Edit past data": pick any date, then see and edit that day's sets, weigh-in, calories and measurements.

## 8. Measurements: grow or reduce
- Each site has a direction, Grow or Reduce, changeable on the measurement screen.
- Default Reduce: Waist, Waist (belly button), Body Fat (belly button). Everything else is Grow.
- Grow site at or above target is achieved, shown as "0.7 in ahead of target" (Shoulders 46.0 vs 45.3). It is not "lose 0.7".
- Reduce site above target shows "lose 2.2 in" (Waist 30.2 vs 28.0). A Reduce site at or below target is achieved.
- The progress ring follows the same direction.

## 9. Muscles worked: show every side that has a worked muscle
- Today the card frames only primary muscles, so hamstrings added as secondary on Leg Extensions never show.
- Now there is one zoomed figure per side (front, back) that holds any worked muscle, primary or secondary. Secondary muscles are drawn in the lighter green and the legend says Primary / Secondary.
- Example: Leg Extensions has quads (primary, front) and hamstrings (secondary, back), so two figures.

## 10. More tab, Import database
- Same picker problem as the first screen (greyed files, Open does nothing).
- Show the files found in the app folder with a "Use <name>" button, and the "What the app sees" card, like the first screen. The file picker stays as an extra option.

## Guesses still open
- The +/-100 kcal Maintenance band (item 6).
- Whether the weekly formula should ignore days with no calories and no default (it falls back to the default).
