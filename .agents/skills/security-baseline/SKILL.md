---
name: security-baseline
description: 'Security baseline for any service. Use when adding protected routes, login or user data, configuring CORS, secrets or rate limits, or hardening before staging or production. Wires auth and rate-limit checks from day one, keeps auth errors non-revealing, never logs secrets, and verifies no placeholder auth reaches production.'
---

# Security Baseline

Standing rules:
- **Security is wired from day zero and hardened in phases.** Protected routes get an auth check and sensitive routes get a rate-limit check the moment they exist, even as placeholders.
- **Authorization is a rule, so it is explicit.** Who may do what is decided at the boundary (authentication in the incoming adapter, permission rules in the application layer), never implied.
- **Nothing secret leaves its box**: not in code, logs, responses, error messages or repository history.

## When to use
- Adding a route that reads or changes user data, money, permissions or configuration.
- Adding registration, login, password reset, tokens or sessions.
- Configuring CORS, secrets, rate limits or debug settings.
- Before the first staging or production deploy (feeds the release gates in `walking-skeleton-delivery`).

## Procedure
1. **Classify routes** in the feature's design notes: public, authenticated, privileged; mark sensitive ones (login, password reset, payments, admin).
2. **Wire placeholders from day zero**: every protected route gets an auth check, every sensitive route gets a rate-limit check. A placeholder may let everything through in local/dev only; mark it explicitly and track it as debt. Keep the route shape stable so hardening never reshapes routes.
3. **Harden progressively**: real authentication and permission checks on write and privileged routes first, then reads; real rate limits, stricter on login and token refresh.
4. **Verify**: no protected route still passes everything through; checks are active in staging and production profiles; unauthorized (401), forbidden (403) and throttled (429) responses use the standard error envelope (`layering-and-composition` API and data contracts).
5. **Run the checklist** in [security checklist](./references/security-checklist.md) before staging and before every production release.
6. **Test it**: level 3 for permission rules (wrong role, someone else's resource); level 6 for 401/403/429 mapping; acceptance sad paths for login failure.

## Rules
- Authentication failures are non-revealing: the same message for unknown user and wrong password; no hint which field was wrong.
- Never log raw tokens, passwords, credentials or secret keys.
- Passwords stored only with a strong, slow, salted hash.
- Tokens have a documented lifetime and refresh policy.
- Never ship placeholder auth to staging or production; never remove a check once wired.

## Exit gate
- Every protected route has an active auth check; every sensitive route has a rate limit.
- Checklist passes for the target environment.
- Auth failure, forbidden and throttled paths have tests.

## Anti-patterns to refuse
- "We'll add auth later" with no check wired, so adding it later reshapes every route.
- Permission checks scattered in controllers or missing on one endpoint of a group.
- Different error messages for "no such user" and "wrong password".
- Secrets in source, sample config, test fixtures or commit history.
- Debug mode, permissive CORS or detailed errors in production.

## AI guardrails
- Agents generate routes without auth unless told. State the route classification in the prompt and ask for the check on every protected route.
- Agents echo tokens and request bodies into logs while debugging; review every new log line.
- Do not let an agent paste real secrets into code or config to "make it work"; it must read them from the environment.

Sources: fastapi-genai-skillset → auth-security/SKILL, auth-security/bootstrap-auth-stubs, auth-security/security-checklist, auth-security/jwt-baseline (policy only), release-gates/pre-deploy-audit; course: architecture--code-placement
