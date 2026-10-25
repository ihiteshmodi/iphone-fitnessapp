# Code Placement Quiz (TypeScript illustration)

Load when deciding where a line belongs or reviewing a diff. Every line gets two answers: **which module/feature** and **which layer**. Tie-breaker: "It's not about where it comes from, it's about what it touches."

```ts
/* 1 */ const { email, username, password } = req.body;
/* 2 */ if (await this.users.findByEmail(email)) return { type: 'AlreadyCreated' };
/* 3 */ if (!EMAIL_PATTERN.test(value)) return new ValidationError('email');
/* 4 */ await prisma.user.create({ data: user.toPersistence() });
/* 5 */ this.createdAt = new Date();
/* 6 */ export abstract class UseCase<In, Out> { abstract execute(input: In): Promise<Out>; }
/* 7 */ await notifyAdmins(job); // appended right after postJob()
/* 8 */ const res = await fetch(`${apiUrl}/users`, { method: 'POST', body: JSON.stringify(dto) });
```

| # | Where it belongs | Why |
|---|---|---|
| 1 | Incoming adapter: the controller in the feature folder | Extracting and validating the request shape is what incoming-adapter tests verify, before the app is called |
| 2 | Application layer: the use case | "If the user already exists, return an error" needs the repository, so it is an application rule |
| 3 | Domain: an `Email` value object | Level-1 input → output validation; keep data and behavior together |
| 4 | Infrastructure: the concrete repository | An actor playing the `UsersRepository` role; it touches the DB |
| 5 | Not in the domain: inject a `Clock` | `new Date()` touches the system clock, which is infrastructure; the domain stays pure |
| 6 | `shared/core/` (and only once needed 3+ times) | A base class is accidental complexity, for the developer |
| 7 | An event handler in the module that cares, triggered by `JobPosted` | Appended awaited side effects are temporal coupling; if one fails, the rest never run |
| 8 | `shared/` as an API driver/gateway (or the feature's gateway) | A REST driver is accidental complexity / an interfacer |

## Before: fat route
```ts
app.post('/users', async (req, res) => {
  const { email, password } = req.body;                                       // HTTP parsing
  const existing = await db.users.findOne({ where: { email } });
  if (existing) return res.status(409).json({ error: 'User already exists' }); // a rule
  const user = await db.users.create({ data: { email, password, createdAt: new Date() } }); // persistence + time
  return res.status(201).json(user);
});
```

## After: slim controller → use case → contract
```ts
export interface UsersRepository {                     // adapter: a role
  findByEmail(email: string): Promise<User | null>;
  save(user: User): Promise<void>;
}
export interface Clock { now(): Date }

export type CreateUserResult = { type: 'Created'; user: User } | { type: 'AlreadyCreated' } | { type: 'Invalid'; error: DomainError };

export class CreateUser {                               // application: pure
  constructor(private readonly users: UsersRepository, private readonly clock: Clock) {}

  async execute(input: { email: string; password: string }): Promise<CreateUserResult> {
    if (await this.users.findByEmail(input.email)) return { type: 'AlreadyCreated' };
    const userOrError = User.create({ ...input, createdAt: this.clock.now() });
    if (userOrError instanceof DomainError) return { type: 'Invalid', error: userOrError };
    await this.users.save(userOrError);
    return { type: 'Created', user: userOrError };
  }
}

export const usersRouter = (app: ApplicationAPI) =>     // infrastructure: parse → delegate → map
  Router().post('/users', async (req, res) => {
    const result = await app.users.createUser({ email: req.body.email, password: req.body.password });
    if (result.type === 'AlreadyCreated') return res.status(409).json({ error: 'User already exists' });
    if (result.type === 'Invalid') return res.status(400).json({ error: result.error.getMessage() });
    return res.status(201).json(result.user.toDTO());
  });
```

Payoff: the rule is tested in milliseconds with a fake.
```ts
it('knows a user whose email is already taken is not created again', async () => {
  const users = new InMemoryUsersRepository();
  await users.save(existingUser);

  const result = await new CreateUser(users, new FixedClock(NOW)).execute({ email: existingUser.email, password: 'Other-456' });

  expect(result.type).toBe('AlreadyCreated');
});
```
Keep `InMemoryUsersRepository` honest with a contract test (`test-doubles-and-contracts`).
