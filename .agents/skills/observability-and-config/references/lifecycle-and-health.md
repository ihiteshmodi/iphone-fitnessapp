# Lifecycle and Health

Load when wiring startup or shutdown, adding a long-lived resource, or adding health checks.

## Startup and shutdown (in the composition root)
1. Load and validate configuration; stop on any missing required value.
2. Open long-lived resources once, in dependency order: connections and pools → clients → repositories and gateways → workers, schedulers and refresh loops → delivery (web server, consumers).
3. If a critical resource fails to start, stop startup with a clear error; non-critical ones start degraded and report it.
4. Log the start and end of each step with its duration.
5. On shutdown: stop accepting new work, drain or re-queue in-flight work, then close resources in **reverse** order.
6. When several sub-applications or modules each own resources, one host lifecycle enters them in a fixed order and exits them in reverse; keep the list of modules and the list of lifecycle entries in sync.

## Liveness vs readiness
| Check | Answers | Includes |
|---|---|---|
| Liveness | Is the process alive and not stuck? | Nothing external |
| Readiness | Can it serve traffic now? | Critical dependencies (database, required providers, sub-modules) |
- Readiness turns false when a critical dependency is down; the platform stops routing traffic instead of restarting the process.
- Readiness of a host reflects the readiness of its critical sub-modules.
- Health endpoints carry no secrets and no internal detail beyond status per dependency.

## Rotating credentials
For long-running services whose credentials expire:
1. Start a refresh loop at startup (fixed interval before expiry, or on an expiry event).
2. Rebind the clients that use the credentials.
3. Expose the last successful refresh time and loop health.
4. Cancel the loop cleanly at shutdown.
Only add this when credentials actually rotate during uptime.

## Tests
- Startup with a missing required variable fails and names it.
- Shutdown closes everything in reverse order with nothing left running.
- Readiness is false when a critical fake dependency fails to start.
