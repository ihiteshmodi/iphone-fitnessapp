# Composition Root and Application Interface (TypeScript illustration)

Load when wiring dependencies, adding an environment, or adding a delivery mechanism (REST, GraphQL, CLI, worker).

## Before: environment checks and hidden wiring
```ts
class UserService {
  async createUser(dto: CreateUserDTO) {
    const db = process.env.NODE_ENV === 'production' ? prodDb : devDb;   // env check inside a service
    const mailer = new SmtpMailer();                                      // inline new: not swappable
    // ...
  }
}
```

## After: one root, Russian dolls
```ts
// main / composition-root: the only file that knows which environment it is
type Env = 'test' | 'development' | 'staging' | 'production';

export interface ApplicationAPI {              // "everything your app can do", pure
  users: { createUser: CreateUser['execute'] };
  orders: { placeOrder: PlaceOrder['execute'] };
}

export async function compose(env: Env) {
  const db = env === 'test' ? null : await DbConnection.create(config[env]);   // once, at bootstrap

  const users: UsersRepository = db ? new SqlUsersRepository(db) : new InMemoryUsersRepository();
  const orders: OrdersRepository = db ? new SqlOrdersRepository(db) : new InMemoryOrdersRepository();
  const payments: PaymentService = env === 'production' ? new StripePaymentService(config.production.stripeKey) : new FakePaymentService();
  const clock: Clock = new SystemClock();
  const bus: EventBus = new InProcessEventBus();

  const createUser = new CreateUser(users, clock);
  const placeOrder = new PlaceOrder(orders, bus, clock);

  const app: ApplicationAPI = {
    users: { createUser: (input) => createUser.execute(input) },
    orders: { placeOrder: (input) => placeOrder.execute(input) },
  };
  registerBillingHandlers(bus, payments);         // subscriptions are wired here too

  return { app, server: createWebServer(app) };   // the web server *uses* the app
}
```

Graph:
```
compose(env)
  → web server (delivery)
    → ApplicationAPI
      → CreateUser use case
        → UsersRepository role
            production → SqlUsersRepository
            test       → InMemoryUsersRepository
```

## Incoming-adapter test with a fake app (level 6)
```ts
test('POST /users calls app.users.createUser with the extracted input', async () => {
  const createUser = vi.fn().mockResolvedValue({ type: 'Created', user: someUser });
  const fakeApp = { users: { createUser }, orders: { placeOrder: vi.fn() } } as ApplicationAPI;

  const server = createWebServer(fakeApp);        // routes only, no infrastructure
  await request(server).post('/users').send({ email: 'a@b.com', password: 'pw' });

  expect(createUser).toHaveBeenCalledWith({ email: 'a@b.com', password: 'pw' });
});
```
A library mock is fine here: the fake app is a trivial stub whose behavior doesn't matter beyond the call.

## Where composition pays off
- Tests swap actors at the application, system and incoming-adapter guess points.
- The same app runs in test, CI, staging, production; the pipeline depends on it.
- Reproducible dev infra (containers instead of a local DB).
- Plugin-style extension: new actors for existing roles without touching use cases.

## Rules
- Respect directionality: outer layers depend on inner ones.
- Trace the graph all the way up to the server; you should be able to read it in one file.
- One DB connection object created at bootstrap and injected into thin repositories; not per-request `Repository.build()`.
- Startup and shutdown live here too: open long-lived resources (connections, clients, workers, refresh loops) once, in dependency order; close them in reverse order; stop startup if required config or a critical dependency fails. Expose liveness and readiness from what this file built (`observability-and-config`).
- Switch to a DI container only when this file is genuinely messy.
