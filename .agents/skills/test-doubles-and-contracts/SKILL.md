---
name: test-doubles-and-contracts
description: 'Hand-written fakes, spies and contract tests that keep them honest. Use whenever a test needs a stand-in for a repository, gateway, clock, mailer, payment or API, when replacing library mock soup, or when reviewing AI-generated mocks. Every fake must pass the same contract spec as the real implementation.'
---

# Test Doubles and Contract Tests

Standing rule: **"It's okay to mock… just make sure you mock correctly. You want parity between what's real and fake."** A fake with no contract test is a guess that nothing checks: "we're only testing our mocks."

## When to use
- A use-case test needs a repository, gateway, clock, mailer, payment service or any role.
- You see `vi.mock`/`jest.mock` of your own modules, inline mock objects copy-pasted across files, or a fake with no shared spec.
- Reviewing agent-generated tests.

## Rules
1. Call them **test doubles** or **fakes**; skip the stub/spy/mock taxonomy debate.
2. **Give the real collaborator a contract** (interface/role) so a fake can implement it. Only at real seams (`responsibility-driven-design`, George Clooney test).
3. **Hand-write fakes for your own roles.** A fake plays two roles: it implements the contract, and it records calls for assertions (a spy). Growing the contract forces the fake to grow (the compiler/type checker yells at you).
4. **Fakes live in their own files** (next to the contract or in one clearly named test-doubles folder), never inline in specs; inline doubles get duplicated.
5. **Controllable fakes set the state of the world** for each edge case (user exists, banned, email taken, provider down), via constructor seeding or builders.
6. **Library mocks only for trivial stubs** whose behavior doesn't matter (a logger, a fake app object in an incoming-adapter test).
7. Wait for the rule of three before extracting a generic spy helper.
8. **Contract test per role** (level 4): one spec file (e.g. `*.contract.spec` / `.ispec`) that loops over **every implementation**, fake and real, with the same assertions. "You're testing the contract, not the implementation." If one breaks, they all break. Runs in the acceptance phase or wherever real infrastructure is available; the fake's run is fast.
9. **Time and randomness are roles** too: `Clock` with `SystemClock` + `FakeClock` (can tick forward instantly), covered by the same contract. Retry backoff waits through the same role, so failing-path tests never really sleep; never weaken the production retry policy to make tests faster.
10. In-memory repositories store **plain objects** (map like the real store does) so they behave like the database, and double as builders for seeding state.

Code: [fakes, spies, contract tests, FakeClock](./references/doubles-examples.md).

## Procedure
1. Identify each collaborator the subject talks to (indirect inputs / outputs).
2. For each: contract exists? If not, extract one (only if it's a real seam).
3. Write or reuse the hand-written fake + spy methods (`getTimesCalled`, `getCallsTo`).
4. Write or extend the contract spec looping over fake and real.
5. Use the fake in level-3 tests; assert result, state and communication.

## Anti-patterns to refuse
- Library-mock soup: `vi.mock('../services/emailService')` repeated across spec files.
- Fakes and production implementations tested separately, or not at all.
- Mocks that return whatever makes the test green.
- Spying on private helpers; asserting implementation details instead of role calls.
- Creating a contract for a single actor that will never have a second (outside real seams).

## AI guardrails
AI-generated mocks can lie. They return whatever makes the test green and nothing checks them against production. Ask for a hand-written fake **plus** a contract spec looped over fake and real, so a hallucinated fake fails the moment it diverges. Reject any generated mock of your own role that has no contract test.

Sources: testing--test-doubles, testing--contract-tests, essentials-physical--subject-system-verification, cheatsheet--testing-rules, cheatsheet--ai-agents; fastapi-genai-skillset → testing-quality/test-stability-retries-telemetry
