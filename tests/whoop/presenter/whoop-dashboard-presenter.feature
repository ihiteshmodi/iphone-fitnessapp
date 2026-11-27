Feature: WHOOP Dashboard, Recovery/Sleep, Longevity & Coaching Presenter

  As the iPhone owner viewing my WHOOP 5.0 metrics across Body, Workout, Diet, Progress, and More
  I want a pure Swift presenter assembling the Recovery-Strain-Sleep 3-hoop triad, 4 contributor sparklines, 4-stage sleep & naps, weekly Longevity (VO2 Max, Fitness Age, Vitality, Body Age), and 4-Mode Coaching + CTL/ATL series
  So every SwiftUI screen stays thin and renders real historical + live 1 Hz telemetry cleanly.

  Scenario: 3-hoop triad orders Recovery (0-100%, left), Strain (0.0-21.0, middle), and Sleep (hours/%, right) and computes Longevity & Coaching
    Given 20 days of WHOOP metric_series history and body measurements with Waist in fitness.sqlite
    When WhoopDashboardPresenter builds the snapshot for 2026-11-26
    Then the triad hoops are ordered ["Recovery", "Strain", "Sleep"] with Recovery in 0..100%, Strain in 0..21, and Sleep showing hours and efficiency
    And the Recovery detail includes 4 contributor sparklines, 4-stage sleep breakdown, target bedtime, and pending nap/workout proposals
    And the Longevity snapshot computes Nes VO2 Max, Fitness Age, Body Age, and 0-100 Vitality
    And the Coaching snapshot computes 4-mode evaluation, 3h lifting benchmark, and CTL vs ATL trend points
