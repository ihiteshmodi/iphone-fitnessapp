---
name: walking-skeleton-delivery
description: 'Walking skeleton, deployment pipeline and release gates. Use at project start or before the first feature on a new stack to deploy the thinnest slice through every component with an E2E test, to set up the commit phase, acceptance phase and gated deploy, and to run go-live checks before a release.'
---

# Walking Skeleton and Deployment Pipeline

Standing rules:
- **Deploy first.** "We don't actually know how long it's going to take us to get something deployed." Build the smallest valuable slice through every main component (UI → server → DB), deploy it, and verify it with an automated E2E test in the most production-like environment possible.
- **One path to production.** The pipeline is a constraint that makes it "very hard to ship negative value to users."

## When to use
- New project, new stack, or new deployable unit; before any real feature work.
- An existing messy project: kick off the next feature with a skeleton-style slice to pull the codebase toward structure. For existing behavior, pin it with characterization (E2E) tests first; don't rewrite.
- No CI, or quality relies on local hooks / manual walkthroughs.

## Walking skeleton procedure
1. Confirm the theoretical guesses (problem, solution) and the broad-stroke architecture are approved.
2. Pick the thinnest valuable story (e.g. "register a user and see it saved").
3. Implement it end to end across every main component, even if crude: UI (or API client) → incoming adapter → use case → repository → real DB.
4. Make the environment reproducible: containers for DB/services, one script to run, one script to test. Decide repo shape (monolith / monorepo), source control, CI, scripts, folder structure, README now; it never gets easier than at the start.
5. Write the E2E acceptance test for that story through a protocol driver (see `test-strategy`, 4-layer acceptance tests). Result verification only.
6. Deploy it through the pipeline below. Expect snag after snag; that is the point (versions, containers, CORS, env vars, ports surface now, not at the end).
7. Then: clean scripts across environments, working composition root, confirmed test strategy, tests in the pipeline. Feature work starts after.

## Pipeline (minimal first, then grow)
1. **Commit phase** (on every push, fast): install, lint, typecheck/build, high-value unit + use-case tests (no DB, no web server). Should give ~80–90% confidence; only possible with a decoupled core. Package a release candidate.
2. **Acceptance phase**: deploy the release candidate to a production-like environment (staging or containers in CI); run the E2E acceptance tests; infrastructure/contract tests before or after.
3. **Deploy**: manual approval or automated, from the same artifact.
Optional later phases: security, performance, extra infrastructure tests.

Rules:
- Fast checks may run in local pre-commit hooks as extra feedback; **hooks are never the gate** (anyone, including agents, can skip them). Slow tests run in CI. E2E in a pre-commit hook is so painful everyone turns it off.
- Know how you'll deploy before building (theoretical guess); prove it concretely in the skeleton.
- Manual walkthroughs are fine at the very start but slow everything as features grow.

Template workflow: [pipeline example](./references/pipeline-example.md).

## Outputs
Running deployed slice, `tests/<capability>/<feature>/` E2E spec, container/compose files, CI workflow, README "how to run / test / deploy".

## Exit gate
- The E2E test passes against the deployed (or production-like) environment from CI.
- A failing unit or acceptance test blocks deploy.
- Someone else can clone, run and test with documented commands: the README quick start is verified on a clean setup and produces the expected output it states.

## Before going live
Run the [release gates](./references/release-gates.md) (pre-deploy audit, pre-flight, migration and rollback plan). Report pass/fail per gate; any blocking issue stops the release.

## Anti-patterns to refuse
- Weeks of unconnected components, deploy at the end ("all these weird CORS errors").
- Assuming you can predict physical-world snags (versions, tooling, containers).
- Frontend-only or backend-only progress with no end-to-end slice.
- Husky / local hooks as the only quality gate; manual QA as the gate.
- All tests as E2E (slow, need the whole app); or only component unit tests with no feature-level tests.

## AI guardrails
- Agents make "weeks of unconnected components" seductively fast. Deploy the skeleton first so every generated piece is exercised by an E2E test against real, production-like infrastructure.
- Agents, like people, skip local hooks; the CI pipeline is the constraint that can't be bypassed. Humans own the pipeline design and the test boundaries it enforces.
- A deployed skeleton gives an agent a working, tested frame to extend one slice at a time.

Sources: essentials-physical--walking-skeleton, essentials-physical--deployment-delivery, workflow--to-physical, workflow--mvp; fastapi-genai-skillset → release-gates/SKILL, release-gates/pre-deploy-audit, release-gates/pre-flight-checklist, release-gates/readme-contract
