---
name: understand-codebase-by-features
description: 'Onboard onto an unfamiliar or legacy codebase by hunting features. Use when asked to understand, explain, map, or start changing someone else''s codebase, or before refactoring legacy code. Traces each feature from UI to database, infers the original mental model, and pins behavior with tests before changing it.'
---

# Understand a Codebase via Features

Standing rule: **"The work that you need to do is entirely on features."** Hunting features is the 80/20 of understanding a codebase. Never rewrite legacy code from scratch; pin it with tests first.

## When to use
- Joining or auditing an existing project; "explain this repo", "where would X go", "how does Y work".
- Before refactoring or adding a feature to code you did not write.

## Procedure
1. **Find the common features.** Ask the user, read tickets/issues, read the README and routes/screens, use the app. Write them as a list of user-visible capabilities (who does what), not endpoints.
2. **Trace each feature into code.** For each one, follow the path UI → incoming adapter (route/controller/component) → application logic → domain rules → persistence/external calls. Record the files touched and where each rule lives.
3. **Infer the original mental model.** Note how the authors thought: package by infrastructure or by feature? Where do rules live (controllers, services, models)? Where is time, IO, configuration handled? Map every pattern you see onto the 12 essentials (jargon map in `architecture-decisions`).
4. **Make the features explicit.** Add a layer of tests representing features. In a messy codebase, **stop the bleeding first**: wrap the main flows in E2E / characterization tests (tailor's pins: they record current input → output end to end) before any structural change.
5. **Then improve one slice at a time**: kick off the next feature with a vertical slice in the target structure (`feature-first-structure`, `layering-and-composition`), pulling the codebase toward it.

## Outputs
`docs/design/codebase-map.md`:
| Feature (who does what) | Entry point | Use case / service | Rules live in | Persistence / external | Tests covering it |
|---|---|---|---|---|---|
plus: inferred mental model, risks (untested features, rules in controllers, env checks), and the recommended first characterization tests.

## Anti-patterns to refuse
- Reading files alphabetically or by layer instead of by feature.
- Rewriting from scratch, or refactoring before characterization tests exist.
- "Pattern-first surgery" on untested code.

## AI guardrails
Asking an agent to "trace feature X from the UI to the DB" is a fast way to run step 2. A `modules/<capability>/<feature>` tree with a README lets agents reach the right file in one or two hops; in a package-by-infrastructure codebase, produce the map above first so later prompts can cite exact files.

Sources: architecture--large-codebases, essentials-physical--walking-skeleton, testing--no-time
