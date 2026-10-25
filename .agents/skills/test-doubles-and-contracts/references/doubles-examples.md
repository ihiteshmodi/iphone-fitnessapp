# Fakes, Spies and Contract Tests (TypeScript / Vitest illustration)

Load when writing a test double or a contract test.

## Before: library-mock soup
```ts
vi.mock('../services/emailService');
const sendEmail = vi.fn().mockResolvedValue(undefined);
vi.mocked(EmailService).mockImplementation(() => ({ sendEmail }) as unknown as EmailService);

it('sends a welcome email', async () => {
  const createUser = new CreateUser(new InMemoryUserRepo(), new EmailService());
  await createUser.execute(validDetails);
  expect(sendEmail).toHaveBeenCalledTimes(1);
});
// copy-pasted into the next five spec files…
```

## After: hand-written fake implementing the contract
```ts
// modules/notifications/emailService.ts
export interface EmailService {
  sendEmail(to: string, body: string): Promise<void>;
}

// modules/notifications/fakeEmailService.ts
export class FakeEmailService implements EmailService {
  private calls: Record<string, unknown[][]> = {};

  async sendEmail(to: string, body: string): Promise<void> {
    this.record('sendEmail', [to, body]);
  }

  getTimesCalled(method: string): number { return (this.calls[method] ?? []).length; }
  getCallsTo(method: string): unknown[][] { return this.calls[method] ?? []; }

  private record(method: string, args: unknown[]) { (this.calls[method] ??= []).push(args); }
}
```

## Level-3 use-case test: result + communication
```ts
const emailSpy = new FakeEmailService();
const userRepo = new InMemoryUserRepo();
const createUser = new CreateUser(userRepo, emailSpy);

const result = await createUser.execute(validDetails);

expect(result.type).toBe('Created');                       // result
expect(await userRepo.getByEmail(validDetails.email)).not.toBeNull(); // state (indirect output)
expect(emailSpy.getTimesCalled('sendEmail')).toBe(1);      // communication
```
Do not assert the email in the E2E test (no polling a sandbox inbox); that belongs here.

## Contract test: one spec, every implementation
```ts
// modules/users/userRepo.contract.spec.ts
const implementations: Array<[string, () => Promise<UserRepo>]> = [
  ['in-memory', async () => new InMemoryUserRepo()],
  ['sqlite', async () => SqliteUserRepo.create(':memory:')],
];

describe.each(implementations)('UserRepo contract (%s)', (_name, makeRepo) => {
  it('can save a user and find it by email', async () => {
    const repo = await makeRepo();
    await repo.save(aUser({ email: 'james@example.com' }));

    const found = await repo.getByEmail('james@example.com');

    expect(found?.email).toBe('james@example.com');
  });

  it('knows an unknown email returns nothing', async () => {
    const repo = await makeRepo();
    expect(await repo.getByEmail('nobody@example.com')).toBeNull();
  });
});
```

## Decoupling from time
Before:
```ts
class User {
  createdAt: Date;
  constructor() { this.createdAt = new Date(); }   // talks to the system clock → untestable
}
```
After:
```ts
export interface Clock {
  now(): Date;
  tickForward(seconds: number): Promise<void>;
}

export class SystemClock implements Clock {
  now() { return new Date(); }
  async tickForward(seconds: number) { await new Promise((r) => setTimeout(r, seconds * 1000)); }
}

export class FakeClock implements Clock {
  constructor(private current = new Date('2026-01-01T00:00:00Z')) {}
  now() { return new Date(this.current); }
  async tickForward(seconds: number) { this.current = new Date(this.current.getTime() + seconds * 1000); }
}

describe.each([
  ['system', () => new SystemClock()],
  ['fake', () => new FakeClock()],
])('Clock contract (%s)', (_name, makeClock) => {
  it('can tick forward', async () => {
    const clock = makeClock();
    const start = clock.now();
    await clock.tickForward(1);
    expect(clock.now().getTime() - start.getTime()).toBeGreaterThanOrEqual(1000);
  });
});
```
Payoff at level 3:
```ts
it('changes the light after an hour', async () => {
  const clock = new FakeClock();
  const app = new TrafficLightApp(clock);
  app.start();

  await clock.tickForward(60 * 60);              // an hour passes instantly
  app.onTick();

  expect(app.getEvents().map((e) => e.type)).toContain('LightChanged');
});
```
Time is an application concern (level 3): the state machine changes when told; the use case knows *when*.
