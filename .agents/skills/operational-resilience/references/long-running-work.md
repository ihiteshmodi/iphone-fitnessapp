# Long-Running Work

Load when a request may take longer than an interactive response, or work must continue after responding.

## Contract
1. Validate the request first; reject bad input before queueing anything.
2. Create a task, enqueue it, and return **202 Accepted** with a task id and the status URL.
3. Expose a status endpoint with a stable response shape: `status`, timestamps, result or error code when finished.
4. Don't fake real-time by holding the connection open. If the client needs pushes later, add them on top of the status endpoint, not instead of it.

## The task is a state machine (`state-machines-invariants`)
```
queued → running → completed
               └──→ failed
```
- Forbidden: completed → running, failed → completed (retry creates a new attempt or a new task).
- Each transition records an event; failures store a stable error code, not a stack trace.
- Time comes from the injected `Clock`.

## Queue and worker rules
- **Bounded queue**: decide the maximum; when full, reject with a stable error (or 429/503) instead of growing memory.
- **Idempotency key**: the client sends one; a duplicate submission returns the existing task instead of creating a second.
- **Workers start and stop with the app** (composition root); shutdown drains or re-queues in-flight work.
- **Durable state** (database or queue service) in production; in-memory only behind the same role for tests.
- **Retention**: delete or archive finished tasks after a documented period.
- **Fairness**: with many tenants, limit per tenant so one can't starve the rest.

## Background failures are never silent
Every job, scheduled task and fire-and-forget operation captures its failure, logs it with the task id and request id, moves the task to `failed`, and increments a failure metric.

## Relation to events
A command whose side effects can happen later publishes an event (`event-driven-decoupling`); a handler or worker does the slow part. Use this file's contract when the *caller* needs to track the outcome.

## Tests
- Level 2: task state machine transitions and forbidden transitions.
- Level 3: submit returns 202 + id; duplicate idempotency key returns the same task; full queue returns the documented error; worker failure moves the task to `failed`.
- Level 6: status endpoint shape.
