# Release Gates

Load before the first production deploy and before any release that changes schema, auth, configuration or infrastructure. The pipeline proves the code works; these gates prove the release is safe to run.

## Gate 1: Pre-deploy audit (before the release candidate is promoted)
Code
- [ ] Main flows work in a production-like environment (acceptance phase green).
- [ ] Status codes and error responses are consistent (`layering-and-composition` API and data contracts).
- [ ] No debug leftovers: print statements, debug flags, commented-out code, temporary endpoints.

Security (`security-baseline`)
- [ ] Passwords hashed with a strong, slow hash.
- [ ] API keys and secrets come from the environment; none in code or in repository history.
- [ ] CORS policy reviewed for the target environment.
- [ ] No placeholder auth or no-op rate limit active in staging/production.

Database
- [ ] Migrations committed and reviewed; they run forward cleanly on a copy of production-shaped data.
- [ ] No test data in the production schema.
- [ ] Connection pool size and exhaustion behavior known; backup and restore posture documented.

## Gate 2: Pre-flight go-live (in the target environment, before switching traffic)
- [ ] Health endpoint returns success; readiness reflects critical dependencies (`observability-and-config`).
- [ ] Every required environment variable is set; the app refused to start when one was missing.
- [ ] Database connected and migrated to the expected version.
- [ ] HTTPS enabled.
- [ ] No secrets embedded in code or images.
- [ ] README and runbook up to date (how to run, configure, roll back, who to call).

## Gate 3: Migration and rollback plan
- [ ] Each migration says whether it is backward compatible with the previous release.
- [ ] Rollback path written down: redeploy the previous artifact, and what happens to data written by the new release.
- [ ] Destructive schema changes split into expand → migrate → contract releases.

## Output format
```
Release: <version> → <environment>
| Gate | Result | Blocking issues |
|---|---|---|
| 1 Pre-deploy audit | PASS | |
| 2 Pre-flight | FAIL | DATABASE_URL missing in production config |
| 3 Migration/rollback | PASS | |
Remediation order: <blocking issues first, then re-run the failed gate and every gate after it>
Verdict: GO | NO-GO
```

## Rules
- Any failed checkbox in a gate is blocking unless the human owner accepts the risk in writing.
- Fix in order: security → data → configuration → documentation, then re-run the failed gate and every gate after it.
- Automate a check as soon as it fails twice (pipeline step, lint rule or test).
