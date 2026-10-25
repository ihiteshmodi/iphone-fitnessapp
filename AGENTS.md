# Engineering Guidelines (Software Essentialist method)

These rules apply to every task in this repository. Detailed procedures live in skills under `.agents/skills/` (mirrored in `.claude/skills/`); load the skill named in the routing table before acting.

## Check
If the user types `essentialist check`, reply only with the phase list below and the skill names under each phase. (Used to verify this file is loaded.)

## Core stance
- **Value-first, never code-first.** Theoretical guesses (who, why, what) come before physical guesses (code, schemas, endpoints, libraries). "Never start a project without who, why, what and how clearly understood."
- **Abstraction**: separate the what from the how; always work top-down: role → goal → features → concrete examples → acceptance test → code (minimum to pass).
- **Feedback loop**: everything is a guess. Feed forward, get feedback (tests, users, metrics), refine. Keep loops tight.
- **Systems thinking**: every feature is input → process → output, moving someone from state A to state B.
- **Three roles must all win**: user (time back or enriched), customer (revenue), developer (code stays easy to change).
- **Four pillars as the trade-off lens**: architecture, design, testing, strategy.
- **Problem decomposition is the main skill**: FA²STR at any level, then drill in with n loops.

## Phase routing (load the skill before acting)
A request often matches several rows: load **every** matching skill, not only the first. `clarify-requirements` never replaces a specialist skill. When a request is about modelling, structure, integration, UI or tests, load that skill too, even if you also clarify first.
| Signal in the conversation | Phase | Skill(s) | Output | Gate |
|---|---|---|---|---|
| Plan mode; new project/feature; user adds or changes a requirement; vague request; stuck in a change→fail loop | 1 Discover | `clarify-requirements` | `docs/design/<feature>/impact-map.md`, `tests/<capability>/<feature>/<feature>.feature` | User approves feature file |
| Several areas or ambiguous words (one word, different meanings); vocabulary; "event storm"; boundaries; build vs buy | 1 Discover | `domain-discovery` | glossary, context map, event storm | No same-context event chains |
| Status, lifecycle, "only when", "make it impossible to", entities, value objects, aggregates | 1 Discover / 3 Build | `state-machines-invariants` | state diagrams, domain objects | Test per arrow and forbidden arrow |
| Which tool/library/DB/framework; client vs server; NFRs; jargon | 2 Design | `architecture-decisions` | `architecture.md`, draft `test-strategy.md` | Human approves hard-to-reverse calls |
| "Microservices?", separate services/processes | 2 Design | `monolith-vs-microservices` | topology table | NFR named for every split |
| Frontend + backend + shared packages; several packages in one repo; messy imports between packages | 2 Design | `monorepo-layout` | repo layout | — |
| More than ~4 collaborating pieces; "where does this go?"; interfaces; god services | 2 Design | `responsibility-driven-design` | role map | One dominant role per object |
| Implement an approved feature; start a project; MVP; ordering the work | 3 Build | `fa2str-workflow` (conductor) | red → green acceptance test, inner tests, final report | All scenarios tested and green |
| New files/folders; README; structure review | 3 Build | `feature-first-structure` | feature folders, mirrored tests | Features visible from the tree |
| Writing backend code; controllers; wiring; status codes, error format, API shape | 3 Build | `layering-and-composition` | layered code, composition root, API and data contracts | No infra in domain/application |
| "after / when / then also / notify / retry" | 3 Build | `event-driven-decoupling` | events, handlers, compensations | No appended awaited side effects |
| Integrating or calling a third-party/provider API or service; timeouts, retries, fallbacks; cache; background jobs; slow requests | 3 Build | `operational-resilience` | gateway actor with timeout, retry and fallback decisions; 202 + task id | Every outgoing call has a timeout and a decided fallback |
| Logging, metrics, alerts, health/readiness; env vars, secrets, per-environment settings; startup/shutdown | 3 Build | `observability-and-config` | settings object, structured logs with request id, readiness | Missing required config stops startup |
| Protected routes, login, user data, CORS, rate limits, hardening before staging/production | 3 Build | `security-baseline` | route classification, auth and rate-limit checks wired | No placeholder auth beyond local/dev |
| First deploy; new stack; CI pipeline; going live | 3 Build | `walking-skeleton-delivery` | deployed slice, pipeline, release gates | E2E green from CI; release gates GO |
| Any UI: page, screen, component, state, hooks, forms; logic mixed into components | 3 Build | `frontend-architecture` | presenter/controller/view model | Feature testable without the UI library |
| Unfamiliar or legacy codebase | 3 Build | `understand-codebase-by-features` | `docs/design/codebase-map.md` | Characterization tests before changes |
| Which tests, which level, E2E design, legacy tests | 4 Test | `test-strategy` | `test-strategy.md`, acceptance tests | Level + verification named per test |
| Writing any test | 4 Test | `tdd-test-writing` | tests written assert-first | Red for the right reason |
| Any fake, mock, spy, stub, clock | 4 Test | `test-doubles-and-contracts` | hand-written fakes + contract specs | Every fake has a contract test |
| Frontend or UI tests (page, screen, component, form) | 4 Test | `frontend-testing` | feature tests without the UI | — |
| Change finished, before commit; "review this"; "is this production ready?" | 5 Review | `code-review` | pass/fail table (+ production-readiness review for backend/ops changes) | All rows pass |
| About to commit | 5 Review | `commit-discipline` | local commit (`feat`/`fix`/`refactor` or plain) | Green only; no push without approval |

