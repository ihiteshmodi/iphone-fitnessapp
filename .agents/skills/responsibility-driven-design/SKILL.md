---
name: responsibility-driven-design
description: 'Object and module design with responsibility-driven design (RDD). Use when a feature has more than about four collaborating pieces, when deciding which class/module owns a behavior, whether to add an interface or abstract class, how much OOP to use, or when reviewing god services and misplaced responsibilities.'
---

# Responsibility-Driven Design (RDD)

Standing rule: software is a set of **responsibilities** (doings and knowings). They are grouped into **roles**, roles **collaborate**, and objects or functions are the **actors** that play those roles. Lean into **one dominant role per object**.

"You should be writing no code unless you're very clear on who plays what role and why they need it." Design = discoverability + understanding.

## When to use
- More than ~4 pieces collaborate (the mind holds about four at once): go to paper and run RDD before code.
- "Where should this logic go?", "is this a service?", "do I need an interface here?"
- Reviewing generated code with god services, `IFoo`/`FooImpl` pairs, or controllers doing IO.

## Procedure (3 steps + optional 4th)
1. **List responsibilities** from one concrete example (unordered is fine). Each is a *doing* ("detect mouse scroll", "save user") or a *knowing* ("knows passwords under 5 chars are invalid", "knows current zoom").
2. **Assign responsibilities to roles using the 6 stereotypes.** One dominant role per object; split an object that plays two.
3. **Define collaborations** (who calls whom, who notifies whom). Do this last. A small sequence diagram or numbered flow is enough.
4. *(Optional)* **Find tools/libraries** that already play a role.

## The 6 object stereotypes
| Stereotype | Responsibility | Backend examples | Frontend examples |
|---|---|---|---|
| Information holder | Knows and holds data | Request DTO, event payload | Mouse event, view model |
| Structurer | Essential data + rules for how it changes (≈ aggregate) | Post aggregate with comments | Camera with movement rules |
| Service provider | Stateless computation / utility | Price calculator, password hasher | Canvas projection math |
| Coordinator | Subscribe / notify; routes events (observer) | Router, web server, event bus | Store / application observer |
| Controller | Decides and tells others to do work; executes a use case | `CreateUser` use case | Zoom controller, page controller |
| Interfacer | Bridges to the outside: network, files, peripherals, 3rd-party APIs | Repositories, payment/mail adapters, HTTP framework | Window/canvas APIs, API client |

Control center = coordinators + controllers: where the main decisions happen. You own it; frameworks must not (see `frontend-architecture`).

## Placement heuristics
- Name responsibilities generally ("subscribe/notify", "persist user"), not by framework.
- Hear "state change" or "updating" → a controller (often with a structurer and an interfacer).
- Controllers **delegate** the change: get the post, ask it to add the comment, ask the repository to save.
- Anything touching network, filesystem, clock, randomness or a 3rd-party API → interfacer.
- Rules about how data changes → structurer / information holder (domain).
- Keep IO out of the application layer; IO goes through interfacer contracts.
- **Controllers are called upon; they do not subscribe.** A separate subscription object listens and calls the use case.
- Name use cases by their dominant responsibility ("UpdateCanvasProjection", "RegisterUser"), not "HandleX" or "SubmitForm".
- There is no statically right answer; it is a game of coupling and cohesion. One object occasionally playing two stereotypes is normal — don't agonise.

## Contracts: the George Clooney test and levels of realness
- Ask **"Who else is going to play this role?"** If only one concretion exists or is planned, no contract is needed. Premature interface = "You George Clooney'd it."
- Keep contracts where real seams are: repositories, clock, payments, mail, gateways (infrastructure boundaries, where fakes are needed).
- Pick the construct by intended level of abstraction: interface/type (role, >1 actor) → abstract class (only after the rule of three) → class → plain object (data). See [levels of realness](./references/levels-of-realness.md).
- **How much OOP**: the paradigm is an implementation choice under the same abstraction. Scripts (functions) or an object network both express the same high-level steps and events. Prefer objects where encapsulation and information hiding protect rules; plain functions for stateless transformations.

## Outputs
A role map in `docs/design/<feature>/architecture.md` (or the PR description):
`Object | Stereotype | Doings / knowings | Collaborates with`, plus the collaboration flow. Worked example and before/after code: [zoom example](./references/zoom-example.md).

## Anti-patterns to refuse
- Calling everything a "service": services that never break down far enough, references passed everywhere.
- God objects fusing IO + rules + math + state + rendering.
- Interfaces for a single implementation; abstract classes before interfaces; interfaces as a "public API" with no role.
- Controllers subscribing to events; information holders doing IO.
- Letting a framework (React, Express) be the control center.

## AI guardrails
- AI makes building fast, but it does not decide where doings and knowings belong. Hand the agent a responsibility list with stereotype labels instead of "build zoom": it has a spec to follow and you have a map to review against.
- Ask an agent to "add zoom" and you get the god-service *before* shape. Give it the role map and one dominant role per object, and the output becomes reviewable piece by piece. Stereotype labels make misplaced responsibilities obvious ("this information holder is doing IO").
- Agents love `IFoo` + `FooImpl`, factories and abstract bases "for flexibility". Run the George Clooney test in review and inline anything with no second actor.

Sources: abstraction-rdd--levels-of-realness, abstraction-rdd--roles-actors, abstraction-rdd--how-much-oop, abstraction-rdd--better-design, abstraction-rdd--rdd, abstraction-rdd--stereotypes, abstraction-rdd--category-theory, abstraction-rdd--zoom-example, abstraction-rdd--critique-next-steps, essentials-theoretical--strategic-design
