---
name: test-strategy
description: 'Choose which tests to write and at which level. Use when planning tests for a feature or project, deciding the subject under test and verification type (result, state, communication), writing E2E acceptance tests with protocol drivers, or adding tests to legacy code. Maps guess points to test levels 1 to 6.'
---

# Test Strategy: Levels, Boundaries, Verification

Standing rule: **isolate exactly what you want to test and forget everything else.** Tests exist because everything is a guess; each test puts a boundary around one guess. "You want the highest level of confidence for the least amount of work, based on where you currently are."

## When to use
Planning tests for a feature (after `architecture-decisions`), choosing a level for a new test, reviewing a test suite, or adding tests to untested code.

## Guess points as test levels
| Level | Guess point | Subject under test | Verification | Typical test |
|---|---|---|---|---|
| 1 | Stateless | Pure function / static method | **Result** only | Concrete examples → parameterized table |
| 2 | Stateful | Entity, value object, state machine | **State** (act, then inquire) | One describe per transition; builders for initial state |
| 3 | Application | Use case with injected collaborators | Mixture + **communication** (only level where you verify calls) | In-memory repos + hand-written spies. **Developer boundary**, ~80% of the work |
| 4 | Outgoing adapter | Repositories, gateways, clock implementations | Contract | One spec looped over every implementation (fake + real) |
| 5 | System (E2E) | Whole system as a black box | **Result** only | Acceptance test via protocol driver. **Customer boundary**: one per feature, happy path + 1–2 sad paths |
| 6 | Incoming adapter | Routes / controllers / API shape | Correct use case called with correct params | API/driver test against a fake application interface |
| — | Execution | The product in use | Metrics (KPIs) | Not a test; closes the loop |

The mapping is not strict; these are the predominant types. State or communication checks at E2E are bad practice.

## Three verification types
- **Result**: direct inputs → direct outputs; environment unchanged. The only type black-box E2E can do.
- **State**: act on a model with no direct output, then inquire into its state (design the inquiry API by wishful thinking).
- **Communication**: the subject talks correctly to dependencies. *Indirect inputs* (state of injected dependencies, e.g. "user already exists" in the repo) and *indirect outputs* (calls made: `save`, `send`). Hardest, most valuable.
Result + state in one test is fine.

## Procedure
1. **Name the guess** each test validates. Pick the layer that owns that guess ("a job post can't be edited after 48 hours" → domain; "API shape stable for 3 clients" → incoming adapter).
2. **Outer loop**: one acceptance test per feature from the `.feature` file (level 5), shared by every platform. Use the [4-layer acceptance structure](./references/acceptance-4-layers.md).
3. **Inner loop**: level-3 use-case tests for every scenario (one success, many failures), then levels 2/1 as new concepts appear. Find the failures with the [edge-case classes](./references/edge-cases-and-operational-tests.md); the same file lists the cache, startup/shutdown and outgoing-call tests to add when that code exists.
4. **Push down what E2E can't see**: emails sent, events published, cache hits → level 3 with spies. Widen the subject to include the event bus only when verifying a temporally decoupled chain.
5. **Every fake gets a level-4 contract test** (`test-doubles-and-contracts`).
6. **Incoming adapters**: level-6 tests that the endpoint extracts input and calls the right use case.
7. **Choose the overall strategy by ROI** (pick, then write it down):
   | Option | Scope | Choose when |
   |---|---|---|
   | A. Use cases + real DB | Application → real DB, builders for setup | Squeezing a bit more confidence tactically; add incoming tests |
   | B. Controller → real DB | Web framework → real DB | A nice middle ground if you don't want E2E; can get expensive |
   | C. Use cases with fakes + E2E (default) | Hundreds of fast use-case tests + a few E2E | Most projects: "combine those two and we're in really good shape" |
   Equivalent framing: (1) E2E + carve inward with high-value unit tests (best start for task-based UI apps), or (2) incoming contract tests + high-value integration tests (many clients, e.g. REST + GraphQL).
8. **Numbers to aim for**: E2E = happy path + 1–2 sad paths per feature; ~12–20 parameterized high-value tests; roughly 1 E2E : ~10 level-3 tests; ~10–12 application scenarios per acceptance test. Fast tests must also be valuable; they run in the commit phase and should give ~80% confidence.

## Legacy / untested code
"Stop the bleeding" first: do the features that must work right now work? Pin the main flows with E2E characterization tests (tailor's pins) before restructuring. Short on time: E2E on the main flows, then high-value unit tests. Weird third-party API: add more outgoing (contract) tests there. Never rewrite from scratch.

## Outputs
`docs/design/<feature>/test-strategy.md`: chosen option, outer-loop test, list of level-3 scenarios, contracts needing contract tests, incoming-adapter tests, what runs in the commit vs acceptance phase.

## Anti-patterns to refuse
- E2E-only or unit-only ("you're always going to fail"); state/communication assertions in E2E.
- Testing only through the UI because the code is coupled; coupling is "the enemy of testing".
- One testing dogma for every project.
- Mock-heavy tests of private helpers; library mocks of your own roles with no contract test.

## AI guardrails
- Picking the level is the judgment call agents get wrong most often: browser E2E for every edge case, or mock-heavy tests of private helpers. Name the level and verification type in the prompt: "level-3 use-case test, in-memory repo, spy on the mailer."
- When agents write the code, the boundary and verification type are your main lever. State and communication checks catch code that returns the right value but never saves or emits. Contract tests stop an agent-written fake from drifting from production.
- Each guess point's tests are the acceptance gate for agent output.

Sources: essentials-physical--subject-system-verification, workflow--guess-points, testing--roadmap, testing--verification, testing--acceptance, testing--strategies, testing--no-time, cheatsheet--guess-points, cheatsheet--testing-rules; fastapi-genai-skillset → testing-quality/edge-case-matrix, testing-quality/cache-and-lifecycle-tests, testing-quality/test-stability-retries-telemetry
