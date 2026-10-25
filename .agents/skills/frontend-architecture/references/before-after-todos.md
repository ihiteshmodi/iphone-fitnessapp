# Before / After: Taking the Control Center Back (React illustration)

Load when reviewing or generating a component that fetches, validates or maps data.

## Before: React is the control center (what agents usually generate)
```tsx
export function TodosPage() {
  const [todos, setTodos] = useState<TodoRow[]>([]);
  const [title, setTitle] = useState('');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/todos')                                    // infrastructure
      .then((res) => res.json())
      .then((dtos: TodoDTO[]) =>
        setTodos(dtos.map((d) => ({ id: d.id, label: d.title, done: d.completedAt !== null })))); // mapping
  }, []);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const clean = title.trim();
    if (clean.length < 1 || clean.length > 80) return setError('Title must be 1–80 characters'); // business rule
    const res = await fetch('/api/todos', { method: 'POST', body: JSON.stringify({ title: clean }) });
    const created: TodoDTO = await res.json();
    setTodos([...todos, { id: created.id, label: created.title, done: false }]);                   // hand-rolled cache
    setTitle('');
  }

  const remaining = todos.filter((t) => !t.done).length;  // selector in the component
  return (/* list, "{remaining} left", form, error */);
}
// To test "adding a todo" you must render React and mock fetch.
```

## After: the component only renders the view model and forwards intent
```tsx
export function TodosPage({ presenter, controller }: TodosPageProps) {
  const [vm, setVm] = useState(presenter.load());
  useEffect(() => presenter.subscribe(() => setVm(presenter.load())), [presenter]);

  const [title, setTitle] = useState('');                 // component state: ephemeral
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    const result = await controller.createTodo(title);
    if (result.isFailure) return setError(result.error);
    setTitle('');
    setError(null);
  }

  return (
    <form onSubmit={handleSubmit}>
      <ul>{vm.items.map((i) => <li key={i.id}>{i.label}</li>)}</ul>
      <p>{vm.remaining}</p>
      {error && <p role="alert">{error}</p>}
      <input value={title} onChange={(e) => setTitle(e.target.value)} />
      <button>Add</button>
    </form>
  );
}
// No fetch, no mapping, no rules. Swappable for another view library.
```

## Wrap hooks you can't avoid
Course opinion: hooks force structure into your code ("don't tell me I need to name things with `use` in front"). Extract a routing service instead of calling the router hook from logic:
```ts
export interface RoutingService { goTo(path: string): void }
// composition root creates a React-router-backed implementation; controllers depend on RoutingService only.
```
