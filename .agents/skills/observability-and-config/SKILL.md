---
name: observability-and-config
description: 'Logs, metrics, request ids, config, secrets and startup/shutdown. Use when adding logging, monitoring, alerts or health checks, reading environment variables or secrets, defining per-environment settings, or wiring startup and shutdown of long-lived resources. Fail fast on missing config; correlate every log by request id.'
---

# Observability and Configuration

Standing rules:
- **Production is the last feedback loop.** Logs, metrics and traces are how you learn whether a deployed guess worked; without them, the execution guess point is blind.
- **Configuration is read once, in the composition root**, from the environment. Missing required config stops startup.
- **Secrets never appear in code, logs, responses or repository history.**

## When to use
- Adding logging, metrics, tracing, alerts, health or readiness checks.
- Adding a new environment variable, secret or per-environment behavior.
- Wiring startup or shutdown of connections, clients, workers or refresh loops.
- Preparing a service for staging or production.

## Procedure
1. **Request id first.** Accept a trusted incoming id or generate one; store it in request-scoped context that is safe under concurrency (not thread-local storage in async runtimes); add it to every log line, the response header, error envelopes and outgoing calls. Keep one format across services; regenerate malformed ids.
2. **Structured logs** (one event per line, key-value or JSON): request id, route, status, duration; plus security events (login failures, permission denials) and business events (order placed). Never log secrets, tokens, passwords or full personal data.
3. **Metrics**: request rate, error rate, latency percentiles (p50, p95, p99) per route; resource and connection-pool usage; per-dependency calls, errors and fallbacks (`operational-resilience`).
4. **Traces** for critical paths that cross processes or dependencies.
5. **Alerts on symptoms users feel first** (see [monitoring baseline](./references/monitoring-baseline.md)), then investigate causes.
6. **Configuration**: one typed settings object built from environment variables in the composition root; `.env.example` documents every variable (required vs optional) and `.env` is gitignored; validate at startup and refuse to start when a required value is missing or malformed. Mirror the table in the README (`feature-first-structure`).
7. **Environment profiles**: decide per environment the log level, telemetry, CORS, API docs exposure, error detail and auth strictness. See [environment profiles](./references/environment-profiles.md). Staging mirrors production.
8. **Startup and shutdown order** (see [lifecycle and health](./references/lifecycle-and-health.md)): open resources once in dependency order, close in reverse, fail fast on critical init failure; expose liveness and readiness separately; refresh rotating credentials in a managed loop.

## Exit gate
- One request can be followed through every log line and outgoing call by its id.
- Error rate, latency and health have alerts.
- The app refuses to start with missing required config; no environment checks outside the composition root.
- Readiness turns false when a critical dependency is down.
- No secret in source, logs or responses.

## Anti-patterns to refuse
- `if (env === 'production')` scattered through services; reading env vars inside use cases.
- Defaults that silently replace missing production config (an empty secret, a local DB URL).
- Unstructured string logs; logging whole request bodies or headers with tokens.
- Thread-local correlation in an async runtime (ids leak between requests).
- One health endpoint that always returns OK; readiness that ignores the database.
- Alerts on every cause (CPU, one 500) instead of user-facing symptoms.

## AI guardrails
- Agents add `console.log`-style debugging and read env vars wherever convenient. Ask for a single settings object built in the composition root and a structured logger injected as a role.
- Agents tend to log full payloads when debugging. Require a redaction rule and check the review for secrets in logs.

Sources: fastapi-genai-skillset → observability-operations/observability-baseline, observability-operations/request-id-logging-correlation, observability-operations/environment-profiles, observability-operations/multi-app-composition-mounted-subapps, observability-operations/credential-refresh-lifecycle, foundation-contracts/foundation-checklist, foundation-contracts/lifespan-fan-in-mounted-subapps; course: essentials-physical--composition, workflow--guess-points
