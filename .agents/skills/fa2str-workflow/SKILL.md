---
name: fa2str-workflow
description: 'Conductor for building any approved feature with FA2STR (Find, Architect, Automate, Specify, Test, Refine) and the ideal developer workflow: outer-loop acceptance test, inner-loop use-case tests, n loops down to smaller units, then adapters, UI, deploy. Use when implementing, starting a project, shipping an MVP, or when stuck.'
---

# FA²STR and the Ideal Developer Workflow

Standing rules for the whole task:
- **The main skill is problem decomposition.** Run FA²STR at whatever level the problem arrives, then drill in with *n* loops.
- **Humans own the spec, agents own the build.** The human approves the theoretical guesses and the acceptance scenarios (the `.feature` file) in plan mode. In agent mode, work autonomously through every loop below; do not stop for approval while tests are red.
- **Tests come from the spec, before the code they verify**, and each new test is seen failing once (red for the right reason). Batching several scenarios of one use case per loop is fine. End state: every scenario has a test and every test passes. Commit at each green scenario or refactor (`commit-discipline`).

## When to stop in agent mode (otherwise keep going)
- A scenario is ambiguous, missing, or contradicted by what you discover → ask; update the `.feature` file only with approval.
- A hard-to-reverse decision appears that `architecture-decisions` didn't settle (storage, platform, public API shape).
- A test can only pass by changing an approved scenario or weakening an assertion.
- The same failure persists after two different fixes → zoom out and report instead of looping.

## When to use
After `clarify-requirements` produced an approved `.feature` file (and `architecture-decisions` a test strategy for anything non-trivial). Also for: starting a new project, an MVP, a new feature on an existing product, or debugging a change → fail loop (zoom out: stop, draw it, clarify responsibilities, descend one level).

## FA²STR: six steps, input → output
| Step | Input | Output |
|---|---|---|
| **Find** | Problem statement / story / vague example | Responsibilities (doing / knowing), concrete examples, the **starting guess point** (subject under test). At feature level: role, why, capabilities → stories, acceptance criteria, examples. |
| **Architect** | Responsibilities + examples | The subject under test and its signature. At higher levels: patterns, components, testing strategy, broad-stroke architecture. |
| **Automate** | Responsibilities, examples, SUT | How it will be tested: harness + scripts that also run in the pipeline. Success criteria defined before code ("think backwards, start at the end"). |
| **Specify** | One example (agent mode: the scenarios of one use case) | Failing test(s) (**red**). At feature level the first is the outer-loop acceptance test. |
| **Test** | The failing test | Passing code: *fake it* / smallest step when practising by hand; the obvious implementation is fine for agents. Commit (**green**). |
| **Refine** | Passing code | Refactor duplication seen **three times**. Commit, line up the next example, loop to Specify. |

Upfront design = Find + Architect + Automate. Emergent design = Specify + Test + Refine.
- Everything is a doing or a knowing. Most tests are one doing with many knowings.
- More than ~4 collaborating pieces? Go to paper and run `responsibility-driven-design`.
- **n loops**: when emergent design needs a construct that doesn't exist yet, run FA²STR again one level down (Find → … → its own red/green/refactor), then come back up. Start anywhere; you always drill in.

## The ideal developer workflow (95% of the time, any side of the stack)
| Step | FA²STR | Guess points | Output |
|---|---|---|---|
| 1 Clarify theoretical guesses (non-negotiable) | Find | Problem, solution | Stories, acceptance criteria, concrete examples |
| 2 Broad-stroke architecture | Architect | Architecture | Patterns, components, testing strategy, how tests plug into the pipeline |
| 3 Walking skeleton | Automate | All physical levels, thinly | Testable architecture + deployed tiny slice + pipeline (`walking-skeleton-delivery`) |
| 4 Feature work, n loops | Specify / Test / Refine | 5 → 3 → 2/1 → 4/6 | Shipped feature, then next feature |

On an existing project with architecture, pipeline and test strategy in place, steps 2–3 shrink to a checklist: start at the outer-loop test.

