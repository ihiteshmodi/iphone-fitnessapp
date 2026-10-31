# Impact map: Diet tracking

**Why.** What a lifter eats decides the result as much as the training. Today the calories per day are typed in by hand and the diet lives somewhere else. Keeping the diet in the app makes the calorie target follow what was really eaten.

**Who.** The lifter, using one iPhone, offline.

**Goal.** Know the calories, protein, carbs, fat and cost of every day without typing them, and have the calorie target use them.

| Capability | Feature | What the lifter gets |
|---|---|---|
| nutrition | [food-library](../../../tests/diet/food-library/food-library.feature) | A library of foods and recipes with nutrition and price. Editing a food updates every day that used it. |
| nutrition | [portions](../../../tests/diet/portions/portions.feature) | "4 biscuits" worked out from a pack, a label and a piece count. |
| nutrition | [supplement-cycles](../../../tests/diet/supplement-cycles/supplement-cycles.feature) | Items that are on for some weeks or days and off for others. |
| nutrition | [diet-plan](../../../tests/diet/diet-plan/diet-plan.feature) | The daily plan, in meals. A change starts on a date and never rewrites earlier days. |
| nutrition | [daily-diet](../../../tests/diet/daily-diet/daily-diet.feature) | Each day: the plan counted as eaten, items unticked for that day, extras on top, totals against the targets. |
| nutrition | [diet-calories](../../../tests/diet/diet-calories/diet-calories.feature) | The calories per day, the weekly average and the calorie target come from the diet. |

**Out of scope for this step.** The order planner (what was bought, daily use, run-out dates).

## Rules decided with the user

- One plan every day. A plan applies from a date onward (the same idea as the calorie default).
- Nothing counts until it is ticked. Ticking is per day and per item, and one box ticks or clears a whole meal. Items that are off their cycle are never ticked. Changing a quantity for one day is not needed. (Earlier the plan counted as eaten by default; days from that time were converted so they keep what they counted.)
- An extra is a food eaten on top of the plan, entered as pieces, grams or a share of a pack.
- Calories of a food are the label value when it is typed, otherwise 4 x protein + 4 x carbs + 9 x fat.
- A recipe is a food made of other foods. Its nutrition and cost are always worked out from the current ingredients.
- Editing a food recalculates every past day. Cost uses current prices.
- Protein is a minimum (180 g by default). The fat limit is the smaller of 20% of the day's calories and the weight cap (grams = weight in lb x 0.4, using the 7-day average weigh-in).
- A day's calories are, in order: the value typed for that day, the diet, the default.
- Cycles: every day, weeks on and off counted from a Monday, days on and off from a date, chosen weekdays, or training days. An off day is not counted in calories or cost and needs no tick.
- The user's own diet, prices and spreadsheet stay out of the repository. The import tool writes them straight into the user's database file.
