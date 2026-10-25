---
name: code-review
description: 'Pre-commit and pull request review against the course checklists. Use after implementing a change and before committing, or when asked to review code, tests or an AI-generated diff. Checks comments, TDD hygiene, layer boundaries, premature interfaces, fakes without contract tests, frontend anti-patterns and production readiness.'
---

# Code Review (Pre-Commit Gate)

Standing rule: run this **after the tests are green and before every commit**, and on any diff an agent produced. Report pass/fail per row; send each failure back as an instruction quoting the row. Then hand off to `commit-discipline`.

## Order of checks
1. **Comments explain why, never what.** "Code should express what happens; comments express why you chose to do it." A comment that narrates the code means the code needs better names; fix the code, delete the comment. Keep comments for rationale the code cannot express (spec quirks, external constraints).
2. **TDD and test hygiene**: the filtered kata checklist (21 rows): [kata checklist](./references/kata-checklist.md).
3. **Backend structure and layer guards**: [backend anti-patterns](./references/backend-anti-patterns.md).
   - No `new Date()`, random, IO, framework or ORM imports in domain/application code.
   - No repository calls or rules in controllers; controllers parse → call one use case → map.
   - Environment checks only in the composition root; no inline `new` of infrastructure in use cases.
   - Side effects after a command go through events, not appended awaits.
   - Feature-first placement: the change lives in `modules/<capability>/<feature>`; tests mirror it.
4. **Premature abstraction (George Clooney test)**: every new interface/abstract class has a second actor or sits at a real seam (repo, clock, payment, mail, gateway). Otherwise inline it.
5. **Fakes without contract tests**: every new fake/in-memory implementation is covered by a contract spec looping over fake and real. Library mocks only for trivial stubs.
6. **Frontend (only if UI files changed)**: [frontend anti-patterns](./references/frontend-anti-patterns.md).
7. **Spec alignment**: the change satisfies the approved `.feature` scenarios; no behavior beyond them (no gold-plating); the acceptance test still passes.
8. **Production readiness (only if backend, integration, config or deploy code changed)**: [production-readiness review](./references/production-readiness-review.md). Each red flag gets a severity, a remediation task and a regression test or lint rule.

## Output format
```
Review: <scope>
| # | Check | Result | Note / instruction |
|---|---|---|---|
| 1 | Comments say why | PASS | |
| 2.12 | No else chains | FAIL | Replace if/else-if in pricing.ts:14-30 with early-return guards |
...
Verdict: READY TO COMMIT | CHANGES REQUESTED
```
Do not commit while any row fails, unless the user explicitly accepts the risk.

## Before / after: comments
```ts
// before: comments narrate the code
export function isPalindrome(text: string): boolean {
  // lowercase the string
  const lower = text.toLowerCase();
  // remove the spaces
  const noSpaces = lower.replace(/ /g, '');
  // reverse it and compare
  return noSpaces === noSpaces.split('').reverse().join('');
}

// after: names carry the what, one comment carries the why
export function isPalindrome(text: string): boolean {
  const normalized = ignoreCaseAndSpaces(text);
  return normalized === reverse(normalized);
}
// Spaces are ignored because the spec treats "Was It A Rat I Saw" as a palindrome.
const ignoreCaseAndSpaces = (text: string) => text.toLowerCase().replace(/ /g, '');
const reverse = (text: string) => [...text].reverse().join('');
```

## AI guardrails
- Agents commonly fail checklist rows 6, 8, 10 and 18: mixed refactors, multi-assert tests with "returns an object with…" names, and "what" comments. Also check that every new test was seen failing once and was written from a scenario, not from the implementation.
- Review with the checklist and the anti-pattern lists; else-if chains, what-comments, implementation-detail names and premature interfaces are common in generated code.
- Guard layer boundaries mechanically where possible (architecture tests).

Sources: testing--comments, katas--review-checklist, cheatsheet--anti-patterns, cheatsheet--ai-agents, frontend--anti-patterns, abstraction-rdd--roles-actors; fastapi-genai-skillset → release-gates/implementation-review-checklist, observability-operations/anti-pattern-detectors