## Per feature, step by step
1. **Failing acceptance test (level 5)** from the approved `.feature` file: system boundary, user's language, result verification only. It may mention pages or things that don't exist yet. One per feature, shared by every platform. Run it once and confirm it fails because the feature is missing.
2. **Move in one level: failing use-case test (level 3)** at the developer boundary, with in-memory fakes and hand-written spies. ~80% of the time is spent here.
3. **Loop over every scenario**: one success, many failures. Name things that don't exist yet and carve them out, recursing into level 2 (state machines) and level 1 (pure functions) and back up. "Any time we mention a new abstraction, we write new tests."
4. **Remaining ~20%**: outgoing adapter contract tests (level 4) so fakes match reality, incoming adapter tests (level 6), then hook up the UI (components + component tests).
5. **Acceptance test green → `code-review` → commits → report.** Deploy and infrastructure tests follow through the pipeline.

**Final report (the human review point after agent mode):** scenarios covered (with test names), tests added per level, anything skipped and why, decisions made, open questions.

Heuristics:
- E2E: happy path + 1–2 sad paths. Then ~12–20 parameterized high-value tests. Roughly 1 E2E : ~10 level-3 tests, and those give ~80% of the confidence.
- Push what E2E can't sensibly see (an email was sent) down to level 3 with a spy.
- If testing a feature requires starting React (or any view framework), the framework is coordinating; move the logic out (`frontend-architecture`).
- It's an ideal. Legacy code and cut corners are real; use it to measure how far off you are.

## Kickoff on a new project
1. Get the deployment pipeline working.
2. Write the end-to-end test; make it pass in a production-like environment (walking skeleton).
3. Jump into level-3 tests.
With a familiar standard architecture: plan, clarify inputs/outputs, process-model, then go straight to level 3 and let required inputs create the entities and value objects. Starting level 3 from one feature: create the use case, go through all success and failure scenarios, let concepts emerge; ask what goes in, what must come out, what must change all at once. Forget the word "aggregate" at first; no base classes until you need them.

## MVP and when to go light
The workflow is the same for an MVP and a mature product. Only time, effort and the quality of your guesses change.
- Unvalidated MVP, zero validated guesses: push one theoretical guess through fast on a good foundation; one acceptance test per feature + a few tests for internals; add defensive tests once value is validated.
- New feature on an existing product: full workflow, Architect step is a checklist.
- Platform with stacked guesses (shared infra, known services): skip guesses at some guess points.
How many loops to test at "depends on the score of the game"; say which you are skipping and why.

## Outputs
Failing → passing acceptance test, inner tests, production code, typed commits, the final report, updated `docs/design/<feature>/test-strategy.md` if the plan changed. Worked outer + inner loop example: [sync feature](./references/worked-example-sync.md).

## Anti-patterns to refuse
- Writing all application code, then trying to deploy ("all these weird CORS errors"). Deploy as early as possible.
- Mixing feature work with architecture setup (discovering DB issues mid-feature).
- E2E-only or unit-only strategies ("you're always going to fail"); state or communication checks at E2E.
- Leaving internal logic untested because "it's not a feature".
- Inventing a different process for MVPs; heavy polish on an unvalidated MVP.
- Re-prompting / re-editing blindly in a change → fail loop.

## AI guardrails
- AI shrinks the feed-forward step to seconds, so **feedback becomes the bottleneck**. Generated code is still a guess; tests, CI and real-user signals turn it into verified value.
- Find + Architect + Automate is the spec you hand an agent: responsibilities, an examples table, the SUT with its signature, and a runnable test command.
- Specify + Test are how you verify the agent's output: tests written from the approved scenarios turn "done" into a green run, not a claim. Tests written *after* the code tend to confirm whatever the code does; that's why test-first stays even for agents.
- Refine: agents abstract too early. The rule of three is the review filter.
- Name the level and verification type in every inner-loop prompt ("level-3 use-case test, in-memory repo, spy on the mailer"). Agents otherwise write browser E2E tests for every edge case or mock-heavy tests of private helpers.
- A deployed walking skeleton gives the agent a tested frame to extend one slice at a time.

Sources: workflow--fa2str, workflow--fa2str-stateless, workflow--worked-example, workflow--n-loops, workflow--guess-points, workflow--ideal-workflow, workflow--to-physical, workflow--mvp, essentials-metaphysical--zoom-out, cheatsheet--fa2str, cheatsheet--ideal-workflow
