# Write Side: Component → Controller → Domain Object → Repository → Gateway

Load when building forms, commands or any state-changing interaction.

1. **Component**: holds ephemeral form state; calls the controller on submit (`controller.register(...)`).
2. **Controller**: a use case / command handler, "effectively the exact same thing as a backend use case." One per use case or a small cluster (`CreateTodoController`, `EditUserController`).
3. **Domain object**: the decision maker. "Anytime you intend to perform a state-changing command, it must typically pass through a domain object to determine if we should continue."
4. **Repository**: receives valid domain objects, calls the gateway, updates the cache. Repository and gateway may be one object in small apps.
5. **Gateway → backend**. The cache updates and everything flows back down the read side reactively.

Rules:
- Share value objects and DTOs with the backend through a shared package; frontend-only domain objects (e.g. `RegistrationForm`) still exist.
- Frontend domain logic is real in logic-heavy apps (editors, audio tools, compatibility rules); front-loading it gives faster feedback (no network round trip).
- Name use cases by intent: "register user", "edit user", not "submit form".

## Full write stack (TypeScript illustration)
```ts
// packages/shared/todoTitle.ts: imported by frontend AND backend
export class TodoTitle {
  private constructor(readonly value: string) {}
  static create(raw: string): Result<TodoTitle> {
    const clean = raw.trim();
    if (clean.length < 1 || clean.length > 80) return Result.fail('Title must be 1–80 characters');
    return Result.ok(new TodoTitle(clean));
  }
}

// modules/todos/todosGateway.ts: the only contract that knows about the backend
export interface TodosGateway {
  getAll(): Promise<TodoDTO[]>;
  create(title: string): Promise<TodoDTO>;
}

// modules/todos/todosRepository.ts
export class TodosRepository {
  constructor(private gateway: TodosGateway, private cache: Observable<TodoDTO[]>) {}
  async load() { this.cache.set(await this.gateway.getAll()); }
  async save(title: TodoTitle) {
    const created = await this.gateway.create(title.value);
    this.cache.set([...this.cache.get(), created]);      // observers fire → presenter rebuilds
  }
}

// modules/todos/todosController.ts
export class TodosController {
  constructor(private repo: TodosRepository) {}
  async createTodo(rawTitle: string): Promise<Result<void>> {
    const titleOrError = TodoTitle.create(rawTitle);      // domain object decides
    if (titleOrError.isFailure) return Result.fail(titleOrError.error);
    await this.repo.save(titleOrError.value);
    return Result.ok();
  }
}
```

## Registration controller shape
```ts
class RegistrationController {
  constructor(private repo: UsersRepository) {}
  async register(props: RegistrationProps) {
    const formOrError = RegistrationForm.create(props);  // FirstName, LastName, Username, Email value objects
    if (formOrError.isError) return formOrError;         // the user must fix it
    return this.repo.register(formOrError.value);        // repo → gateway → backend; caches the result
  }
}
```
