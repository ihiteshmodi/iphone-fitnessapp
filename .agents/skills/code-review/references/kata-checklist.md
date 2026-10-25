# Kata Review Checklist (filtered for real projects)

Load during every review. Recurring feedback from the course's code reviews; use it as a PR rubric for your own and AI-generated code.

| # | Check | Smell (before) | Fix (after) |
|---|---|---|---|
| 1 | Shape matches the problem | A stateless problem modelled with no input and generated output | `fn(input) => output`, stateless |
| 2 | Red for the right reason | Test fails because the function doesn't exist | Export a stub in the red step |
| 3 | Simplest transformation (by hand) | Map / loop / variables for the first test | Constant first; climb the TPP one rung at a time. Agent mode: no speculative generality beyond the scenarios |
| 4 | Rule of three | Refactor after one or two repeats; examples added mid-refactor | Refactor on the third repeat, structure only |
| 5 | One example per loop (by hand) | Two tests in one red-green-refactor | Enable one test at a time. Agent mode: every test was seen failing once |
| 6 | Refactor XOR transformation | New behavior + cleanup in one commit | Split into two commits |
| 7 | Commit cadence & types | One big commit; no intent in the message | Commit on green; `feat` / `fix` / `refactor` prefix, plain message for everything else |
| 8 | One `it`, one expectation of behavior | Several examples asserted in one `it` | Separate `it`s or `it.each` rows |
| 9 | Concrete example names | "…divisible by both three and five" | "returns 'FizzBuzz' for 15"; abstract behavior in `describe` |
| 10 | Responsibility names, not how | "sets result to true and error to null…" | "can detect valid passwords", "can calculate the minimum value" |
| 11 | Positive names | "does not know dog is not a palindrome" | "knows dog is not a palindrome" |
| 12 | No `else` | `if / else if / else` chains | Early-return `if`s |
| 13 | Stateless means no instance | `new PasswordValidator()` | Static method or plain function |
| 14 | Encapsulate what varies | Copied tests, hard-coded reasons | `it.each` rows holding input + expected |
| 15 | Named example sets | `firstInput`, `secondInput` | `inputContainingZeros`, `inputWithNegativeNumbers` |
| 16 | Order-independent assertions | Strict equality on an unordered errors array | `toContain` per error |
| 17 | Type what you invent | Loose return objects | A named result type/interface (a role) |
| 18 | No "what" comments | Comments restating the code | Expressive names; comment only "why" |
| 19 | Readable test structure | Nested conditional describes; vague "parts" | Swim lanes by category + concrete examples; named concepts |
| 20 | Decompose, then compose | One function with flags and nested branches | Tiny responsibilities; top level reads like the algorithm |
| 21 | Commits tell the story | Design done off-screen in one jump | One guess at a time; design it twice |

Agents trip rows 6, 8, 10 and 18 most (and 3, 5 when pairing step by step). Paste the failing row into the instruction you send back.
