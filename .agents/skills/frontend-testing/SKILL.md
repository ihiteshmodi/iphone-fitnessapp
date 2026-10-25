---
name: frontend-testing
description: 'Frontend and UI testing. Use when writing or reviewing tests for a UI, page, screen, component or form in React, Vue or any view library: whole-feature tests on presenters and controllers without rendering the UI, fake gateways with contract tests, component tests, and the shared E2E acceptance test.'
---

# Frontend Testing Strategy

Standing rule: **test the pure middle without starting the view library.** When presenters and controllers are plain objects, the whole feature suite runs in milliseconds with no browser and no backend.

## When to use
Any frontend feature work (paired with `frontend-architecture`), or reviewing a frontend suite that only has E2E or only has component snapshot tests.

## Levels
| Level | What it answers | How |
|---|---|---|
| System / E2E | Do API calls work, reach the backend, and translate into the right UI? | The shared acceptance test (one per feature) through a page-object protocol driver. Result verification only |
| Whole feature (app) | Does the feature behave? | Compose controller + presenter + repository with a **fake gateway**; call controller methods, assert presenter view models. No UI framework, no real API |
| Application logic | Rules and edge cases | High-value unit tests on controllers, domain objects, presenters' selectors ("creating a user shows validation errors") |
| Components & adapters | Rendering and adapters | Components mostly stateless → simple render-the-view-model tests; stateful components behave like small state machines. **Cache hydration / gateway** = outgoing adapter contract test. Incoming-adapter tests matter less on the frontend |

## Rules
1. **One acceptance test per feature**, shared with the backend; never a frontend-specific copy. The frontend may only assert "check your email" while the email itself is verified at the backend's level 3.
2. **Fake gateways need contract tests** against the real API client, so the fake can't drift.
3. Use-case tests never know which state library is used; test hydration separately.
4. Assert view models, not DOM details, in feature tests; assert communication (gateway calls) where it matters ("rejects a blank title and never calls the backend").
5. Strategy choice: (A) a few E2E tests + carve inward with high-value unit tests (best start for task-based UI apps), or (B) incoming contract tests + high-value integration tests. Mixing is fine; judge by confidence, not dogma. In a messy frontend, stop the bleeding with E2E first.
6. Reusable page objects make new features "plug and play".

## Example (TypeScript / Vitest illustration)
```ts
class FakeTodosGateway implements TodosGateway {
  private todos: TodoDTO[] = [];
  created: string[] = [];
  withTodos(...titles: string[]) {
    this.todos = titles.map((title, i) => ({ id: String(i + 1), title, completedAt: null }));
    return this;
  }
  async getAll() { return [...this.todos]; }
  async create(title: string) {
    const dto = { id: String(this.todos.length + 1), title, completedAt: null };
    this.todos.push(dto);
    this.created.push(title);
    return dto;
  }
}

function createApp(gateway = new FakeTodosGateway()) {
  const cache = new Observable<TodoDTO[]>([]);
  const repo = new TodosRepository(gateway, cache);
  return { gateway, repo, presenter: new TodosPresenter(cache), controller: new TodosController(repo) };
}

describe('todos', () => {
  it('shows a new todo at the bottom of an existing list', async () => {
    const { repo, presenter, controller } = createApp(new FakeTodosGateway().withTodos('Buy milk'));
    await repo.load();

    await controller.createTodo('  Walk dog ');

    const vm = presenter.load();
    expect(vm.items.map((i) => i.label)).toEqual(['Buy milk', 'Walk dog']);
    expect(vm.remaining).toBe('2 left');
  });

  it('rejects a blank title and never calls the backend', async () => {
    const { gateway, controller } = createApp();
    const result = await controller.createTodo('   ');
    expect(result.isFailure).toBe(true);
    expect(gateway.created).toEqual([]);            // communication verification
  });

  it('notifies the view when the cache changes', async () => {
    const { presenter, controller } = createApp();
    const onChange = vi.fn();
    presenter.subscribe(onChange);
    await controller.createTodo('Read GOOS');
    expect(onChange).toHaveBeenCalledTimes(1);
  });
});
```

## Anti-patterns to refuse
- Only E2E tests because the code isn't structured for anything else.
- Tests that must render the UI framework and mock `fetch` to check a business rule.
- Separate acceptance specs per platform.
- Fake gateways with no contract test.

## AI guardrails
When presenters and controllers are plain objects, an agent can run the whole feature suite in milliseconds after every edit; that short loop is what makes AI-generated frontend changes safe to accept. A shared contract test catches the common agent failure of a fake gateway drifting from the real API.

Sources: frontend--testing, frontend--control-center, testing--strategies
