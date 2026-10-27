Feature: Log sets
  As the lifter I want to record weight and reps per exercise so that next week's workout reflects what I did.

  Scenario: Log a week of sets from my notes
    Given "Triceps Pushdown" is in the exercise library
    When I log on 2026-10-23: 45 kg × 10, 45 kg × 9, 40 kg × 12
    Then 3 sets are stored for "Triceps Pushdown" on 2026-10-23
    And Day 3 now recommends from the heaviest set, 45 kg × 10

  Scenario: Log an exercise that is not in the library yet
    When I log "Cable Crunch" 30 kg × 15 on 2026-10-23 and choose muscle "Abs"
    Then "Cable Crunch" is added to the library with muscle "Abs"
    And the set is stored

  Scenario Outline: Reject invalid sets
    When I log <weight> kg × <reps> on <date>
    Then it is rejected with "<message>"

    Examples:
      | weight | reps | date       | message                        |
      | -5     | 10   | 2026-10-23 | Weight cannot be negative      |
      | 45     | 0    | 2026-10-23 | Reps must be at least 1        |
      | 45     | 10   | 2027-02-30 | Date is not valid              |

  Scenario: Bodyweight exercises can be logged with 0 kg
    When I log "Push Ups" 0 kg × 20 on 2026-10-23
    Then the set is stored with weight 0

  Scenario: Delete a mistaken set
    Given a set "Triceps Pushdown" 450 kg × 10 was logged by mistake
    When I delete it
    Then it no longer affects the recommendation

  Scenario: Reaching the top of the rep range asks one question about form
    Given "Leg Extensions" is planned for 8 to 16 reps
    When I log 60 kg × 16
    Then the app asks "Did every rep have a full contraction?" once for the exercise
    And answering stores Yes or No for that exercise on that day

  Scenario Outline: When the question is asked
    Given "Leg Extensions" is planned for 8 to 16 reps and deload is <deload>
    When I log <reps> reps
    Then the question is asked: <asked>

    Examples:
      | deload | reps | asked |
      | off    | 16   | yes   |
      | off    | 17   | yes   |
      | off    | 15   | no    |
      | on     | 12   | no    |

  Scenario: The question is asked only once a day
    Given I answered it for "Leg Extensions" today
    When I log another set of 16 reps
    Then it is not asked again

  Scenario: The answer can be changed
    Given I answered Yes
    When I answer No for the same exercise and day
    Then the stored answer is No
