# Levels of Realness and Contracts (TypeScript illustration — translate idiomatically)

Load when deciding between interface, abstract class, class or plain data, or reviewing premature abstractions.

| Level | Construct | Use when | Example |
|---|---|---|---|
| Most abstract | Interface / type | A role that more than one actor plays; infrastructure seams | `interface UserRepo` |
| | Abstract class | Partial implementation + abstract members, after the rule of three | framework base component |
| | Class | One implementation with behavior; needs construction | `class TrafficLight` |
| Most real | Plain object / record | Data, props, DTOs | `{ name: 'Khalil' }` |

"I can't get more abstract than a contract and it can't get more real than an actor."

## Vocabulary
- **Role**: a job to be played; abstract until an actor plays it.
- **Actor**: the real thing playing one or many roles.
- **Responsibility**: what a role must do or know.
- **Collaboration**: interactions between roles.
- **Contract**: an actor declaring it plays a role (`implements` / `extends`, or the language's equivalent).

## George Clooney test
Ask: "Who else is going to play this role?" If the answer is only this one concretion, no contract is needed. When a second actor appears, triangulate the contract from both. Pair with YAGNI and the rule of three.

```ts
// Before: premature interface, every reader jumps interface → class
interface ITrafficLight { next(): void; getColor(): Color; }
class TrafficLight implements ITrafficLight { /* ... */ }
const light: ITrafficLight = new TrafficLight();

// After: concrete until a second actor exists
class TrafficLight {
  private color: Color = 'red';
  next() { /* red → green → yellow → red */ }
  getColor() { return this.color; }
}
// Only when ModelTrainTrafficLight appears: extract `interface TrafficLight`.
```

## Where contracts belong (real seams)
```ts
interface UserRepo { save(user: User): Promise<void>; getById(id: string): Promise<User | null>; }

class CreateUser {
  constructor(private userRepo: UserRepo) {}      // depends on the role, not the actor
}

class PostgresUserRepo implements UserRepo { /* ... */ }   // real actor (infrastructure)
class InMemoryUserRepo implements UserRepo { /* ... */ }   // fake actor (tests) → needs a contract test
```

## Same steps, two paradigms
```ts
// Functional script
async function createUser(input: Input) {
  const user = validate(input);
  await saveUser(user);
  await sendWelcomeEmail(user);
}

// Object network
class CreateUser {
  constructor(private users: UserRepo, private mailer: Mailer) {}
  async execute(input: Input) {
    const user = User.create(input);     // rules hidden inside User
    await this.users.save(user);
    await this.mailer.sendWelcome(user); // better: publish UserCreated and let a handler email
  }
}
```
The highest level of abstraction is the high-level steps and events; the paradigm is an implementation choice under it.

## Designing your own abstraction (when no library has it)
```ts
class LoadingState {
  private loading = false;
  start() { this.loading = true; }
  stop() { this.loading = false; }
  isLoading() { return this.loading; }
}

class PostsPresenter {
  constructor(private postsRepo: PostsRepository, private loadingState: LoadingState) {}
  async loadPosts() {
    this.loadingState.start();
    const posts = await this.postsRepo.getPosts();
    this.loadingState.stop();
    return posts;
  }
}
```

## Design quality check (empathy)
"Will someone else understand what this is, how to use it and why I'm using it, and can they do their task with it?" Design is discoverability (how do I do it?) plus understanding (did it work, what happened?).
