# Monitoring Baseline

Load when setting up monitoring for a new service or reviewing what an existing one emits.

## Logs (structured)
| Field | Always |
|---|---|
| request id | yes |
| route / operation | yes |
| status / outcome | yes |
| duration | yes |
| user or tenant id (not personal data) | when authenticated |
| error code | on failure |

Also capture security events (failed logins, permission denials, rate-limit hits) and key business events (order placed, payment failed).

## Metrics
- Requests: rate, error rate, latency percentiles per route.
- Resources: CPU, memory, connection-pool usage and wait time, queue depth.
- Dependencies: calls, errors, latency, retries, fallbacks, cache hit ratio.
- Business: the feature's KPI (closes the execution guess point loop).

## Traces
Distributed tracing on critical paths that cross processes or dependencies; propagate the trace context and the request id together.

## Alerts (symptoms first)
| Severity | Condition |
|---|---|
| Immediate | Elevated error rate; sustained high p99 latency; failing health/readiness checks |
| Warning | Resource pressure trends (pool, memory, queue depth); moderate error-rate drift |

Each alert links to a runbook entry: what it means, how to check, how to mitigate.

## Redaction
Never log: passwords, tokens, API keys, session ids, full card or identity numbers, full request bodies of sensitive routes. Redact at the logger, not at each call site.
