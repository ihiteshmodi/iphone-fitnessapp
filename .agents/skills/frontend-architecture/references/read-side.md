# Read Side: Gateway → Cache → Observer → Presenter → View Model → Component

Load when building data display for a feature. TypeScript/React illustration; the same shape works in Vue, Svelte or any view library.

1. **Gateway / API client** (infrastructure): sends requests.
2. **Cache** (infrastructure): stores fetched data = global/app state, persisted across screens.
3. **Observer** (coordinator): notifies subscribers when the cache changes. "Global state… fundamentally it is an observer."
4. **Presenter**: subscribes to changes and rebuilds view models (`presenter.load()`); selectors live here.
5. **View model**: the exact shape the component renders. Components "shouldn't take on the job of preparing data to be seen. They should just get the data to be seen."
6. **Component**: binds to the presenter and re-renders. "That's how you connect pure code to React."

Rules:
- Components never know about the cache/store (dependency rule).
- Reads go straight to the data store and return the simplest shape; do not load domain objects for reads.
- Get reactivity working during the walking skeleton.

## Minimal observable store (the whole "global state library")
```ts
// shared/persistence/observable.ts
type Listener = () => void;

export class Observable<T> {
  private listeners = new Set<Listener>();
  constructor(private state: T) {}

  get(): T { return this.state; }

  set(next: T) {
    this.state = next;
    this.listeners.forEach((listener) => listener());
  }

  subscribe(listener: Listener): () => void {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  }
}
```

## Presenter with selectors
```ts
// modules/todos/todosPresenter.ts
export interface TodoItemVM { id: string; label: string; done: boolean }
export interface TodosViewModel { items: TodoItemVM[]; remaining: string }

export class TodosPresenter {
  constructor(private cache: Observable<TodoDTO[]>) {}

  load(): TodosViewModel {
    const todos = this.cache.get();
    const open = todos.filter((t) => t.completedAt === null).length;    // selector lives here
    return {
      items: todos.map((t) => ({ id: t.id, label: t.title, done: t.completedAt !== null })),
      remaining: `${open} left`,
    };
  }

  subscribe(onChange: () => void) { return this.cache.subscribe(onChange); }
}
```

## Component binding
```tsx
function TodosList({ presenter }: { presenter: TodosPresenter }) {
  const [vm, setVm] = useState(presenter.load());
  useEffect(() => presenter.subscribe(() => setVm(presenter.load())), [presenter]);
  return <ul>{vm.items.map((i) => <li key={i.id}>{i.label}</li>)}</ul>;
}
```
In Vue: a `ref` updated from `presenter.subscribe`; in any library, the binding is the only framework-specific code.