**New requirement mid-implementation**: pause, run `clarify-requirements` on the delta only, update `docs/design/` and the `.feature` file, get approval, then resume `fa2str-workflow`.

## Who decides what
**Plan mode (human approves, then the agent may build):**
1. Theoretical guesses: impact map + `.feature` file with acceptance scenarios. Humans own the spec.
2. Hard-to-reverse architecture choices.

**Agent mode (autonomous):** build through every FA²STR loop without stopping for approval, even while tests are red. Tests are written from the approved scenarios before the code they verify, and each is seen failing once. Stop only when a scenario is ambiguous or contradicted, an unsettled hard-to-reverse decision appears, a test could only pass by changing an approved scenario, or the same failure survives two different fixes.

**After agent mode:** a final report (scenarios → tests, anything skipped, decisions, open questions), `code-review` passed, commits made. This is the human review point.

## Pre-commit chain (fixed order)
`code-review` (comments say why → kata checklist → backend anti-patterns and layer guards → premature interfaces → fakes without contract tests → frontend anti-patterns if UI changed → production-readiness review if backend, integration, config or deploy code changed) → `commit-discipline` (green only; `feat` / `fix` / `refactor` prefix, plain message for everything else) → push only when the user asks.

## Hard guardrails
- No `new Date()`, randomness, IO, framework or ORM calls in domain or application code; inject roles (`Clock`, repositories, gateways).
- Controllers parse → call one use case → map. No rules or repository calls in controllers.
- Environment checks and wiring only in the composition root.
- Every outgoing call has a timeout; retries are bounded; fallbacks are visible. Missing required config stops startup.
- Never put secrets or tokens in code, logs, responses or commits.
- Every fake has a contract test; library mocks only for trivial stubs.
- Tests from the spec before the code; every new test seen failing once; every scenario ends with a passing test; commit only on green.
- Never push, force-push or rewrite shared history without explicit approval.

## Artifact conventions
- Design notes: `docs/design/<feature>/` → `impact-map.md`, `glossary.md`, `subdomains-context-map.md`, `event-storm.md`, `state-machines.md`, `architecture.md`, `test-strategy.md`.
- Code: `src/modules/<capability>/<feature>/` (customer), `src/shared/` (developer).
- Tests mirror features: `tests/<capability>/<feature>/<feature>.feature` + specs.

## Mindset one-liners
- Anxiety means lack of clarity: go back up to the theoretical guesses.
- Zoom out when stuck: stop, draw it, clarify responsibilities, descend one level. Don't re-prompt or re-edit blindly.
- Think backwards: name the end state first (assert first, acceptance test first).
- No more "it depends": run the scenario (theoretical → physical → which guesses → time budget) and say what it depends on.
- File new jargon under one of the 12 essentials (`architecture-decisions` jargon map) instead of chasing it.
