---
name: commit-discipline
description: 'Commit discipline. Use whenever about to create a git commit: commit only on green, prefix behavior and structure changes with feat, fix or refactor, write a plain message for everything else, keep behavior changes and refactors in separate commits, and never push or rewrite shared history without asking the user.'
---

# Commit Discipline

Standing rules:
- **Commit only on green.** Green is standing on a platform; red is not a save point.
- **One kind of change per commit.** Behavior changes (`feat`, `fix`) and structure changes (`refactor`) never share a commit. The type says which.
- **Local commits only.** Never `git push`, force-push, amend or rebase published commits, or change remotes without the user's explicit approval.

## When to use
After `code-review` passes, at the end of each green step and each refactor step in `fa2str-workflow`.

## Commit messages
Three typed prefixes, plain messages for everything else.

| Prefix | Use when | Example |
|---|---|---|
| `feat` | New behavior a user or caller can observe | `feat(tickets): place an order for several tickets` |
| `fix` | Wrong behavior corrected (start with a failing test that reproduces the bug) | `fix(users): treat emails case-insensitively` |
| `refactor` | Structure changed, behavior identical, tests untouched and green | `refactor(tickets): extract group discount into pricing` |
| *(none)* | Anything else: tests only, docs, `.feature` wording, dependencies, CI, config, formatting | `Add OrdersRepository contract spec`, `Bump vitest to 3.2`, `Add acceptance phase to pipeline` |

Rules:
- Scope = the module/capability (`users`, `tickets`, `billing`), matching `src/modules/<capability>`.
- Plain messages are imperative and specific ("Add …", "Update …", "Remove …"), never `wip` or `update`.
- If the repo already enforces a convention (e.g. full Conventional Commits via commitlint), follow the repo; keep the "behavior XOR structure" separation anyway.
- The course's two reasons to commit on green map directly: new functionality → `feat`/`fix`; design change → `refactor`.

## Procedure
1. Run the relevant tests; all green. In agent mode an in-progress feature's outer acceptance test may still be red; say so in the body.
2. For each new test, confirm it was seen failing once (red for the right reason) or flip the switch: break the code briefly, watch it fail, restore it.
3. Check `git status` / `git diff --staged`; stage only files for this step (no debug files, secrets, generated artifacts).
4. Write `feat|fix|refactor(scope): <behavior in the user's or caller's language>`, or a plain imperative message for anything else. Describe behavior, not internals ("return result true and error null" is not a message).
5. Commits tell the story: a reviewer should see the feature grow scenario by scenario, then the refactors, not one big jump.
6. When the user asks to push or open a PR, confirm the branch and remote first.

## Before / after
```
# before
a91f2c3 wip
7c0d1e8 fix tests          # were they red before this?
5b33a90 stuff + cleanup    # behavior change or structure change?
1e0f7aa trying modulo      # committed on red

# after
3f2a9c1 feat(tickets): place an order for several tickets
8b71d04 feat(tickets): reject orders above ten tickets
c09e5aa refactor(tickets): extract quantity rule into Order
d1a77b2 Add OrdersRepository contract spec
```

## Anti-patterns to refuse
- Committing on red; big-bang commits; mixing a refactor with a behavior change.
- `wip`, `fix stuff`, `update` messages.
- Skipping hooks or CI checks (`--no-verify`) to get a commit through.
- Pushing without approval.

## AI guardrails
Ask for small commits typed by intent (`feat` / `fix` / `refactor`, plain for the rest) so you review a story of commits instead of a big-bang diff. In agent mode, commit at each green scenario or refactor so every AI change stays small enough to review or revert.

Sources: testing--commits, katas--review-checklist, cheatsheet--testing-rules, cheatsheet--ai-agents
