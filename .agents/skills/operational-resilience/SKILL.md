---
name: operational-resilience
description: 'Third-party and provider API integrations, retries, caching and long-running work. Use when code calls or integrates an external API, provider or service (HTTP client, SDK), adds timeouts, retries, fallbacks or a cache, runs background jobs, or a request takes seconds. Keeps the request path short, retries bounded, fallbacks visible.'
---

# Operational Resilience

Standing rules:
- **The request path is a traffic controller**: accept, validate, route. Heavy or slow work does not happen inside it.
- **Every outgoing call is a guess about someone else's system.** Put it behind a role (gateway contract), give it a timeout, and decide up front what happens when it fails.
- **Degraded is fine; silent is not.** Every retry, fallback and stale value is visible in logs and metrics.

## When to use
- Writing an infrastructure actor that calls an external API, payment provider, another service or a slow database query.
- Adding retries, timeouts, circuit-breaking, fallbacks or a cache.
- A request may take more than an interactive response time, or work must continue after the response.
- Starting a background job, worker or scheduled task.

Not for: side effects that belong to another feature after a command (use `event-driven-decoupling`); logging and config wiring (`observability-and-config`).

## Procedure
1. **Put the call behind a role.** The use case depends on `PaymentGateway`, not on an HTTP client (`layering-and-composition`). Timeouts, retries and error mapping live in the infrastructure actor, never in the use case.
2. **Apply the client baseline** to that actor: timeout on every call, status checked, network errors caught explicitly, provider errors mapped to your stable error codes, client created once at startup and closed at shutdown. See [outgoing calls](./references/outgoing-calls.md).
3. **Retry only temporary failures** (timeouts, provider temporarily down, rate-limited with retry-after), a fixed number of times with growing delays plus jitter, through the injected `Clock`. Never retry bad input, auth failures or deterministic validation errors. Retry writes only when the call is idempotent (send an idempotency key).
4. **Decide the fallback explicitly** per call: degraded response allowed by product policy (cached value, default, partial result) or a stable error code. Mark degraded responses and count them.
5. **Cache deliberately**, if at all: one refresher per expired key, stale-on-failure with a marker, invalidation of dependents, versioned keys, TTL per volatility, metrics. See [caching](./references/caching.md).
6. **Move long work off the request path**: return 202 with a task id and a status endpoint; the task is a small state machine (queued → running → completed | failed). See [long-running work](./references/long-running-work.md).
7. **Never let background work fail silently**: every job and fire-and-forget task captures its failure and logs it with its identity.
8. **Ask the load-failure questions** before shipping: what blocks the request path first? When do connection pools saturate? What is the timeout path for each dependency? What happens when the work queue lags?
9. **Test it** at level 3 with a controllable fake (provider down, slow, rate-limited) and at level 4 with a contract test proving the fake and the real actor map failures the same way. Retry waits go through `FakeClock`, so tests never sleep.

## Exit gate
- Every outgoing call has a timeout, a failure mapping and a decided fallback.
- Retries are bounded, only for temporary failures, and observable.
- No request handler does blocking or CPU-heavy work; long work returns 202 + task id.
- Every background job reports its failures.

## Anti-patterns to refuse
- HTTP client calls inside use cases or domain code; no timeout ("it usually answers").
- Unbounded retries, retrying 4xx, retry loops with real sleeps in tests.
- Fallbacks that return default data as if it were real; stale cache served as fresh.
- Holding a connection open for a minute to fake real-time; polling with no status endpoint.
- Fire-and-forget tasks with nobody observing the result.
- Blocking clients inside async request paths.

## AI guardrails
- Generated integration code usually omits timeouts and wraps everything in a catch-all retry. Ask for: a gateway role, a timeout per call, a retry policy naming which failures are temporary, and a fallback decision, with level-3 tests for each failure.
- Agents fake success in fallbacks. Require a degraded marker and a metric for every fallback path.

Sources: fastapi-genai-skillset → integration-reliability/api-client-policy, integration-reliability/retry-fallback-policy, integration-reliability/resilient-caching-patterns, integration-reliability/resilient-background-task-manager, integration-reliability/fastapi-concurrency-long-task-thesis, genai-application-patterns/external-tool-agent-runtime-safety (background task discipline only); course: essentials-physical--horizontal-decoupling, testing--contract-tests
