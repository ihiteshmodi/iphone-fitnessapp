---
name: frontend-architecture
description: 'Frontend architecture for React, Vue or any view library. Use when building a page, screen or component, or reviewing UI code where components mix API calls, state and business rules (forms, hooks, data fetching). Moves logic out of components into a read side (presenter, view model) and a write side (controller), testable without the UI.'
---

# Frontend Architecture: Own the Control Center

Standing rules:
- **"If you need to start React to test your features, React is doing the coordination."** A view library becomes a framework when you let it coordinate. Aim to test ~90% of feature behavior without starting the view library.
- The frontend uses the same stereotypical architecture as the backend: components are incoming adapters, controllers are use cases, the API client is an outgoing adapter.
- Organise by **features**, not pages or components (see `feature-first-structure`).

## When to use
Any frontend feature, form, data-fetching, state or hook work; reviewing generated UI code; choosing a state library; evaluating any frontend library.

## The split
**Read side** (data flows down): gateway / API client → cache (frontend "database", global state) → observer (notifies subscribers) → **presenter** (builds view models, hosts selectors) → **view model** (exactly what the component renders) → component.

**Write side** (intent flows up): component → **controller** (one per use case or a cluster) → **domain object** (decides if the command may proceed; validation) → **repository** (sends via gateway, updates cache) → gateway → backend. The cache change flows back down the read side reactively.

The **pure middle** (presenters, controllers, domain objects, repositories with a fake gateway) is plain code and is where the tests live (`frontend-testing`).

## Procedure (per feature)
1. Start from the approved `.feature` file; the frontend shares the backend's acceptance spec.
2. Define the **view model** the screen needs (shape of what is shown), then the presenter that builds it from the cache. Selectors ("2 left") live in the presenter, not the component.
3. Define the **controller** method per user intent (`register`, `createTodo`), named by intent, not `submitForm`.
4. Put rules and validation in **domain objects / value objects**; share value objects with the backend through a shared package instead of duplicating validation.
5. Repository + gateway contract: the only code that knows the backend URL/shape. Reads return the simplest shape straight from the store/API; **domain objects are for writes only** (no "mapper hell" on reads).
6. Global state = a small observable store (cache + observer). No state library is required; choose one only if it plays a role you need.
7. Component last and thinnest: get the view model from the presenter, subscribe for updates, forward intent to the controller. Ephemeral form/toggle state may stay in the component.
8. **Wrap framework rules you can't avoid** (router hook, data hooks) behind your own small abstraction (`routingService`), so controllers/presenters never call hooks.
9. Wire presenters/controllers/repositories in a composition root and pass them into the component tree.
Details and code: [read side](./references/read-side.md), [write side](./references/write-side.md), [state management](./references/state-management.md), [before/after todos](./references/before-after-todos.md).

## Evaluating any frontend library (Redux, Pinia, Query, router…)
1. Read its docs for doings and knowings: what does it actually do and know?
2. List those responsibilities.
3. Map each to an object stereotype and layer (e.g. a store/reducer = cache + coordinator, infrastructure; `dispatch` = updating the store; selectors = presenter logic).
4. Decide where it plugs in and what stays out. A state library "has nothing to do with features."

## Strategy dial
Small/medium apps or an unvalidated MVP may start with E2E tests and simpler components; carve the read/write split when internal complexity justifies it. Say which you chose and why. Logic-heavy apps (editors, audio tools, drag-and-drop builders) need real frontend domain models; front-loading logic on the client also speeds feedback.

## Anti-patterns to refuse
- Components that fetch, map DTOs, validate and patch the cache (React as control center).
- Queries or cache/store access inside components; selectors in component files.
- Hooks doing coordination, or hooks leaking into controllers.
- A state library for literally everything; hoisting toggle/form state into global state.
- Loading domain objects for reads and mapping them into view shapes.
- Duplicated frontend/backend validation.
- Organising by pages/components or building a component library first (inside-out).
- Over-architecting a tiny app without strategic justification.

## AI guardrails
Ask an assistant for "a React todo list with an API" and you get `useEffect` fetching, inline validation and a custom hook that coordinates everything. Name the roles in the prompt: "presenter builds a view model, controller calls a domain object, repository talks to the gateway, component only renders". The logic then ends up in plain objects that a fast test can check.

Sources: frontend--control-center, frontend--read-side, frontend--write-side, frontend--state, frontend--structure-nfrs, frontend--same-architecture, abstraction-rdd--stereotypes
