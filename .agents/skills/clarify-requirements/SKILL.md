---
name: clarify-requirements
description: 'Problem guess point and requirement gathering. Use in plan mode, at project start, or whenever the user adds or changes a requirement. Asks who, why, what before how, then produces role, goal, features, concrete Given/When/Then examples and acceptance criteria. Do not use for pure refactors or typo fixes.'
---

# Clarify Requirements (Problem Guess Point)

Standing rule for the whole task: **no physical guesses (code, schemas, endpoints, libraries) until the theoretical guesses below are sorted and the user has confirmed them.** Vagueness does not compile.

**Load companion skills now, not after the exit gate.** This skill never replaces a specialist skill. If the request also contains one of these, load that skill as well and use its questions while clarifying:
| Request contains | Also load |
|---|---|
| A business rule about states: "can't X until Y", "only after", "make it impossible to…", a status or lifecycle | `state-machines-invariants` (ask for states, transitions, forbidden transitions) |
| One word meaning different things, vocabulary, teams or areas, boundaries | `domain-discovery` |
| A third-party or provider API, retries, slow work | `operational-resilience` |
| A page, screen, component or form | `frontend-architecture` |
| Several packages or apps in one repo | `monorepo-layout` |

## Purpose
Turn a vague request into a validated, testable *what*, worked top-down through the abstraction prism:

role (who) → goal (why, pain → benefit) → capabilities → features (what) → stories → acceptance criteria → concrete examples (Given/When/Then) → acceptance test (the crossover from *what* to *how*).

"Never start a project without these four words clearly understood: who, why, what, how."

## When to use
- Plan mode, new project, new feature, or a new/changed requirement arriving mid-implementation (run on the **delta only**, then update the artifacts and resume).
- The user describes a solution ("add an endpoint", "add a table") without saying who it is for or why.
- You are stuck in a change → fail loop: zoom out here first.

Not for: renames, formatting, dependency bumps, or bugs whose expected behavior is already specified by a test.

## Inputs
The request, any existing `docs/design/**`, existing `.feature` files and README. If something below is unknown, **ask**; do not invent roles, goals or rules.

## Procedure
1. **Frame as a system.** Every feature is input → process → output, moving a person from state A to state B. Write one sentence: "<Role> is at <state A>, wants <state B>, and experiences <…>".
2. **Check the framing context.** The same words can be different problems (plain "tic-tac-toe" vs "web-based multiplayer tic-tac-toe" adds concurrency, client/server, rooms, network failures). Ask which context applies. See [framing examples](./references/framing-examples.md) when the request is short or generic.
3. **Value identification (who / why / what).** Establish, in order:
   - Vision: can we say what is being built in one line?
   - Roles + goals: whose goal does this serve, what pain → what benefit? Value depends on the role.
   - Capabilities: what will they be able to do that they cannot now?
   - The 3 roles must all win: user (time back / enriched), customer (revenue), developer (codebase stays easy to change). Name any conflict.
   Use the [question bank](./references/question-bank.md). Ask in small batches (3–5 questions), most important first.
4. **Features → stories → acceptance criteria.** Name features as user-visible capabilities, never as endpoints or tables.
5. **Concrete examples.** For each story write Given/When/Then with real names and values (start state, action, what they see / what changed). Then clauses describe the outcome the user experiences, usually past tense ("an order should have been placed", "an email is sent"); present tense is fine for UI state. One success scenario, then the failure scenarios. Format: [Gherkin and examples](./references/gherkin-and-examples.md).
6. **List the guesses.** Mark which items are validated (user confirmed, data) and which are still guesses. The first guess is always "does anyone care?".
7. **Exit gate.** Stop and get explicit user confirmation before handing off.

## Outputs (write to files, not only chat)
- `docs/design/<feature>/impact-map.md`: vision, role → goal → capabilities → features, open guesses.
- `tests/<capability>/<feature>/<feature>.feature`: stories + scenarios with concrete examples (one `.feature` per feature). This is the spec the agent can't negotiate with.
- Examples table (inputs → expected outcome) inside the feature file or impact map.
- For a mid-task requirement change: a short delta note in the same folder plus updated scenarios.

## Exit gate (all true)
- You can state who it helps, what they achieve, why it is worthwhile, and how we will know it is done.
- Every feature has at least one success and one failure example with concrete values.
- The user approved the feature file. Humans own the outer loop.

## Anti-patterns to refuse
- Code-first / API-first / DB-first: thinking in endpoints and tables before features.
- Skipping concrete examples ("handle errors properly" is not an example).
- Modelling the domain before the theoretical guesses are sorted.
- Gold-plating: rabbit-holing into tooling when the goal is the feature.
- Treating the agent's assumptions as validated value.

## AI guardrails
- An agent cannot decide who you serve or whether they care. When code is cheap, this who/why/what gate is what stops fast generation of features nobody wanted.
- Agents make code cheap but also speed up negative value. Balancing user, customer and developer goals is a human trade-off; organising work around features gives agents testable units.
- A feature file plus a failing acceptance test is the most precise prompt and the best oracle. Without role and goal above it, output drifts to tables and endpoints with no reason to exist.
- When generated code keeps failing, do not re-prompt blindly; restate the *what* (behavior, responsibilities, level) first.

## Handoff
- Language, boundaries, events → `domain-discovery`.
- Components, tools, test strategy → `architecture-decisions`.
- Ready to build → `fa2str-workflow` (it turns the approved feature file into the failing acceptance test).

Sources: metaphysics--mental-models, metaphysics--systems-thinking, metaphysics--essence-purpose-form, metaphysics--value-creation-system, metaphysics--three-roles, metaphysics--four-pillars, metaphysics--how-it-fits, essentials-metaphysical--overview, essentials-metaphysical--abstraction, essentials-metaphysical--prism, essentials-metaphysical--abstraction-in-practice, essentials-metaphysical--feedback-loop, essentials-metaphysical--guess-points, essentials-metaphysical--zoom-out, essentials-theoretical--roadmap, essentials-theoretical--value-identification, essentials-theoretical--role-goal-chain, ddd-feedbook--roadmap, ddd-feedbook--problem, cheatsheet--core-loop, cheatsheet--theoretical-checklist
