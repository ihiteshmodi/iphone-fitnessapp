---
name: monorepo-layout
description: 'Monorepo layout for frontend, backend and shared code. Use when setting up or reorganising a repo with several packages or apps (e.g. React or Vue frontend, Node backend), fixing messy imports between packages, or deciding what goes in a shared package (DTOs, value objects, acceptance specs).'
---

# Monorepo Layout: Frontend, Backend, Shared

## When to use
- Creating a repo with frontend + backend (+ shared) packages, or moving to workspaces.
- Deciding whether a DTO, validation rule or test belongs in a shared package.

Not for: module structure inside one package (`feature-first-structure`) or service topology (`monolith-vs-microservices`).

## Rules
1. **A monolith inside a monorepo is fine**: frontend and backend in one repo, sharing code via package-manager workspaces (npm/pnpm/yarn workspaces, or the language's equivalent).
2. **Layout**: `packages/frontend`, `packages/backend`, `packages/shared`. Each package follows feature-first structure internally (`src/modules/<capability>/<feature>`, `src/shared/`, mirrored `tests/`).
3. **What goes in `shared`** (only what both sides truly need):
   - the acceptance specs (`.feature` files): **one acceptance test per feature, shared by every platform**, never rewritten per environment;
   - DTOs (wire shapes);
   - value objects / validation both sides need, so validation is not duplicated (later, when needed).
   Never put frontend-only domain objects or backend persistence in `shared`.
4. **Each side has its own layers.** Backend: controllers → use cases → domain → repositories. Frontend: components → controllers/presenters → domain objects → repositories/gateways (see `frontend-architecture`).
5. **README explains `packages/`.** `src/` and `tests/` are knowledge in the world; uncommon folders are not. Add a README table of contents: how to add a feature, how to run each package's tests.
6. **Hosting is an architecture guess point** (SSR framework, backend-served frontend, or separate hosts). Decide it in `architecture-decisions` and prove it in the walking skeleton.

## Reference tree
```
<repo>/
  package.json            { "private": true, "workspaces": ["packages/*"] }
  README.md               explains packages/, how to add and test a feature
  packages/
    frontend/
      src/modules/users/registration/   presenter, controller, repository
      src/shared/                       observer store, api client, router wrapper
      tests/
    backend/
      src/modules/users/registration/   controller, use case, input/output
      src/shared/core/                  base classes only when needed
      tests/
    shared/
      src/dtos/                         CreateUserDTO, UserDTO
      src/domain/                       value objects both sides need (later)
      tests/acceptance/registration.feature
```

```ts
// packages/shared/src/dtos/users.ts (TypeScript illustration)
export type CreateUserDTO = { email: string; username: string; password: string };
export type UserDTO = { id: string; email: string; username: string };
// imported by both sides via the workspace package name, e.g. '@app/shared'
```

## Anti-patterns to refuse
- Copy-pasting DTOs or validation between frontend and backend.
- A `shared` package that becomes a dumping ground (utils, helpers, unrelated base classes).
- Separate acceptance specs per platform for the same feature.

Sources: architecture--monorepo, frontend--write-side
