---
name: layering-and-composition
description: 'Horizontal decoupling, dependency rule and composition root. Use when writing or reviewing backend code to decide which layer a line belongs to, inject time, randomness and IO behind contracts, keep controllers slim, wire dependencies in one composition root, and expose the app through an application interface.'
---

# Layering and Composition

Standing rules for every line you write:
- **Classify code by what it touches, not where it comes from.** Network, DB, filesystem, system clock, randomness, framework = infrastructure.
- **Dependency rule**: domain ← application ← adapter (contracts) ← infrastructure. Inner layers never import infrastructure; use cases depend on roles (interfaces), actors are injected.
- **One composition root** wires everything and is the only place that knows the environment.

## When to use
Writing or reviewing any backend (or frontend core) code; an agent produced a fat controller, inline `new`, hidden imports or `if (env === 'prod')`; a test needs a real DB to check a business rule.

## The four layers
| Layer | Holds | Examples | Tested by |
|---|---|---|---|
| Domain | Data, rules (invariants), relationships, processes. Pure. | Entities, value objects, domain services | Level 1–2 unit tests |
| Application | Use cases: coordinate domain + contracts; app-level rules needing a repository ("user already exists"); time and transactions | `CreateUser`, `PlaceOrder` | Level 3 use-case tests with fakes + spies |
| Adapter | Contracts / ports (roles) | `UsersRepository`, `Clock`, `PaymentService`, `EmailService` | Level 4 contract tests |
| Infrastructure | Actors that touch the world; delivery mechanisms | ORM repositories, HTTP controllers/routes, mail/payment clients, `SystemClock` | Contract (L4), incoming (L6), E2E (L5) |

Why: locality (DB code in one known place) and **testing options**. The most valuable code (rules, edge cases, policies) becomes testable in milliseconds instead of only end-to-end.

## Procedure
1. **Place every line** with the [code placement quiz](./references/placement-quiz.md): which module/feature, and which layer.
2. **Slim controller**: parse request → call one use case → map result to response. No rules, no SQL, no `repo.save`. Map every outcome to the status code and stable error code from the [API and data contracts](./references/api-and-data-contracts.md) (one error envelope, PUT vs PATCH, optimistic locking, bulk, soft delete, versioning, payload limits).
3. **Use case depends on contracts** passed via constructor. Return expected failures as values (`{ type: 'AlreadyCreated' }`), not exceptions.
4. **Time and randomness are roles**: inject a `Clock` / `IdGenerator`. `new Date()` and `Math.random()` never appear in domain or application code. Time is an application concern (the use case knows *when*; the state machine changes when told).
5. **Start with an interface** for each real seam; move to an abstract class only after the rule of three. No interface without a second actor (a fake counts only if it is covered by a contract test).
6. **Composition root** (see [composition root](./references/composition-root.md)):
   - Build the dependency graph like Russian dolls: infra actors → repositories → use cases → application interface → delivery (web server, CLI, workers).
   - Read the environment **once** here; choose real or fake actors here; create DB connections once at bootstrap, not per request.
   - Start with plain constructor wiring ("poor man's DI"); adopt a DI container only when this file gets messy.
   - Open long-lived resources once at startup, close them in reverse order at shutdown, and refuse to start when required config or a critical dependency is missing (`observability-and-config`).
7. **Application interface**: express everything the app can do as one object grouped by module (`app.users.register`, `app.orders.placeOrder`). The app implements it with real use cases; REST/GraphQL/CLI adapters receive the app and only delegate. Incoming-adapter tests replace the app with a fake and check that each endpoint calls the right use case with the right parameters. Without it, "you end up building your app within your framework."
8. **Optionally enforce boundaries** with architecture tests (a dependency-rule test library for your language) so domain/application folders cannot import framework packages.

## Exit gate
- Domain and application import no framework, ORM, HTTP, clock or random APIs.
- Each business rule has a fast test that runs without DB or web server.
- Exactly one place reads environment variables / chooses implementations.

## Anti-patterns to refuse
- Fat controllers / anemic domain: HTTP parsing, rules and SQL in one handler; `this.repo.save` in a controller.
- Injecting a concrete ORM client into a use case.
- `new Date()` inside entities; random IDs generated in the domain.
- Environment checks scattered through services; imports pulled in "willy nilly" inside controllers; per-request DB connections built inside repositories.
- Cyclical dependencies from copy-paste wiring.

## AI guardrails
- AI tools happily generate fat controllers with ORM calls inline. Ask for a use case behind a repository interface plus an in-memory fake, and the generated rules become testable in milliseconds.
- Generated code is the new "paste from Stack Overflow": inline `new`, hidden imports, scattered env checks. Insist on constructor injection and a single composition root so the dependency graph stays auditable and every piece stays swappable for fast tests.

Sources: essentials-physical--horizontal-decoupling, essentials-physical--composition, architecture--code-placement, architecture--app-interface, cheatsheet--design-rules; fastapi-genai-skillset → foundation-contracts/status-contract, foundation-contracts/SKILL, data-crud-patterns/crud-checklist, data-crud-patterns/concurrency-bulk, data-crud-patterns/soft-delete-audit-semantics, observability-operations/multi-app-composition-mounted-subapps, integration-reliability/fastapi-concurrency-long-task-thesis
