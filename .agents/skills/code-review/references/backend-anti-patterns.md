# Backend and Design Anti-Patterns to Catch in Review

Load during review of backend, domain or test code.

| Anti-pattern | Why it hurts | Fix / skill |
|---|---|---|
| Package by infrastructure (`routes/`, `controllers/`, `services/`) | Features invisible; changes sprawl | Feature-first folders (`feature-first-structure`) |
| Fat controller / anemic domain: HTTP, rules and SQL in one handler; `repo.save` in a controller | Rules only testable end to end | Slim controller → use case → contract (`layering-and-composition`) |
| `new Date()`, `Math.random()`, IO inside domain/application | Hidden infrastructure; untestable time | Inject `Clock` / ID generator |
| Environment checks everywhere; imports pulled in "willy nilly" | Graph not auditable; nothing swappable | Single composition root |
| Mocks that lie: fakes with no contract test; inline library-mock soup | "We're only testing our mocks" | Hand-written fakes + contract spec (`test-doubles-and-contracts`) |
| Implementation-detail test names ("sets result to true and error to null…") | Locks tests to one implementation | Responsibility names (`tdd-test-writing`) |
| `else-if` chains | Hard to read and extend | Early-return guards |
| Big-bang commits, commits on red, design done off-screen in one jump | No reviewable story | Red-green-refactor commits (`commit-discipline`) |
| Code-first / DB-first / API-first design: thinking in endpoints | Builds things with no reason to exist | Back to `clarify-requirements` |
| Awaited side effects appended to a command (`makePurchase`) | One failure strands the rest; invalid states | Events + handlers + compensation (`event-driven-decoupling`) |
| Components built for weeks, deploy last | Infra surprises land last | Walking skeleton (`walking-skeleton-delivery`) |
| Premature interfaces (`IFoo` + `FooImpl`), factories, abstract bases | Indirection with no second actor | George Clooney test (`responsibility-driven-design`) |
| Everything is a "service" | No dominant role; references everywhere | Object stereotypes |
| Public setters / string status fields on entities | Callers can create invalid states | Guarded transitions (`state-machines-invariants`) |
| Throwing for expected domain failures | Control flow by exceptions | Return error values |
| E2E-only or unit-only strategies; state/communication checks at E2E | Slow or blind suites | `test-strategy` |
| Local hooks as the only quality gate; manual walkthroughs | Bypassable; doesn't scale | CI pipeline gates (`walking-skeleton-delivery`) |
| Modelling the domain before the theoretical guesses | Patterns with no value | `clarify-requirements`, `domain-discovery` |
| Rewriting legacy code from scratch | Loses unknown behavior | Characterization tests first (`understand-codebase-by-features`) |
| Comments that restate the code | Noise that drifts | Better names; comment only why |
| Gold-plating beyond the approved scenarios | Unvalidated guesses shipped | Stay inside the `.feature` file |
