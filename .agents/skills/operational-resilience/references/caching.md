# Caching

Load before adding a cache. First ask whether the cache is needed: it is a second source of truth and a new set of failure modes. Put it behind the same role as the data it caches (a caching decorator around the repository or gateway), so use cases don't know it exists.

## Patterns
1. **One refresher per expired key.** When a key expires, one caller refreshes it; concurrent callers get the cached value (if safe) or wait for that one refresh. Prevents a stampede on the source.
2. **Stale on failure, marked.** If the refresh fails and an older value exists, serve it with a marker (response flag, log field, metric). Fail only when no acceptable value exists. Never present stale data as fresh.
3. **Invalidation cascade.** Write down which entries depend on which source; when a source changes, invalidate its dependents. Avoid wildcard invalidation on hot paths.
4. **Versioned keys.** Namespace keys with service and version (`orders:v2:summary:{id}`) so a format change never reads old-shaped values.
5. **TTL by volatility.** Short TTL for data that changes often; longer for expensive, stable data. Refreshes have their own timeout so a slow source can't hang a request.

## Metrics
Hit ratio, miss ratio, refresh successes and failures, stale values served, refresh latency. Log the fallback reason whenever a stale value is served.

## Tests (`test-strategy` operational tests)
- Stale value served and marked when refresh fails.
- One refresh under many concurrent callers.
- Dependents invalidated when the source changes.
- New key version ignores old-format values.
- Contract test: the caching decorator passes the same contract spec as the undecorated role.
