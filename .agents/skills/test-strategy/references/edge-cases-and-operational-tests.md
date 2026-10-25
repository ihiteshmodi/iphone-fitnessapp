# Edge Cases and Operational Tests

Load when listing failure scenarios for a feature, or when a change adds outgoing calls, caching, background work or startup/shutdown code.

## Edge-case classes
Turn each relevant class into a `.feature` sad-path scenario or a level-1/2/3 example row. Prioritise business-critical and security-critical flows before low-risk utilities.

| Class | Examples | Usual level |
|---|---|---|
| Empty / null | empty string, missing field, empty list | 1–2 (value objects) |
| Boundaries | min/max length, zero, negative, max batch size, exact limit | 1–2, `it.each` rows |
| Wrong types | number as string, malformed date, unknown enum | 6 (incoming adapter) |
| Unicode / special characters | emoji, accents, RTL text, quotes, very long strings | 1–2 |
| Missing resources | unknown id, deleted record, missing parent | 3 (in-memory repo seeded empty) |
| Dependency failures | timeout, provider down, rate-limited by provider | 3 (controllable fake) |
| Auth and permissions | unauthenticated, wrong role, someone else's resource | 3 and 6 |
| Concurrency | stale version (409), duplicate submission (idempotency key) | 3 |

## Operational tests (when the code exists)
Caching
- Old value is served, and marked as old, when refresh fails.
- Only one refresh runs when many callers hit an expired key at once.
- Dependent entries are cleared when their source changes.
- Versioned keys: a new key version never reads an old-format value.

Startup and shutdown
- Startup builds every required client, pool and worker; missing required config stops startup.
- Shutdown closes them in reverse order with nothing left running.
- Readiness reports not-ready when a critical dependency fails to start.

Outgoing calls
- Timeouts surface as the documented error code.
- Retries stop at the limit; non-temporary failures are not retried.
- Fallback responses carry their marker and increment the fallback metric (spy on the metrics role).

At least one cache test and one shutdown test run in CI wherever caching or lifecycle code exists.

## Test stability
- Tests never really wait between retries: backoff goes through the injected `Clock` or a no-wait policy in tests (`test-doubles-and-contracts`).
- Telemetry (tracing, metrics exporters) is initialised once per test run and shut down at the end, so no background worker outlives the suite.
- Keep these overrides in test wiring only; never weaken the production retry or timeout policy to speed up tests.
