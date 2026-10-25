# Production-Readiness Review

Load in `code-review` step 8 when a change touches backend, integration, configuration or deployment code. Runs after the course checklists; it does not replace them.

## Review checklist
Security wiring (`security-baseline`)
- [ ] Protected and sensitive routes have auth and rate-limit checks wired (placeholders allowed only if tracked as debt).
- [ ] No staging/production configuration lets requests through placeholder auth.
- [ ] Authorization is explicit at the boundary; no secrets, tokens or credentials logged.

Request path and long work (`operational-resilience`)
- [ ] No blocking IO or CPU-heavy work on the request path; heavy work is offloaded.
- [ ] Long-running endpoints use 202 + task id + status endpoint with a stable response shape.
- [ ] Async request paths use non-blocking clients only.

Reliability (`operational-resilience`)
- [ ] Every outgoing call has a timeout and maps failures to stable error codes.
- [ ] Retries are bounded, with backoff, and only for temporary failures.
- [ ] Fallbacks are explicit, marked in the response or logs, and counted in metrics.
- [ ] Background jobs capture and log failures with job identity.

Performance and stability
- [ ] Payload limits enforced, stricter on high-risk routes.
- [ ] Connection pool limits and exhaustion behavior reviewed.
- [ ] Known blocking hotspots identified and addressed or ticketed.

Operability (`observability-and-config`)
- [ ] Request id on every log line, response and outgoing call.
- [ ] New config is env-driven, documented in the README config table, and fails fast when missing.
- [ ] Readiness reflects any new critical dependency.

Contracts and tests
- [ ] Status codes and error envelope match the API and data contracts (`layering-and-composition`).
- [ ] Critical paths have failure-path tests (timeouts, auth failures, missing resources).
- [ ] Cache and startup/shutdown tests exist where the change added caching or lifecycle code (`test-strategy` edge cases and operational tests).

## Red flags (detectors)
| Area | Red flag |
|---|---|
| Request path | Blocking client call inside an async handler; CPU-heavy work in a handler |
| Request path | Outgoing call without a timeout |
| Request path | Long request held open instead of 202 + task id; accepted work with no status endpoint |
| Errors | Catch-all exception handler with no mapping to stable codes |
| Errors | Stack traces or internal exception names in responses |
| Errors | Mixed error formats across related endpoints |
| Runtime | No request id propagation |
| Runtime | No rate limit on sensitive routes (login, password reset, payments) |
| Runtime | No readiness check for critical dependencies |
| Runtime | Background job started with nobody observing its failure |

## Action rule (every red flag)
1. Classify severity: blocking (security, data loss, outage risk) or follow-up.
2. Add a remediation task naming the file and the fix.
3. Add a regression test or lint/architecture rule so it cannot come back.

## Decision
- **Approve**: every row passes.
- **Approve with follow-ups**: only follow-up severity hits, each with a tracked task.
- **Request changes**: any blocking hit.
