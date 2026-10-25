# Folder Trees and README Template

Load when creating or restructuring a project.

## Before: package by infrastructure (refuse)
```
src/
  controllers/  usersController  postsController
  services/     userService  postService      ← create post? vote? comment? all here
  repositories/
  models/
  utils/helpers ← base classes, HTTP client, date maths…
tests/
  fake/          ← two folders for one concept
  testing-utils/
  users.test     ← which features are covered?
```

## After: backend, feature-first
```
README.md
src/
  modules/                          for the customer (essential complexity)
    users/                          capability / module
      domain/                       User, Email (shared inside the module)
      registration/                 feature
        create-user.(use case)      command
        create-user.(controller)
      profile/                      feature
        get-profile-details         query
        edit-user                   command
    forum/
      posting/
  shared/                           for the developer (accidental complexity)
    core/                           base classes only when needed 3+ times
    infra/                          db connection, event bus, http server
tests/
  users/
    registration/
      registration.feature          stories + scenarios + examples
      registration.acceptance.spec  outer loop (level 5)
      create-user.spec              inner loop (level 3)
  forum/posting/…
```

## After: frontend, feature-first (organise by features, not pages)
```
README.md
src/
  modules/
    todos/                          feature / module
      create-todo/                  use case (vertical slice)
        todosController
      todosPresenter                read side for the feature
      todosRepository
      todosGateway                  contract to the backend
      TodosPage                     component: last and thinnest
    account/
      registration/…
  shared/
    persistence/observable          global state = observer
    http/apiClient                  REST driver
    routing/routingService          wraps the router hook
tests/
  todos/create-todo/create-todo.feature
```
Pages exist one level below features. Build outside-in from the customer boundary; never start by building a reusable component library.

## README template
```markdown
# <App name>
<One line: who it helps and what they can do.>

## Capabilities
- Users: registration, profile
- Forum: posting, voting

## Quick start
1. <install command>
2. <run command>
3. <one request or click> → expected output: <exact response or screen>

## Configuration
| Variable | Required | Default | Purpose |
|---|---|---|---|
| DATABASE_URL | yes | — | Main database |
| LOG_LEVEL | no | info | Log verbosity |
Copy `.env.example` to `.env` (gitignored). The app refuses to start when a required variable is missing.

## Usage examples
- Register a user: <request> → <response>
- Email already taken: <request> → <error response with its stable error code>

## How to run
<one command>

## How to test
- All fast tests: <command>
- Acceptance (E2E): <command>
- Tests live in `tests/<capability>/<feature>/`; each feature has a `.feature` spec.

## How to add a feature
1. Write/approve `tests/<capability>/<feature>/<feature>.feature`.
2. Create `src/modules/<capability>/<feature>/`.
3. Outer-loop acceptance test first, then use-case tests (see AGENTS.md workflow).

## Structure
- `src/modules/` customer-facing capabilities; `src/shared/` developer plumbing.
```

README contract:
- A README is never optional, including for generated projects.
- Quick start states the expected output, so a reader knows it worked.
- Configuration table separates required from optional variables; no secret values in it.
- Usage examples include at least one error case with its response.
- Verify by following the quick start on a clean setup (fresh clone, fresh container); fix the README, not the reader.

## Navigation as a table of contents
README → `tests/` by capability → `.feature` per feature → scenarios/examples → matching `src/modules/<capability>/<feature>/`. Goal: from opening the repo to knowing how to do a use case in one or two seconds.
