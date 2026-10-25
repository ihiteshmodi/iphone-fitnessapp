# Gherkin, Concrete Examples and the Impact Map

Load when writing `impact-map.md` or a `.feature` file.

## The chain (top-down, never skip a level)
role (who) → goal (why) → capabilities → features (what) → stories → acceptance criteria → concrete examples (Given/When/Then) → acceptance test → code (minimum to pass).

The acceptance test is the crossover from theoretical (*what*) to physical (*how*). It is a "flag post in the future": it fails today and passes when the feature is done.

## Impact map template (`docs/design/<feature>/impact-map.md`)
```markdown
# <Feature or epic>
Vision: <one line>
Role: <who>            Goal: <pain → benefit>
Capabilities: <what they will be able to do>
Features: <user-visible capabilities, not endpoints>
Concrete example: <named person, state A → state B>
Open guesses: <what is not yet validated>
Out of scope: <…>
```

Course example (DDD Forum):
- Role: conference organizer. Goal: get an audience of developers curious about DDD to sell tickets to.
- Features: register, buy tickets, view ticket advert, ask questions.
- Concrete example: James buys three tickets for his company.

## Feature file template
```gherkin
Feature: Buy tickets
  As a conference attendee buying for my company
  I want to purchase several tickets at once
  So that my team can attend together

  Scenario: James buys three tickets for his company
    Given James has three tickets in his cart
    When James purchases the tickets
    Then an order should have been placed
    And an email is sent

  Scenario: Purchase fails when the card is declined
    Given James has three tickets in his cart
    And his card will be declined
    When James purchases the tickets
    Then he should see "Your card was declined"
    And no order should have been placed
```

Rules:
- Real names and values. "Valid data" is not an example.
- Then-clauses describe what the user experiences; past tense for things that happened ("placed", "sent"), present tense is fine for UI state ("I should now be logged in").
- One success scenario, then the failure scenarios. A feature is one success case and many failure cases.
- Write in the user's language. No HTTP verbs, selectors, table names or class names.
- One `.feature` file per feature, stored under `tests/<capability>/<feature>/`. Frontend, backend and other platforms share the same spec.

## Examples table (for parameterized rules)
```gherkin
  Scenario Outline: Password rules
    Given a new user chooses the password "<password>"
    When they register
    Then registration <outcome> because "<reason>"

    Examples:
      | password          | outcome  | reason       |
      | abc               | fails    | too short    |
      | thisIsWayTooLong1 | fails    | too long     |
      | Secret12          | succeeds | -            |
```

## Before / after: code-first vs abstraction-first
- **Before (how first, what never written):** an endpoint with validation, tested once with curl. Nobody can say who it is for or when it is done; verified once by hand.
- **After (what as executable spec, then minimum how):** Gherkin scenarios → failing acceptance test (red) → thinnest code to green.

## Ideal codebase entry path (what the artifacts enable)
README → `tests/` organised by capability → one `.feature` per feature → stories → scenarios / examples → matching `src/modules/<capability>/<feature>/` code. A new developer or agent should find how to do a use case in one or two hops.
