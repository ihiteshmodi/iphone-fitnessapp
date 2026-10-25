---
name: monolith-vs-microservices
description: 'Deployment topology decision. Use only when the user asks whether to split into microservices, separate services or processes, or how to organise modules in a modular monolith with an event bus. Defaults to a modular monolith and requires an NFR to justify each split.'
---

# Modular Monolith vs Microservices

Standing rule: **every architectural complication must be solidly justified against the negative value it can introduce.** "The least amount of components you have to manage means the least amount of guesses you have to make."

## When to use
- "Should we use microservices?", "split this into a separate service", "which modules run where", "how do modules talk".
- Reviewing an agent-scaffolded multi-service setup.

Not for: folder layout inside one app (`feature-first-structure`) or frontend/backend packaging (`monorepo-layout`).

## Thinking framework
1. **Maintainability and extensibility come from vertical slicing + horizontal decoupling**, not from deployment topology. Fix those first.
2. **Modular monolith ≠ single process.** "Modular monolith does not mean modular process. This is just how you organize your code." Several modules live in one project; at bootstrap you choose which modules share a process.
3. **Subdomain classification drives modules** (from `domain-discovery`):
   - core → a module you build (most of your code),
   - supporting → a module you build reluctantly,
   - generic → a thin module wrapping the external service with the minimum integration code (e.g. billing around a payments provider). Never build auth, SMTP or payments yourself.
4. **Event bus as backbone.** Modules register and subscribe to events; "at the end of the day, we just need coordinators." Start with an in-process bus and everything in one deployable.
5. **Split a module into its own process or service only when an NFR demands it**: independent scaling, isolation of a slow/risky workload (e.g. browser sessions, scheduling), different runtime, team autonomy at real scale. Name the NFR and the extra guesses it creates (observability, messaging, deploys, partial failure, data consistency).
6. **Partial failure is designed, not discovered.** Cross-module work is event-driven with compensating events (see `event-driven-decoupling`). Never a transaction script across modules.

## Default layout
```
src/
  modules/
    <core-context>/        build it (e.g. feedbook)
    <supporting-context>/  build reluctantly; may run in its own process (e.g. sessions)
    <generic-context>/     thin wrapper around an external service (e.g. billing)
  shared/
    core/                  event bus, base utilities (accidental complexity)
    domain/                shared domain descriptions (events, ids) only when truly shared
```

## Decision output (`docs/design/<project>/architecture.md`, section "Topology")
| Module | Classification | Process / deployable | NFR justifying a separate process (or "none") | Events published / consumed |
|---|---|---|---|---|

## Anti-patterns to refuse
- Microservices as a starting point "for scalability" with no NFR.
- The `makePurchase` transaction script: get cart → check inventory → bill card → update inventory → send email in one call. A crash between billing and the inventory update leaves an invalid state. Model each subdomain as its own state machine reacting to events instead.
- Shared database tables across modules as the integration mechanism.
- Building generic subdomains in-house.

## AI guardrails
An agent can scaffold ten microservices in an afternoon, but the operational guesses (observability, messaging, deploys, partial failure) do not shrink with it. Default to a modular monolith with explicit module boundaries and event contracts. Split processes only when an NFR justifies the extra guesses.

Further reading named in the course: Vaughn Vernon, *Strategic Monoliths and Microservices*.

Sources: architecture--monolith-vs-microservices, ddd-feedbook--architecture
