# Outgoing Calls

Load when writing or reviewing an infrastructure actor that calls another system.

## Client baseline (every outgoing call)
| Rule | Why |
|---|---|
| Set a connect and a total timeout on every call | A missing timeout turns one slow provider into a full outage |
| Check the response status; don't assume success | Providers return errors with a 200-shaped body or a 5xx with HTML |
| Catch network errors explicitly (timeout, connection refused, DNS) | Each one maps to a different error code and retry decision |
| Map provider errors to your own stable error codes | Use cases and clients never see provider-specific errors |
| Create the client once at startup; close it at shutdown | Reuses connections; no leaked sockets (`observability-and-config` lifecycle) |
| Use non-blocking clients on non-blocking request paths | One blocking call stalls every concurrent request |
| Forward the request id on outgoing calls | Correlates your logs with the provider's |

## Retry decision table
| Failure | Retry? |
|---|---|
| Timeout, connection reset, DNS hiccup | Yes, bounded |
| 502 / 503 / 504, provider temporarily unavailable | Yes, bounded |
| 429 rate-limited | Yes, after the provider's retry-after |
| 400 / 422 validation, 404 | No |
| 401 / 403 auth | No (refresh credentials first if that is the cause, then one retry) |
| 500 on a non-idempotent write without an idempotency key | No |

Policy shape: max attempts (usually 3), exponential backoff with jitter, a total time budget smaller than the caller's timeout. Waits go through the injected `Clock`.

## Fallback decision (write it down per call)
| Option | Choose when | Must also |
|---|---|---|
| Degraded response (cached value, default, partial) | Product owner agrees stale or partial is acceptable | Mark it in the response or log; increment a fallback metric |
| Stable error code | Correctness matters more than availability (payments, permissions) | Return the documented error envelope; never leak the provider error |
| Queue for later | The user doesn't need the result now | Return 202 + task id (`long-running-work`) |

## Observability per call
Log: dependency name, operation, duration, outcome, attempt number, request id. Metrics: calls, errors, latency, retries, fallbacks per dependency. Never log credentials or full payloads with personal data.

## Tests
- Level 3: controllable fake set to timeout, 503, 429, 400; assert the use-case outcome and the error code.
- Level 4: contract test looping over fake and real actor (sandbox) proving both map failures identically.
- Retry tests advance `FakeClock` instead of sleeping.
