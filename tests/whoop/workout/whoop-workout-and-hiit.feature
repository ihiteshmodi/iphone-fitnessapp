Feature: Live Workout Session, Set Timestamps, Dual-Mode HIIT Haptics, and AutoWorkoutDetector

  As the owner running lifting and cardio sessions in LiveContainer with a WHOOP 5.0 band
  I want live 0x03 HR sessions with editable start/end times, per-exercise HR correlation via set timestamps, throttled UNUserNotificationCenter zone updates (no ActivityKit), Dual-Mode HIIT haptics (0x13/0x4F with 10s hysteresis), and reviewable AutoWorkoutDetector proposals
  So workouts, interval triggers, and unlogged HR spikes work reliably on sideloaded hardware and remain 100% editable.

  Scenario: WorkoutSessionService toggles 0x03 live HR, correlates per-exercise HR from set timestamps, and recomputes stats when end_ts is edited backward
    When I start a lifting session at t=1000, log Bench Press sets at t=1200..1500, and accidentally stop the session late at t=7000 before editing end_ts back to t=3600
    Then starting and stopping emit 0x03 live HR frames, Bench Press correlates peak/mean HR over its set window, and editing end_ts to 3600 recomputes session HR/zones/strain strictly over 1000..3600

  Scenario: DualModeHiitEngine triggers 0x13 Gen5 / 0x4F Gen4 haptics on time intervals and HR thresholds with a 10-second hysteresis cooldown
    When running HR-Threshold HIIT (high=172 bpm, low=130 bpm) on Gen5
    Then crossing >=172 bpm emits a 0x13 haptic frame and flips to recovery, a rapid fluctuation 4 seconds later is suppressed by the 10s cooldown, and dropping <=130 bpm after >=10s emits a 0x13 haptic frame to start the next round

  Scenario: AutoWorkoutDetector detects >=12m elevated HR bouts, bridges <=15m unrecovered pauses, rescues low-wrist-motion cycling via +25 bpm onset, and skips already-saved workouts
    When 1 Hz HR has a 20-min stationary cycling bout with low wrist motion (<0.15g) but a +32 bpm 3-minute cardiac onset, and another bout overlapping a saved workout
    Then the cycling bout is proposed in activity_suggestions without auto-creating a workout, the overlapping bout is suppressed, and accepting an edited proposal creates a clean workout session
