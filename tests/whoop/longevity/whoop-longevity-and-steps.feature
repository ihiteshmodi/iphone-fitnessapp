Feature: Gen5 Step Filtering, VO2 Max, Fitness Age, Vitality, Body Age, and ACSM Treadmill VO2 Max

  As the owner tracking daily steps and weekly longevity metrics from my WHOOP 5.0 band without HealthKit
  I want Gen5 activity_class-filtered step counting, Nes/Uth VO2 Max & Fitness Age with 0-21 Strain normalization, Gompertz Body Age & Vitality, and an editable ACSM Treadmill VO2 Max log
  So wrist arm motion and sleep tosses never inflate steps and weekly longevity metrics stay mathematically exact.

  Scenario: Gen5 step counter wraps u16 cleanly, counts only walk/run activity_class in {1, 2}, rejects sleep tosses, and divides by stepTicksPerStep
    When Gen5 step_count wraps across 65535 -> 10 during walking (activity_class = 1), ticks during desk typing (activity_class = 0), and has a 2-second nocturnal wrist toss vs a 6-second coherent nocturnal bathroom walk
    Then desk typing and nocturnal tosses are rejected, wraparound walking and coherent bathroom walk are counted, and stepTicksPerStep scales the total cleanly

  Scenario: FitnessAgeEngine normalizes 0-21 Strain to 0-100 Effort, selects Nes 2011 with waist cm or Uth 2004 fallback, and VitalityEngine computes Gompertz Body Age & 0-100 Vitality
    When 6 of the last 7 days have nocturnal RHR (median 50 bpm) and 4 days have Strain = 12.6 (normalized Effort = 60 >= 30)
    Then FitnessAgeEngine computes PAI, Nes VO2 Max (with waist cm) and Uth fallback (without waist cm), and younger Fitness Age
    And VitalityEngine aggregates RHR, sleep hours, sleep consistency, RMSSD vs age norm, and steps into Body Age and Vitality > 50

  Scenario: ACSM Treadmill VO2 Max calculator scales submaximal HR-reserve runs and supports full in-place editing
    When I log a steady treadmill run at 10.8 km/h (180 m/min) and 2% grade at HR 158 bpm (RHR 50, MaxHR 190)
    Then VO2 is 0.2*180 + 0.9*180*0.02 + 3.5 = 42.74 mL/kg/min, submaximal VO2_max scales via %HRR, and editing speed/HR updates the stored log in place
