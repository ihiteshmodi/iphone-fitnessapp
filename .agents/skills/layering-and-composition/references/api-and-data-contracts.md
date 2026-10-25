# API and Data Contracts

Load when designing or reviewing an incoming adapter (HTTP routes, API shape) or the persistence rules behind it. The use case returns expected failures as values; the incoming adapter maps each one to a status code and error code. Decide these once per API and keep them identical across endpoints.

## Status codes: the most specific code per outcome
| Code | Use for |
|---|---|
| 200 | Successful read or standard success with a body |
| 201 | Created; return the created resource |
| 202 | Accepted long-running work; return a task id (`operational-resilience`) |
| 204 | Success with no body; default for delete |
| 400 | Validation or request-shape failure |
| 401 | Not authenticated |
| 403 | Authenticated but not allowed |
| 404 | Resource missing (or soft-deleted, for non-admin callers) |
| 409 | Conflict: stale version, duplicate, forbidden state transition |
| 500 | Unexpected failure; never an expected domain outcome |

## One error envelope
- Pick one error response shape for the whole API and document it, e.g. `{ "error": { "code": "EmailAlreadyTaken", "message": "…", "requestId": "…" } }`.
- `code` is stable and machine-readable; clients branch on it, never on the message.
- Domain errors (`UserAlreadyExists`) map to codes in the incoming adapter, not in the domain.
- Never return stack traces, SQL or internal exception names. Log them with the request id instead.
- Mixed error formats across related endpoints are a review failure.

## PUT vs PATCH
- PUT replaces the whole resource; missing fields mean "cleared".
- PATCH changes only the fields sent; absent fields are untouched. Distinguish "absent" from "explicitly null".
- Either way the change goes through the entity's intention-revealing methods, so invariants still hold.

## Concurrent edits: optimistic locking
- Store a version number on contested records; the client sends the version it read.
- Update only when the stored version matches, then increment it.
- On mismatch return 409 with a stable code (`StaleVersion`); never silently overwrite.

## Bulk operations
- Define a maximum batch size; reject larger requests with 400.
- Write in transaction chunks, not one giant transaction.
- Declare per endpoint: all-or-nothing, or partial success.
- With partial success, report a result per item (`index`, `status`, `code`).

## Soft delete and audit
- Model "Deleted" as a state in the entity's state machine (`state-machines-invariants`): a `delete()` transition, a `Deleted` event, and forbidden transitions out of Deleted except `restore()`.
- Business records are soft-deleted by default; hard delete only when explicitly required (for example legal erasure).
- Default reads and lists exclude deleted records; admin or audit views include them through an explicit filter.
- Audit fields: created at/by, updated at/by, deleted at/by, optional reason. Time comes from the injected `Clock`; the actor comes from the authenticated request. Domain events are the audit trail.
- Restore is its own operation with stricter permissions than update, and records a restore event.
- Never mix hard and soft delete in one endpoint; document what happens to children of a deleted parent.

## Versioning
- Put the version in the path (`/api/v1/...`), not only in documentation.
- A breaking change means a new version; keep the old one until its clients have moved.

## Validation and limits
- Reject malformed input at the edge, before any expensive work: request-shape checks in the incoming adapter, business rules in value objects.
- Enforce payload size limits (body size, list lengths, string lengths) on every route, stricter on high-risk ones.

## Tests
- Level 6 (incoming adapter): each use-case outcome maps to the documented status and error code.
- Level 3: version conflicts, partial bulk failures, restore permissions.
- Level 2: Deleted state transitions.
