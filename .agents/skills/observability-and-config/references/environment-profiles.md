# Environment Profiles

Load when adding an environment, a per-environment setting, or preparing for staging/production. All differences are decided in the composition root from configuration, never with environment checks in services.

| Setting | Local | Development | Staging | Production |
|---|---|---|---|---|
| Log level | debug when debugging | debug allowed | info | info or warning |
| Telemetry | off by default | optional | production-like, with redaction | full: tracing, metrics, alerts |
| CORS | permissive allowed | explicit list | mirrors production | strict allowlist only |
| API docs / schema endpoints | on | on | on or access-controlled | off or access-controlled |
| Error detail in responses | full allowed | moderate | minimal | minimal: error code + request id |
| Auth | relaxed only for explicit local testing | real, test credentials | same as production | strongest; no placeholders |
| Credentials | local fakes or test accounts | test credentials and sinks | separate from production | production secrets from a secret store |
| Debug mode | allowed | allowed | off | off |

## Rules
- Staging exists to give confidence about production: same auth strictness, same CORS policy, same telemetry.
- Each profile is a configuration set, not a code branch.
- A production start with any local/dev setting (debug on, permissive CORS, placeholder auth) fails at startup.

## Configuration and secrets
- One typed settings object, built from environment variables at startup; inject the values it holds, not the settings object, into actors.
- `.env.example` lists every variable with required/optional and a safe example; `.env` is gitignored.
- Missing or malformed required values stop startup with a clear message naming the variable (never its value).
- Secrets come from the environment or a secret store; never from code, images or repository history.
