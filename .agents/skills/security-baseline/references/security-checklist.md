# Security Checklist

Load before staging and before each production release. Every unchecked box is blocking for production.

## Secrets
- [ ] Secrets and API keys come from the environment or a secret store only.
- [ ] No secrets in code, sample config, test fixtures, container images or repository history (scan history, rotate anything ever committed).
- [ ] Signing secrets are strong and different per environment.

## Authentication
- [ ] Passwords stored with a strong, slow, salted hash.
- [ ] Token lifetimes and refresh policy documented.
- [ ] Failure messages are identical for unknown user and wrong password.
- [ ] No placeholder auth active in staging or production.

## Authorization
- [ ] Every protected route has an explicit check; privileged actions check roles or ownership.
- [ ] Access to someone else's resource returns 403 (or 404 when existence itself is sensitive).

## Rate limiting
- [ ] Sensitive routes are rate-limited; login, password reset and token refresh have stricter limits.
- [ ] Throttled responses use the standard error envelope.

## Transport and browser
- [ ] HTTPS everywhere outside local.
- [ ] CORS allowlist set per environment; strict in production.

## Responses and logs
- [ ] Sensitive fields (password hashes, tokens, internal ids where relevant) excluded from responses.
- [ ] Production errors return an error code and request id only, no stack traces.
- [ ] Tokens, passwords and secrets never logged; redaction happens in the logger.
- [ ] Debug mode off in production.
