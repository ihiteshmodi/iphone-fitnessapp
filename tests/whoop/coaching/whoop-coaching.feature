Feature: 3-Layer WHOOP Coaching & Mode Override Engine

  As the owner training across General Health and 90-day specialization blocks (Maximizing VO2 Max, Maximizing HRV, Reducing RHR)
  I want static Layer 1 tips, General Health baseline checks (Zone 2, Gray-Zone, 80/20, +5% cap, 1:2 spacing, 3h lifting benchmark, Red recovery context override, dynamic sleep need -> target bedtime), and Layer 3 mode overrides
  So daily recovery, cardio volume, and sleep targets adapt without orthosomnia or false-positive Red alarms.

  Scenario: Red Recovery Context Override keeps normal strain on late-meal/poor-sleep single Red day, but triggers deload on 3+ consecutive Red days
    When today's recovery is Red (28%) after a 2.1h meal-to-sleep gap with normal yesterday strain (9.5) and 1 Red day
    Then keepNormalStrainOverride is true and deloadTriggered is false
    When consecutiveRedDays reaches 3
    Then keepNormalStrainOverride is false and deloadTriggered is true

  Scenario: Dynamic Sleep Need scales by day load, credits valid naps, and computes Target Bedtime backward from Wake Time
    When today is an endurance cardio day (8.0h base) with 0.5h sleep debt, a valid 30m nap before 13:00, and targetWakeHm "07:00"
    Then net tonight sleep need is 8.0h and targetBedtimeHm is "23:00"

  Scenario: Mode A (Maximizing VO2 Max), Mode B (Maximizing HRV), and Mode C (Reducing RHR) apply their exact overrides
    When Mode A is active with Anaerobic Battery limiter, 55 min >85% HRmax, and 450 min total weekly cardio
    Then split target is 60/30/10, 50-min >85% target is met, and the 7h (420m) weekly cardio ceiling warning fires
    When Mode B is active with a 120-min Zone 3-5 long endurance run at 152 bpm
    Then Gray-Zone warning is suppressed on the long run and the 4-Day Post-Endurance Rebound Tracker evaluates Day 1..4 status
    When Mode C is active with 3,800 steps vs 11,200 steps and a failed noon caffeine check in Microcycle Week 2 vs Week 3
    Then easy cardio duration scales 40m (<5k) -> 0m + 30m secondary (>10k) at 110-130 bpm, caffeine cutoff flags, and microcycle multiplier shifts 1.10x (Wk2) -> 0.50x Zone-2-only deload (Wk3)
