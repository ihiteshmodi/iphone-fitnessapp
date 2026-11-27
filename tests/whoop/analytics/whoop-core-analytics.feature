Feature: Part 3 Core Physiological Engine (kAlgoVersion = 133)

  As the owner wearing a WHOOP 5.0 / 4.0 band
  I want exact glass-box HRV/RHR, 4-stage sleep & naps, self-excluded 28d Readiness & tempIllnessFlag, and sex-specific Banister Strain/Zones/Energy
  So every physiological metric matches the peer-reviewed openstrap_analytics specification without population-constant fallbacks.

  Scenario: Substrate plausibility gates reject (0,0,0) gravity, out-of-range HR/RR, and cross-generation skin-temp seams
    When evaluating substrate gates on HR, RR, and 1 Hz gravity samples
    Then HR outside 25..230 maps to 0, RR outside 250..2400 is rejected, (0,0,0) accel is marked invalid (never immobile), and Gen5 skin_temp_c converts to centi-Celsius without mixing into Gen4 ADC baselines

  Scenario: Lipponen-Tarvainen RR artifact correction, overcount & ACF1 jitter gates, 5-min headline RMSSD, and 3h nocturnal RHR trough
    When RR intervals contain an isolated ectopic beat, a compensatory recovery beat, and a 3-beat dropout run
    Then single-beat ectopic is Catmull-Rom spline interpolated, compensatory beat is demoted to normal, multi-beat run is dropped without interpolation, overcounted (>1.10) or white-jitter (ACF1 < -0.35 without RSA peak) nights abstain, headline RMSSD averages valid 5-min windows, and nocturnal RHR finds the lowest 30-min >=90%-covered trough only when TST >= 3h

  Scenario: 4-stage sleep segmentation, Gen5 lie-in trim, review-gated daytime naps, and editable sleep overrides
    When 1 Hz gravity and HR/RR span an overnight sleep with a 15-min Gen5 wake lie-in tail
    Then bandTrimmedOffsetSec trims the wake tail, cardioStager classifies wake/light/deep/rem with Webster rescore and <3m deep merge, naps require >=15m stillness + <=0.95x awake HR dip and stay review-gated until accepted or manually edited, and sleep overrides update in place

  Scenario: Self-excluded 28d Readiness composite, calibrated logistic score, tempIllnessFlag, and Exercise-Protected 0-21 Strain & Energy
    When computing Readiness on day D against 20 prior days of ln_rmssd, rhr, and resp_rate
    Then valuesBefore strictly excludes day D, Autonomic 0.70 splits across HRV+RHR, |Z| > 5.0 abstains, tempIllnessFlag fires elevated on >=2 consecutive z >= 2.0 nights (or lutealConfound during luteal phase), and Banister net TRIMP prevents quiet afternoon sitting from debiting morning exercise while mapping 0..400 net TRIMP to 0..21 Strain
