---
name: domain-discovery
description: 'Shared language and DDD strategic design. Use when teams or areas use the same word differently, to build a glossary, find subdomains and bounded contexts, decide build vs buy, draw a context map, or event storm one concrete scenario into commands, events, views and data.'
---

# Domain Discovery (Solution Guess Point)

Standing rules: **drive everything through one concrete scenario** (person at state A wants state B, here is their experience). Event storming without one leaves your brain "like mush". Names you agree on here become the code, so criticise them hard.

## Purpose
Given the who/why/what from `clarify-requirements`, decide what we will build, what someone will experience, which words mean what, and where the boundaries are. Output feeds `architecture-decisions` and `state-machines-invariants`.

## When to use
- After the problem guess point is approved and before any modelling in code.
- A request mixes several areas (billing, emails, scheduling, core logic) or uses ambiguous words ("reservation", "user", "account").
- A new feature touches an existing bounded context and you need to know where it belongs.

Not for: single pure functions, UI polish, or a feature that clearly lives inside one known module with settled language (go to `fa2str-workflow`).

## Inputs
Approved `impact-map.md` and `.feature` file. If either is missing, run `clarify-requirements` first.

## Procedure
1. **Glossary.** List the domain words from the scenarios with one-line meanings. Ask the user (the domain expert) to confirm or correct. Same word, different meaning in two areas = two contexts (a *User* in identity is not a *Pre-reader* in the core domain).
2. **Subdomains (problem space).** Brain-dump every problem category the app needs, unfiltered. Stop when you run out. Do not group yet.
3. **Classify** each subdomain:
   - **Core**: unique, the reason the product exists. Build it.
   - **Supporting**: needed, not unique, no good off-the-shelf option. Build reluctantly.
   - **Generic**: solved problem (email, auth, payments, analytics). Buy or use a service.
4. **Bounded contexts (solution space).** "Act like Aristotle": for each item ask "is this actually part of that topic?", combine items that share language, name the cluster. Add rather than remove while grouping; new language emerges. Always keep **one bounded context that represents your actual (core) domain**.
5. **Build / buy per context** and **context map**: who relies on whom, which are external. Each context maps to one module folder later (`modules/<context>/`).
6. **Event storm ONE scenario** (process modelling):
   1. Take one Given/When/Then with a clear beginning and end.
   2. Domain events, past tense, unordered first, then ordered.
   3. Commands (imperative) that cause each event.
   4. Actor per command: a person/role, or *System* for automatic follow-ups.
   5. The data each command works against (prefer required inputs/outputs over naming aggregates).
   6. The context each command/event belongs to.
7. **Critique with the smell rule.** Two events in a row in the **same context** changing the **same concept** inside one process usually means a missing state machine or a wrong model. Redesign (often: the thing starts in an initial state and transitions, instead of "create X then create Y"). Cross-context chains linked by events are fine.
8. **Add views and tally data.** Put screens next to the commands. For every command–event pair write the input data and the output data. Walk the screens line by line; every ambiguity is a question for the user or designer.
9. **One state change per step, per context, linked by events.** If a step changes 3–4 things at once you need a transaction around all of them. Linking by events means any step can fail and the system stays consistent (and steps can be retried idempotently).
10. **Hand off** the state pieces you own (what changes, which transitions) to `state-machines-invariants`.

Worked FeedBook tables (subdomains, contexts, event storm with the smell, refined view→command→event tally): [feedbook walkthrough](./references/feedbook-walkthrough.md). Load it the first time you run this skill in a session.

## Outputs
- `docs/design/<feature>/glossary.md`
- `docs/design/<feature>/subdomains-context-map.md`: subdomain list, classification, contexts, build/buy, context map (mermaid allowed).
- `docs/design/<feature>/event-storm.md`: the GWT scenario, the ordered table `View | Actor | Command | Input data | Event | Context`, smells found and how they were fixed, open questions.

## Exit gate
- Every command has an actor, input data, one resulting event and one owning context.
- No unresolved same-context event chain.
- The user confirmed the glossary and the core context.

## Anti-patterns to refuse
- Event storming with no concrete scenario.
- Treating technical splits ("delivery", "shop", "api") as subdomains without checking language.
- Modelling entities before the problem guess point is sorted, or learning DDD on a problem with no real value (patterns only).
- Building generic subdomains yourself (auth, SMTP, payments).
- A synchronous "accept then create account then email" chain in one call.

## AI guardrails
- Agents mirror the vocabulary you give them. They cannot crunch knowledge with your domain experts. Settle language and boundaries first and generated code stops being generic CRUD.
- Grouping by language, placing boundaries and spotting same-context chains are human judgement calls. An agent will happily invent an extra entity and a synchronous chain. Give it the GWT scenario plus the redesigned event table as the spec, and review its output against the smell rule.

## Handoff
`state-machines-invariants` for each state piece we own; `architecture-decisions` for modules, deployable units and the event bus.

Sources: essentials-theoretical--domain-discovery, ddd-feedbook--subdomains, ddd-feedbook--bounded-contexts, ddd-feedbook--consolidating, ddd-feedbook--event-storming, ddd-feedbook--refining
