# State Management: Kinds of State and Where Each Lives

Load when deciding where a piece of frontend state goes, or whether to add a state library.

"It's either global and it gets translated into domain and view, or it's component state."

| Kind of state | Lives in | Notes |
|---|---|---|
| API cache (the frontend "database") | API client / store (HTTP client cache, GraphQL client cache, store/reducer) | Infrastructure. Filled by the gateway, updated after writes |
| Global / app state | Cache + observer (subscriptions) | Persists across screens. "Fundamentally it is an observer" |
| Domain models | Domain objects (write side) | Rules and validation; derived from global state when a command needs them |
| View models | Presenter | Rebuilt on every cache change; components get their initial state from them |
| Component state | The component (`useState`, `ref`) | Ephemeral: forms, toggles. Gone when you leave the screen. Never hoist toggles into global state |

## Two approaches (choose knowingly)
- **Centralised**: one application data model (store) that everything subscribes to.
- **Delegated**: data and behavior live on related objects (aggregates) you observe individually, like the backend.
Both have trade-offs; often the best is in the middle. View data, model data, updating view data and triggering re-render are real responsibilities that need owners.

## Rules
- No state library is required; a hand-written observable store designed by wishful thinking is enough for most apps.
- Use-case (controller/presenter) tests don't know the state library exists. Test cache hydration separately as an outgoing-adapter test. Keep them separate.
- The real reason frontend apps get complex is state management: where data belongs, who operates on it, which namespace.
