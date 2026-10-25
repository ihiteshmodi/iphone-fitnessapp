# Frontend Anti-Patterns to Catch in Review

Load when the diff touches UI code (components, hooks, stores, pages).

| # | Anti-pattern | Fix (see `frontend-architecture`) |
|---|---|---|
| 1 | Queries / fetch calls directly inside components | Gateway + repository; component reads a view model |
| 2 | Components that fetch, display and decide how to structure information ("too much in one place") | Presenter builds the view model; controller handles intent |
| 3 | A state-management library used for literally everything | Small observable cache; component state for ephemeral UI |
| 4 | Selectors or cache/store access in component files (breaks the dependency rule) | Selectors in the presenter |
| 5 | Hooks doing coordination; hooks leaking into controllers | Wrap framework hooks behind own services (e.g. routing service) |
| 6 | The view library as control center: features only testable by rendering | Controllers/presenters as plain objects, tested without the UI |
| 7 | Massive coupling between clumps of UI code | Insert a contract between clumps so each is tested alone |
| 8 | Loading domain objects for reads and mapping them into view shapes ("mapper hell") | Reads return the simplest shape; domain objects are for writes |
| 9 | Hoisting toggle/form state into global state | Keep ephemeral state in the component |
| 10 | Duplicated validation on frontend and backend | Shared value objects in a shared package |
| 11 | Organising by pages/components, or building a component library first (inside-out) | Feature folders; outside-in from the acceptance test |
| 12 | Only E2E tests because the code isn't structured for anything else | Whole-feature tests on the pure middle (`frontend-testing`) |
| 13 | Over-architecting a small/medium app without strategic justification | Match structure to complexity; state the choice |
