# NFRs → Tools and Levers

Load when choosing a tool, platform, rendering strategy or storage.

Procedure recap: list functional + non-functional requirements → RDD (responsibilities → roles → collaborations) → pick tools that play those roles → validate with concrete examples → choose.

## Backend responsibilities / NFRs
| Responsibility / NFR | Candidate approach |
|---|---|
| Very fast data retrieval | Key-value storage (alternatives: document, relational) |
| Caching, pub/sub, key-value | Redis (one component can play many roles) |
| Queuing and scheduling | Redis + a job queue library (e.g. BullMQ) |
| Generic capabilities (email, auth, payments, analytics) | Buy / external service; wrap the minimum integration code in an adapter |
| Modules talking to each other | In-process event bus first; a broker only when an NFR demands it |

## Frontend / client-server NFRs
| NFR | Question to ask | Lever |
|---|---|---|
| Speed / bundle size | How fast is the first load? | Do not ship a huge bundle; users drop off after ~3 seconds |
| SEO | Will user-generated content drive traffic? (ask the customer) | Pre-render / server-render the first request, then client-side |
| Security | What must unauthenticated users never receive? | Server-side rendering so protected pages are never sent |
| Real-time / availability | Does the slice need live updates worldwide? | WebSockets or similar; decide where each responsibility lives (e.g. multiplayer "start / join game") |

The main driver of frontend architecture choices is moving responsibilities between client and server.

## Review an AI-suggested stack
For each component the agent proposes, fill in:
| Component | Role / responsibilities it plays | Layer | NFR that justifies it | Build / buy | Reversible? |
|---|---|---|---|---|---|

Reject rows with no responsibility or no NFR. Flag irreversible rows for the human.
