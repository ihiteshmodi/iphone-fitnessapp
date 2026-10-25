# Question Bank (Problem Guess Point)

Load when you need questions to ask. Ask 3–5 at a time, most important first. Skip anything already answered in `docs/design/**` or the conversation.

## Vision and value
- In one sentence, what are we building and for whom?
- Who exactly benefits? Name the **role** (e.g. "conference organizer"), not just a job title or "users".
- What pain do they have today, and what benefit will they get? (time given back, or time enriched)
- What will they be able to do that they cannot do now? (capabilities)
- How do we know this is worth building? Any qualitative (conversations, complaints) or quantitative (usage, market size) evidence?
- Why now?

## The 3 roles must all win
- **User**: does this give them time back or enrich their time?
- **Customer** (whoever pays): how does this make or protect revenue?
- **Developer**: will the codebase stay easy to change after this? Anything that would make the next feature harder?

## Concrete scenario
- Walk me through one real example: who is the person, what state are they in now (state A), what do they want (state B)?
- What do they do, step by step, and what do they see at each step?
- What should happen when it goes wrong? (invalid input, missing data, already done, not allowed, external service down)
- Which example is the most complex one? (Design against it first.)

## Framing and boundaries
- What is the context: single user or multi-user, real-time or not, web/mobile/CLI, online/offline?
- Is any part of this something we should buy or reuse rather than build? (email, auth, payments are usually generic)
- What is explicitly out of scope for this iteration?

## Done and verification
- How will you know this is done? (Answer in user-visible outcomes, not "the code compiles".)
- Who verifies it: you, a domain expert, real users, a metric?
- Which failure would hurt most: a bug, slowness, building the wrong thing, or an unclear feature?
- After release, which KPI tells us it worked? (execution guess point)

## Uncertainty and strategy
- What are you most unsure about? Which guess, if wrong, costs the most?
- What is the one thing we should validate before building?
- Is this an unvalidated MVP (go light, ship to learn) or a feature on a product with real users (full workflow)?

## The 4 pillars (developer trade-off lens)
- Architecture: will the structure support all 3 roles' long-term goals?
- Design: can a developer discover and understand how to add, change and test this feature?
- Testing: can we define what it does ahead of time and know it still does it?
- Strategy: given time, money, team and codebase quality, how much rigor is right now?

## Pre-flight (also use when stuck)
Do I know what I am doing? Why? Who is it for? At what level does this need to happen?
