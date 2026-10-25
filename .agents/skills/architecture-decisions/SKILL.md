---
name: architecture-decisions
description: 'Architecture guess point. Use when choosing components, tools, libraries, platforms, storage, client vs server split, or the testing strategy for a feature or project, and when mapping unfamiliar jargon (hexagonal, CQS, sagas) to principles. Produces a broad-stroke architecture and test strategy before code.'
---

# Architecture Decisions (Architecture Guess Point)

Standing rule: **theoretical before physical.** "You never want to be making physical guesses unless you have your theoretical guesses sorted." Code generation is cheap; reworking a platform or storage choice is not. Hard-to-reverse calls are proposed by the agent and **decided by the human**.

## When to use
- After `clarify-requirements` (and `domain-discovery` when there are several contexts), before the walking skeleton or a new feature's code.
- The user asks "which library / database / framework / queue", "SSR or SPA", "should this run on the client or server", "how do we test this".
- An agent-suggested stack needs review.
- Unfamiliar jargon appears: file it under an essential with the [jargon map](./references/jargon-map.md).

Niche follow-ups: `monolith-vs-microservices` (deployment topology), `monorepo-layout` (frontend/backend/shared packages).

## The stereotypical architecture (default, same on frontend, backend, desktop)
Hexagonal, onion, ports & adapters, clean, layered: "one architecture, many names." Its four laws:
1. **CQS**: a read path and a write path. Commands change state; queries read.
2. **Event-based**: features chain in time through events (temporal decoupling).
3. **Layers of concerns**: domain (data, rules, relationships, processes) ← application (use cases) ← adapters (contracts/ports) ← infrastructure (frameworks, DB, network, clock).
4. **Dependency rule**: inner layers never know infrastructure directly; use cases depend on contracts.

Why layers exist: everything is a guess, and layers give you different places to test those guesses with different speed and confidence. Application-layer tests exercise the core without the UI, DB or web server.

**Complexity triggers** (add structure only when the need is real):
| Need | What it justifies |
|---|---|
| Test business rules without the DB / fat handlers doing too much | Separate application (use case) layer from delivery |
| Many high-value unit tests on the core | Adapter contracts (repositories, gateways, clock) with fakes |
| Features that happen *after / when* something else | Events + handlers (coordinator / event bus) |
| Responsibilities no pattern covers | Responsibility-driven design (`responsibility-driven-design`) |

## Procedure
1. **List functional requirements and NFRs.** "The non-functional part is where the real complexity lies." Ask about speed / bundle size, SEO, security, availability, real-time, scale, offline, cost. See [NFR → tool table](./references/nfr-tools.md).
2. **Strategic design, the 4 jobs:**
   - *Stereotype* components: for any library/framework/service, name which responsibilities it covers and which layer it belongs to.
   - *Develop* components that don't exist (glue / custom abstractions) using RDD.
   - *Integrate*: fill the responsibility gap between systems that don't talk with thin glue code.
   - *Prioritize*: core = build, supporting = build reluctantly, generic = buy. Start with the most valuable context.
3. **Run RDD at the component level**: responsibilities → roles → collaborations, then find tools that play those roles. Choose tools by **responsibility and NFR**, never by popularity. One component can play several roles (e.g. Redis: cache, pub/sub, key-value, queue).
4. **Decide the client/server split** (frontend projects): what must be server-rendered (SEO for user content, never sending protected pages to anonymous users), what can live in the client, what needs real-time transport. Moving responsibilities between client and server is the main driver.
5. **Default shape**: modular monolith (module per bounded context) + in-process event bus. Fewer components = fewer guesses. Deviate only when an NFR justifies it.
6. **Testing strategy** (bridge to physical): one acceptance test per feature (outer loop) + level-3 use-case tests (inner loop) + contract tests for every fake + adapter tests. Details in `test-strategy`.
7. **Draw the broad-stroke architecture**: modules, deployable units, external services, event bus, where each test level plugs into the pipeline.
8. **Replace "it depends" with the scenario**: run it through systems thinking (theoretical → physical → which guesses → time budget) and state what it depends on.

## Outputs
- `docs/design/<feature-or-project>/architecture.md`: requirements + NFRs, component table (`component | responsibilities/role | layer | build/buy | why`), client/server split, diagram, open risks.
- `docs/design/<feature-or-project>/test-strategy.md` (draft; refined by `test-strategy`).

## Exit gate
- Every chosen tool is justified by a responsibility and an NFR.
- The user approved hard-to-reverse choices (platform, storage, deployment topology).
- Test strategy names the outer-loop test and the inner-loop level.

## Anti-patterns to refuse
- Choosing tools before the problem and solution guess points are clear; getting stuck choosing components.
- Pattern-first thinking: applying patterns with no responsibility behind them.
- Building commodity systems (auth, email, payments) yourself.
- Microservices or extra infrastructure without an NFR that demands it.
- Architecture that ignores testing (components stacked so only UI tests are possible).

## AI guardrails
- An agent will suggest a library for anything and write the glue in seconds. Deciding what is core, what to buy and which NFRs rule an option out stays human. Review an AI-suggested stack by asking, per component, "which role does it play, for which NFR?"
- Agents produce code inside one pillar easily; trade-offs across architecture, design, testing and strategy are the human's job.

Sources: cheatsheet--twelve-essentials, essentials-theoretical--strategic-design, essentials-theoretical--tools-per-guess-point, ddd-feedbook--architecture, architecture--architect-role, architecture--one-architecture, essentials-metaphysical--jargon-map, frontend--structure-nfrs, metaphysics--four-pillars
