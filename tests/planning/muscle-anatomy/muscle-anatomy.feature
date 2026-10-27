Feature: Muscles worked by an exercise
  As the lifter I want to see which muscles an exercise trains, highlighted on a body diagram,
  so that I know where to focus while I train it.

  Background:
    The catalog has 33 muscle parts in 14 regions. Parts:
      Chest:      Upper chest, Mid chest, Lower chest
      Shoulders:  Front delts, Side delts, Rear delts
      Upper back: Upper traps, Mid traps, Lower traps, Lats, Rhomboids, Teres and rotator cuff
      Lower back: Spinal erectors
      Biceps:     Biceps, Brachialis
      Triceps:    Triceps long head, Triceps lateral head
      Forearms:   Forearm flexors, Forearm extensors
      Core:       Abs, Obliques, Serratus
      Quads:      Rectus femoris, Outer quad, Inner quad
      Hamstrings: Outer hamstring, Inner hamstring
      Glutes:     Glute max
      Hips:       Hip abductors, Hip adductors
      Calves:     Gastrocnemius, Soleus
      Shins:      Tibialis

  Scenario: See the trained muscles highlighted in a small card near the bottom
    Given "Triceps Press" is in the library with muscle group "Triceps" and no chosen muscles
    When I open "Triceps Press"
    Then a small "Muscles worked" card sits after the "How to" card and before "Log sets", which stays last
    And the card shows only the back of the body, zoomed on the arms, with both triceps parts fully highlighted
    And it lists "Primary: Triceps long head, Triceps lateral head"
    And it says "Automatic"

  Scenario: The card zooms on the primary muscles only
    Given "Lat Pulldown" works the lats as primary and the biceps and rear delts as secondary
    When I open it
    Then the card shows only the back of the body, framed on the lats
    And it does not add a front picture just for the secondary biceps

  Scenario: Two pictures only when the primary muscles are on both sides
    Given an exercise whose primary muscles are the quads (front) and the glutes (back)
    When I open it
    Then the card shows a front picture framed on the quads and a back picture framed on the glutes

  Scenario Outline: Where the card frames
    Given the primary muscles are "<parts>"
    Then the card shows the "<views>" of the body
    Examples:
      | parts                                   | views        |
      | Triceps lateral head                    | back         |
      | Upper chest                             | front        |
      | Lats                                    | back         |
      | Biceps                                  | front        |
      | Quad parts and Glute max                | front, back  |

  Scenario: The frame never gets too tight
    Given the only primary muscle is a small one such as the Brachialis
    Then the frame is at least 90 by 90 units of the 200 by 440 figure, so the picture still shows where on the body it is
    And the frame never leaves the figure

  Scenario: Primary and secondary muscles look different
    Given "Champagne Press" works the chest as primary and the front delts and triceps as secondary
    When I open it
    Then chest parts are fully highlighted and the front delts are lighter inside the same frame
    And the legend lists "Primary" and "Secondary" separately

  Scenario Outline: Automatic muscles come from the exercise name and group
    Given "<exercise>" has muscle group "<group>" and no chosen muscles
    Then its primary muscles are "<primary>"
    And its secondary muscles are "<secondary>"
    (the order inside a list does not matter)

    Examples:
      | exercise                                       | group     | primary                                    | secondary                                                   |
      | Guillotine press - incline black chest machine | Chest     | Upper chest                                | Mid chest, Front delts, Triceps long head, Triceps lateral head |
      | Chest Dips Machine                             | Chest     | Lower chest                                | Mid chest, Front delts, Triceps long head, Triceps lateral head |
      | Chest Fly Machine                              | Chest     | Mid chest                                  | Upper chest, Lower chest, Front delts                       |
      | Champagne Press                                | Chest     | Upper chest, Mid chest, Lower chest        | Front delts, Triceps long head, Triceps lateral head        |
      | Lat Pulldown                                   | Back      | Lats                                       | Teres and rotator cuff, Biceps, Rear delts                  |
      | Power Row machine - Orange                     | Back      | Mid traps, Rhomboids, Lats                 | Lower traps, Rear delts, Biceps                             |
      | Triceps Pushdown                               | Triceps   | Triceps lateral head                       | Triceps long head                                           |
      | DB Overhead Triceps                            | Triceps   | Triceps long head                          | Triceps lateral head                                        |
      | Triceps Press                                  | Triceps   | Triceps long head, Triceps lateral head    |                                                             |
      | Preacher Curls                                 | Biceps    | Biceps                                     | Brachialis, Forearm flexors                                 |
      | DB Hammer Curls                                | Biceps    | Brachialis, Biceps                         | Forearm flexors                                             |
      | Belt machine Stiff Leg Deadlift                | Hamstrings| Outer hamstring, Inner hamstring, Glute max| Spinal erectors                                             |
      | Goblet Squat                                   | Legs      | Rectus femoris, Outer quad, Inner quad     | Glute max, Hip adductors                                    |
      | Cable Hip Abduction                            | Legs      | Hip abductors                              | Glute max                                                   |
      | Shrugs                                         | Traps     | Upper traps                                | Mid traps                                                   |

  Scenario: Unknown exercise names fall back to the whole muscle group
    Given "Bicep Station" has muscle group "Biceps" and matches no naming rule
    Then its primary muscles are "Biceps, Brachialis"

  Scenario: An exercise with no group and no clue highlights nothing
    Given "Mystery Move" has no muscle group and matches no rule
    When I open it
    Then no muscle is highlighted
    And the card says "No muscles yet" with a "Choose muscles" button

  Scenario: Choose the entire upper back
    Given I am editing the muscles of "Seated rows mid back"
    When I choose the entire "Upper back" region
    Then Upper traps, Mid traps, Lower traps, Lats, Rhomboids and Teres and rotator cuff are all primary
    And after saving the card says "Customised"

  Scenario: Choose specific parts only
    Given I am editing the muscles of "Seated rows mid back"
    When I set Rhomboids to primary, Lats to secondary and everything else to none
    And I save
    Then the card lists "Primary: Rhomboids" and "Secondary: Lats"
    And the figure highlights only those two parts

  Scenario: Tapping a part cycles none, primary, secondary
    Given a part is not selected
    When I tap it three times
    Then it goes primary, then secondary, then none

  Scenario: Reset to automatic
    Given "Seated rows mid back" has chosen muscles
    When I tap "Reset to automatic"
    Then the muscles come from the naming rules again
    And the card says "Automatic"

  Scenario: Selecting nothing equals automatic
    Given "Preacher Curls" has chosen muscles
    When I set every part to none and save
    Then the card says "Automatic" and shows the automatic muscles

  Scenario: Chosen muscles survive renaming and go away with the exercise
    Given "Tricep Pushdown" has chosen muscles
    When I rename it to "Triceps Pushdown"
    Then the chosen muscles are kept
    When I delete an unused exercise that has chosen muscles
    Then its chosen muscles are deleted too

  Scenario: Both sides of the body exist in the drawing
    Then the figure has a front and a back drawing
    And parts visible from both sides (side delts, upper traps, hip abductors, gastrocnemius) are drawn in both

  Scenario: The editor shows the whole body
    Given I am choosing muscles
    Then both full figures are shown small so I can see what I am choosing

  Scenario: Edit muscles from the exercise library
    Given I opened "Lat Pulldown" in the exercise library
    When I tap "Muscles worked"
    Then I get the same editor, and saving updates the exercise screen too

  Scenario: An older database is upgraded
    Given a version 2 database without chosen muscles
    When the app opens it
    Then it is upgraded to version 3 with an empty chosen-muscles table
    And every exercise shows automatic muscles
