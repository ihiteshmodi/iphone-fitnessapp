# Whoop 5.0 integration (later)

Status: **not built.** This is the plan to come back to if the app ever reads Whoop data. The rules come from the program notes (Vol 06: cardio, recovery, sleep). They are paraphrased and give only the numbers the app would need.

## Why
Whoop already measures heart-rate zones, HRV, resting heart rate and sleep. Today the app can only ask about these in the skippable check-in. With Whoop data the checks below would run by themselves, with no extra logging.

## Data needed from Whoop (export or API)
| Data | Used for |
|---|---|
| Workouts: start, duration, sport, time in each HR zone, average and max HR | Zone 2 minutes, hard sessions, gray-zone drift, cardio vs lifting spacing |
| Max HR (set or measured) | Zone limits as % of max HR |
| Daily resting HR and HRV (overnight) | Recovery trend against your own 2–4 week baseline |
| Sleep: total time, bed and wake time | 7–9 h check, steady wake time |
| VO2 max estimate (if Whoop gives one) | Trend only |
| Strain (optional) | Load spikes week to week |

## Checks it would drive (Room for improvement → Trends)
| Check | Rule | Note |
|---|---|---|
| Zone 2 weekly minutes | At least 150 min/week of moderate cardio. Build to 3–5 Zone 2 sessions of 30–60 min. Starting from nothing: 20–30 min × 3 days. | Zone 2 ≈ 60–70% of max HR; the talk test wins if max HR is unsure |
| 80/20 split | About 80% easy, 20% hard (1–2 interval sessions a week) | Weekly chart |
| Gray zone | "Easy" sessions that drift above Zone 2 waste effort | Flag the session, suggest slowing down |
| Hard sessions | 1 a week is the staple, 2 is fine, 3 is the most. None when tired, after poor sleep, unfuelled or on heavy leg days | Uses sleep and HRV of that morning |
| Norwegian 4×4 | 10 min warm-up, 4 × 4 min at 90–95% max HR with 3 min at ~70% between | Optional template; expect roughly +7–10% VO2 max over ~8 weeks |
| Fat max | Most fat burnt per minute at about 45–65% of VO2 max (individual) | Information only. The payoff of Zone 2 is mitochondria built over weeks, not the fuel burnt in a session |
| Cardio vs lifting | Best on different days; next best 3–6 h apart; lift first if same session; keep intervals away from the heaviest leg day | Uses lift sessions from the app |
| VO2 max retest | Every 8–12 weeks | Watch estimates can be off by several points: trend, not value |
| HRV and resting HR | Compare with your own 2–4 week average. HRV low **and** sleep poor for a few days → cut sets or intensity for a few days. Resting HR several beats above normal → tired, stressed or ill | Never compare with other people or brands |
| Sleep | 7–9 h; one wake time 7 days a week; a weekend running 2 h late counts as jet lag | Total time and timing only |
| Deload signals | Add to the app's deload check: resting HR up, sleep worse, HRV down for days | Joins the existing key-lift-drop trigger |

## Deliberately left out
- **Sleep stage percentages and 90-minute cycle tracking.** The notes say tracker stage data is rough, and chasing it becomes an obsession (orthosomnia). Total sleep, timing and the HRV/RHR trend are enough.
- **Daily "readiness score" targets.** Same reason: trends, not single days.
- **Steps target.** The notes give no number.

## Open questions for when this is built
- Whoop API (needs an app registration and OAuth) or a manual CSV export import? The app runs in LiveContainer with no server, so a periodic export import is likely simpler.
- How far back to import (the 2–4 week baseline needs at least 4 weeks).
