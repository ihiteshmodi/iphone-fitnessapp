# Framing and Essence Examples

Load when the request is short, generic or context-free.

## Mental models decide the code
"A mental model is only as good as how closely it maps to reality." API-first and DB-first models map to tables and endpoints; the value-based model maps to people moving from pain to benefit. The model you hold is what shows up in the code.

## Context-free vs context-full framing
The same words describe different problems. Always ask which one.
- "Build tic-tac-toe": a pure game-rules problem.
- "Build web-based multiplayer tic-tac-toe": adds concurrency, client and server domains, rooms, matchmaking, network failures.
- "Tic-tac-toe on a fast-food order terminal": the problem changes again (idle time, kiosk input, short sessions) and exposes different subdomains.

Framing decides the subdomains, the architecture and the tests. Get it before anything else.

## Essence → role/goal → purpose → form
Features are born from: actor → role → goal → feature → only the essential properties. Write no code unless you are clear on who plays what role and why they need it; that is how you write the minimal amount of code.

The mug example: the same object has different essential properties per role.
- Programmer (goal: drink coffee) → the hole that holds liquid is essential.
- Landscaper (goal: scoop dirt) → the hole that holds matter is essential.
- Business owner (goal: advertise) → a printable surface is essential.

Software essence: behavior is guarded state transitions; data is initial state plus events; logic is sequence, selection, iteration.

## Systems thinking frame
Every thing is input → process → output, moving state A to state B: a function, an app, a business, a person. Sub-systems compose. Use it to:
- decompose (find the smaller systems),
- debug (isolate which sub-system is wrong instead of poking at random),
- refine (improve one system at a time).

An input → output spec with a precise state A → state B is a well-scoped, verifiable task for an agent.

## Value creation system
Move people from pain to benefit by giving back or enriching time. Work theoretical → physical, left to right. Score, then score faster, without shipping negative value (bugs, regressions, hard-to-change code). Agents make code cheap, which also speeds up negative value; who/what/why/how is the context they cannot invent.

## How to actually validate value
- Customer work: talk to them, prototype, wireframe.
- Existing product: big-picture event storming to see current problems and how work flows.
- New venture: quantitative (market size, demand) plus qualitative (talk to users and domain experts).
- No code is needed to pass the problem guess point.
