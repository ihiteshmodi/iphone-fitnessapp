---
name: state-machines-invariants
description: 'Domain modelling for states and business rules. Use when a concept has a status or lifecycle (orders, invites, bookings) or a rule like "X only after Y" or "make it impossible to...": define states, transitions, events and invariants, size aggregates, and build encapsulated entities and value objects with one test per transition.'
---

# State Machines and Invariants (Stateful Guess Point, Level 2)

Standing rules for the whole task:
- **Invariant = rule = business logic.** It lives inside the domain object, never in callers.
- **Encapsulation exists to protect the way the model changes.** It must be impossible to put the object into an invalid state from outside.
- The domain is pure: no time, randomness, IO, framework or database inside it.

## When to use
- `domain-discovery` handed over a state piece we own, or a feature mentions status, lifecycle, "only when", "can't … after …".
- You see public setters, string status fields, or validation scattered in controllers / use cases.
- Writing or reviewing entities, value objects, aggregates.

Not for: stateless transformations (use `tdd-test-writing` at level 1) or coordination across collaborators (level 3, `fa2str-workflow`).

## Procedure
1. **Start at the goal and work backwards.** Write the final state first, then the states that must come before it. ("You see what happens when you start from the end? It's the technique.")
2. **Draw the state machine** (mermaid `stateDiagram-v2`): states, valid transitions (arrows), the event emitted on each transition, and forbidden transitions. Example: washing clothes can't jump from *NotWashed* to *Clean*.
3. **List invariants**: which transitions are forbidden, which states a concept may be in, which data must be present and valid.
4. **Size the aggregate per command.** An aggregate is the *minimum data a command needs to evaluate its rules*; it is a transaction / consistency boundary (a level-3 idea), not a DTO.
   - Separate per-command shapes are fine (`create user` needs email + password; `edit user` does not need the password). Pull up a common type only after the rule of three.
   - Reference other aggregates by ID; never load a whole graph ("9,000 other things").
   - Lists: design for the worst case (reordering should touch pointers, not every item).
   - Boundary test: walk the state-change code line by line; if the process could die midway and leave a half-done state, the boundary is wrong.
   - Logic spanning two state machines → a stateless domain service that returns a plan the application layer applies.
5. **Implement with this shape** (any language; illustration in [domain object patterns](./references/domain-object-patterns.md)):
   - Private constructor + static `create(input)` that returns `Entity | DomainError` (or the language's result/either idiom).
   - Inside `create`: check presence → create value objects (each validates itself) → collect validation errors → construct. Return early with the first error, naming the property.
   - Expected failures are **returned**, not thrown. Throw only for programmer errors.
   - Transitions are intention-revealing methods (`acceptInvite()`), guarded by the invariant, that record a domain event. No public status setter.
   - Deletion of a business record is usually a transition too (`delete()` → `Deleted`, `restore()` back); see soft delete and audit in `layering-and-composition` API and data contracts.
   - No early base classes (`AggregateRoot`, `Result`) until you need them three times. Grow your own small result types.
6. **Test by transition** (TDD, assert first; see `tdd-test-writing`):
   - One `describe` per transition (`create`, `acceptInvite`, …).
   - One test per arrow and one per forbidden arrow. Use `it.each` for presence/validation rows.
   - **State verification**: act, then inquire into state (`getStatus()`, `getEvents()`).
   - Use builders to reach a starting state without replaying history (see `tdd-test-writing`).
   - Every new abstraction (guard, value object, error type) gets its own test.

## Outputs
- `docs/design/<feature>/state-machines.md`: one diagram + invariants list per state piece.
- Domain code under `src/modules/<context>/domain/` with co-located or mirrored tests.

## Exit gate
- Every arrow and every forbidden arrow in the diagram has a passing test.
- No public setters, no string-typed status, no IO in domain code.
- Each command's aggregate holds only the data its rules need.

## Anti-patterns to refuse
- Anemic model: public fields + `setStatus(string)` with rules in a service or controller.
- Validation in the entity instead of value objects; throwing for expected domain failures.
- `new Date()` / random IDs inside entities (inject from the application layer).
- One giant aggregate loaded for every command; transaction-script commands (`makePurchase`) that bill, update stock and email in one call.
- Premature base classes or copied utility libraries.

## AI guardrails
- Agents generate public setters freely. Invariants encoded inside the object (guarded transition, no setter) mean generated callers cannot push the system into an invalid state.
- Ask for the shape, not "a PreReaderInvite model": private constructor, static `create` returning `Entity | DomainError`, value objects owning validation, one `describe` per transition. Point the tests at the invariants (accepted → accepted errors, exactly one `InviteAccepted` event).
- The state diagram is the review checklist.

Sources: ddd-feedbook--state-machines, ddd-feedbook--aggregates, ddd-feedbook--prereaderinvite, cheatsheet--design-rules; fastapi-genai-skillset → data-crud-patterns/soft-delete-audit-semantics
