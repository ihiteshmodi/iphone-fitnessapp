---
name: tdd-test-writing
description: 'How to write each test and drive code with red-green-refactor. Use whenever writing or reviewing a unit, use-case or domain test: AAA backwards with wishful thinking, red for the right reason, fake it, transformation priority, rule of three, responsibility-style test names, it.each example tables, and builders for fixtures.'
---

# TDD Test Writing

Standing rules for every test:
- **Write the assert first, from the spec.** Overwhelm comes from vagueness; start at the end. "Vagueness does not compile."
- **Every new test is seen failing once** before the code that makes it pass. One behavior per `it`. Commit on green (`commit-discipline`).
- Names state *what* (a doing or a knowing); examples hold the *how* (concrete values).

## Agent mode vs practising by hand
| Practice | Agent mode | By hand (learning, katas, tricky logic) |
|---|---|---|
| Tests derived from the approved scenarios before the code | **Required** | Required |
| Each new test seen red for the right reason (or flip the switch) | **Required** | Required |
| Responsibility names, one behavior per `it`, `it.each` tables, builders | **Required** | Required |
| Refactor on the third repeat; refactor XOR behavior | **Required** | Required |
| One example per loop | Optional: batch the scenarios of one use case | Required |
| Fake it / climb TPP one rung at a time | Optional: obvious implementation is fine | Required |
| Commit after every red/green/refactor micro-step | Optional: commit per green scenario or refactor | Required |

Why test-first still matters for agents: tests written after the code describe what the code does, not what the user asked for, so they pass even when the code is wrong. Seeing each test fail once proves it can catch a regression.

## When to use
Any time a test is written or reviewed, at any level (after `test-strategy` picked the level).

## The loop (by hand; agents may batch steps as the table above allows)
1. **Pick one example.** Start with the **most complex example** when designing the API (it settles most design early); when implementing, add examples one at a time.
2. **AAA backwards + programming by wishful thinking**: write the **Assert** (the expected output / state / call), then the **Act** (call the API as if it already existed — would you enjoy using it?), then the **Arrange**. Everything you write is an API for someone else.
3. **Red for the right reason**: export a stub (function/method that returns nothing useful) so the test fails on logic, not on a missing import or compile error.
4. **Green**: *fake it* (return the constant) until duplication forces generalisation; use the *obvious implementation* only when confident. Climb the **transformation priority premise** one rung at a time: nil → constant → scalar/variable → single statement → conditional (`if`) → loop/collection → mutation. If you need a new variable, loop or mutation for one new example, question the step.
5. **Flip the switch**: break the code briefly, watch the test go red, restore. Proves the test can fail.
6. **Refine**: refactor only when duplication appears **three times**. Refactor XOR add behavior: never add examples during a refactor. Tests stay green throughout.
7. Commit, line up the next example, repeat.

## Naming and structure
- `describe` = the subject or the responsibility; `it` = a responsibility spec: "can detect valid passwords", "knows that a password shorter than five characters is invalid". Positive phrasing ("knows dog is not a palindrome", not "does not know…").
- Never leak internals into names ("sets result to true and error to null…", "returns object with errors array").
- After three similar examples, move to `it.each` / table-driven tests: each row holds input **and** expected output together; put the varying reason in the data, not in hard-coded names; named example sets (`inputWithNegativeNumbers`, not `firstInput`). New example = new row (open-closed).
- One `it`, one expectation of behavior. Separate `it`s or rows instead of asserting 15 and 45 in one test.
- Order-independent assertions for unordered collections (`toContain` per item, not strict equality on order).
- Type what you invent: a returned shape becomes a named type/interface (a role).
- No `else` chains: early-return guards.
- Stateless subject = plain function or static method, never `new Validator()`.
- Swim-lane readable tests: group by category of behavior with concrete examples; no conditionals in tests.

## Fixtures with builders
A fixture is the **initial state**. If arrange lines only get the system into a state, move them into a builder with **named well-known states** in the domain's language ("scholar's mate", "an author with three pending invites"). Design the builder API by wishful thinking. In-memory repositories can be seeded through builders (store plain objects, mapping like the real store does). Real-DB strategies need builders even more.

Examples (password validator, naming before/after, it.each, builders, TPP): [tdd examples](./references/tdd-examples.md).

## Anti-patterns to refuse
- Starting at arrange and fumbling toward a vague assert (10–15 minutes of setup, then the API doesn't work).
- Big-bang implementation for the first test when practising by hand (maps, loops, variables for example one).
- Refactoring after one or two repeats; adding examples mid-refactor; refactor and behavior in one commit.
- Tests that were never seen failing; tests written after the code to match it.
- Copying someone else's utility classes (`Result`, base entities) instead of growing your own.
- "What" comments in tests or code (`code-review`).

## AI guardrails
- **The approved scenarios are the spec;** the agent turns them into asserts first and fills in act/arrange and the implementation. An agent will happily invent an awkward API that satisfies a vague test, so review the asserts in the final report.
- Responsibility specs make good prompts: a list of "knows that… / can…" titles tells an agent what to build without prescribing how. Reject generated names that leak internals.
- When pairing step by step with an agent (tricky logic), ask for **one** failing test, then "the smallest fake-it change that makes only this test pass", and commit before the next prompt.
- In that pairing mode, use TPP as shared vocabulary: "make this pass with the highest-priority transformation: constant before conditional, no new variables." If the diff adds a `let`, a loop or a lookup map for one new example, reject it and ask one rung lower.

Sources: testing--aaa-backwards, testing--naming, testing--builders, workflow--fa2str-stateless, katas--review-checklist, cheatsheet--testing-rules
