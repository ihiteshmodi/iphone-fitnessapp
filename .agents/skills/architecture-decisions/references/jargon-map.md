# Jargon Map: file every term under an essential

Load when the user (or a library, article, or agent) uses architecture or testing jargon. Learn the 12 essentials, then classify new terms instead of chasing each one. Many terms are "the same concept said a little differently".

Hierarchy: industry topics (patterns, tools, techniques) → 12 essentials → 2 mental models (abstraction, feedback loop), tied together by systems thinking.

## The 12 essentials (one line each)
| Group | Essential | One-liner | Ask yourself |
|---|---|---|---|
| Metaphysical | Abstraction | Separate the what from the how; work top-down. | Do I know what, why, for whom, at what level? |
| Metaphysical | Feedback loop | Everything is a guess; feed forward, get feedback, refine, keep loops tight. | What guess am I making and how will I know it is right? |
| Theoretical | Value identification | Who you help, why, what they will be able to do. | Can I connect this to a role's goal? |
| Theoretical | Domain discovery | Shared language → features, stories, examples, boundaries. | Does everyone use the same words? |
| Theoretical | Strategic design | Stereotype, develop, integrate, prioritize components. Core = build, generic = buy. | Build, buy, or use a service? |
| Physical | Vertical slicing | Features first-class in folders and tests: modules → features → operations. | Can I see the features from the folder tree alone? |
| Physical | Horizontal decoupling | Every line in the right layer; contracts between layers. | Where does this line belong? |
| Physical | Temporal decoupling | End each slice at its own state change; handlers start the next. | What happens after, before, only when? |
| Physical | Composition | Wire collaborators deliberately in one composition root. | How are parts wired per environment? |
| Physical | Subject/system verification | Boundary around the subject; result, state or communication verification. | Am I clear on the subject under test? |
| Physical | Walking skeleton | Deploy the thinnest slice through all components first, with an E2E test. | Can this even deploy and run? |
| Physical | Deployment & delivery | One pipeline: commit → acceptance → deploy. | Can negative value reach users? |

Any question maps to one metaphysical essential plus one theoretical or physical essential.

## Jargon → essential
| Jargon | Essential |
|---|---|
| Hexagonal, onion, ports & adapters, clean architecture, stereotypical architecture, core vs infra, separation of concerns, levels of abstraction | Horizontal decoupling |
| CQS (read path vs write path) | Vertical slicing |
| Package by feature, screaming architecture, modules, bounded contexts (as folders), operations (API calls) | Vertical slicing |
| Event-based architecture, coordinator, event bus, outbox, unidirectional data flow | Temporal decoupling |
| Composition root, poor man's DI, DI containers, encapsulation, OOP/FP composition | Composition |
| Contract tests, result / state / communication verification, test doubles | Subject/system verification |
| Commit phase, acceptance phase, CD pipeline | Deployment & delivery |
| Impact mapping | Value identification |
| Big-picture event storming, process modelling, event modelling, example mapping | Domain discovery |
| Core / supporting / generic subdomains, build vs buy, glue code (RDD) | Strategic design |
| Gherkin, executable specifications, BDD, TDD, what vs how, declarative vs imperative | Abstraction |
| Sagas, state machines | Abstraction + feedback loop, built at the stateful guess point |

Beyond hexagonal: hexagonal covers technical isolation from infrastructure. The course adds what drives development: BDD, DDD, impact mapping, value, pain and benefit.

## Tools belong to guess points
"It's less about the tool, more about the inputs and outputs of the system creating value." Knowing which guess point a tool serves removes most confusion.
| Guess point | Tools |
|---|---|
| Problem | Talking to users, prototyping, big-picture event storming, impact mapping |
| Solution | Process modelling (tactical event storming), event modelling, context mapping, example mapping, user story mapping |
| Architecture | Component stereotyping, build vs buy, core/supporting/generic, NFR analysis |
| Physical | TDD, contract tests, builders, CI pipeline |

Choose tools by responsibility. If a responsibility (e.g. "collect feedback") is already covered by something in place, add no new tool.
