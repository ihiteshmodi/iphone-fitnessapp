---
name: feature-first-structure
description: 'Vertical slicing and codebase structure. Use when creating a project, adding a feature, deciding where new files or folders go, writing a README, or reviewing a package-by-infrastructure layout (controllers/, services/, models/). Makes features first-class in folders and tests (modules, features, operations).'
---

# Feature-First Structure (Vertical Slicing)

Standing rule: **"If you can't see your features from the folder structure alone, there's a good chance maintainability is under pressure."** Mental models show up in code: think in features, not endpoints or tiny scripts.

## When to use
- New project or new feature: decide the folder for every new file before creating it.
- Reviewing structure, or a feature change that sprawls across `controllers/`, `services/`, `models/`.
- Writing or updating the README.

## Vocabulary (thick → thin slices)
- **Module / capability**: a bounded context or capability (users, forum, billing). Thick slice.
- **Feature**: valuable to a customer, described by a story; often several operations (register and choose a premium plan).
- **Operation**: one command (changes state, e.g. `createUser`) or query (reads, e.g. `getProfileDetails`). Thin slice; usually one API call. Command/query separation (CQS) lives here: a read path and a write path.

"Use cases define features, which define modules, which define sub-modules."

## Rules
1. **Folders show features.** `src/modules/<capability>/<feature>/` holds that feature's operations (controller, use case, input/output). Shared domain objects of a module may sit in `src/modules/<capability>/domain/`.
2. **`modules/` is for the customer** (essential complexity). **`shared/` is for the developer** (accidental complexity: base classes when truly needed, API drivers, event bus, HTTP client, test utilities).
3. **Tests mirror features**: `tests/<capability>/<feature>/` with **one `.feature` file per feature** (stories, scenarios, examples) plus its acceptance spec. Fakes and test builders live next to the contract they implement or in one clearly named place, never in two folders for one concept.
4. **Folders are not layers.** Layers are theoretical concerns. The tree outside follows modules/features; *inside* a feature, objects follow the stereotypical architecture (controller → use case → domain → repository contract; see `layering-and-composition`).
5. **Siblings share a level of cohesion.** Ask: is `posts/` a peer of `users/`, or is `forum/` the module and `posting/` the feature? Decide by language and cohesion; it requires constant scrutiny.
6. **Every new abstraction gets two answers**: which module/feature (essential → `modules/`, accidental → `shared/`) and which layer.
7. **Name by intent.** Use case and feature names are the dominant responsibility (`register-user`, `purchase-tickets`), never `handle-submit` or `misc`.
8. **README is a table of contents**: what the app does (capabilities), quick start with expected output, configuration table (required vs optional), usage examples including an error case, how to add a feature, how to test features, where the tests are, how to run it. Rely on knowledge in the world (`src/`, `tests/` need no explanation); explain uncommon folders (`packages/`). A README is never optional; verify it by following the quick start on a clean setup.

## Target trees (backend and frontend): see [folder trees](./references/folder-trees.md)

Short form:
```
src/
  modules/            for the customer
    users/
      registration/   create-user (command), controller, input/output
      profile/        get-profile-details (query), edit-user (command)
    forum/
      posting/
  shared/             for the developer
tests/
  users/
    registration/registration.feature
    registration/registration.spec.*
```

## Procedure (adding a feature)
1. Find the capability from the feature file's language. Existing module? Use it. New language? Ask whether it's a new module (`domain-discovery`).
2. Create `src/modules/<capability>/<feature>/` and `tests/<capability>/<feature>/<feature>.feature` first.
3. Add operations as separate files named by intent; commands and queries separate.
4. Update the README's feature list if a capability was added.
5. Self-check: can someone else find this feature from the tree in one or two hops?

## Anti-patterns to refuse
- Package by infrastructure (`controllers/`, `services/`, `models/`, `routes/`, `utils/helpers`): features invisible, one change sprawls everywhere. "I hate package by infrastructure."
- Thinking in endpoints instead of features; starting from UI components.
- Two folders for one concept (`fake/` and `testing-utils/`): merge.
- A `utils/` or `helpers/` dumping ground.
- Testing operations in isolation as if they were the most valuable unit; the feature is.

## AI guardrails
- Agents follow the structure they find. In a package-by-infrastructure repo one feature change sprawls across many folders. Feature folders plus one `.feature` per feature give the agent one place to work and one oracle to check against.
- With `modules/<capability>/<feature>` and a README "how to add a feature", an agent reaches the right file in one or two hops, and mirrored feature tests tell it when it is done.

Sources: essentials-physical--vertical-slicing, architecture--structuring, frontend--structure-nfrs, cheatsheet--design-rules; fastapi-genai-skillset → release-gates/readme-contract
