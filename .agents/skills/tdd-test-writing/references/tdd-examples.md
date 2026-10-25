# TDD Examples (TypeScript / Vitest illustration — translate idiomatically)

Load the first time you write tests in a session, or when reviewing test names and structure.

## Find at the stateless guess point
```
// Doing: validate password
// Knowing:
//   knows passwords between 5 and 15 characters are valid
//   knows passwords outside 5–15 characters are invalid
//   knows passwords without a digit are invalid
// Starting guess point: stateless (data in, data out) → subject: a function
```
One doing with many knowings is the shape of most tests.

## AAA backwards
Forwards (design fails at the assert):
```ts
it('validates the password', () => {
  const validator = new PasswordValidator();
  validator.setMinLength(5);
  validator.load('abc');
  validator.run();
  expect(validator.isValid).toBe(false);          // ...now what? which error wins?
  expect(validator.lastError).toBe('too short');
});
```
Backwards (the assert designs the API):
```ts
it('returns all errors for an invalid password', () => {
  const password = 'abc';                          // 3. arrange (written last)
  const output = validatePassword(password);       // 2. act (wishful thinking)
  expect(output.result).toBe(false);               // 1. assert (written first)
  expect(output.errors).toContain('TooShort');
  expect(output.errors).toContain('MissingDigit');
});
```

## Red for the right reason
```ts
export function validatePassword(password: string): ValidationResult {
  return { result: true, errors: [] };             // stub exported in the red step
}
```

## Names: before / after
```ts
// before: names describe the how
it('sets result to true and error to null when password is valid', ...);
it('sets result to false and error to too short when password is less than five characters', ...);
// after: names state responsibilities
it('can detect valid passwords', ...);
it('knows that a password shorter than five characters is invalid', ...);
```

## Rule of three → it.each
```ts
describe('password validator', () => {
  describe('knows that a password must be between 5 and 15 characters', () => {
    it.each([
      { password: 'abc', reason: 'TooShort' },
      { password: 'abcd', reason: 'TooShort' },
      { password: 'thisIsWayTooLong1', reason: 'TooLong' },
    ])('rejects "$password" because it is $reason', ({ password, reason }) => {
      const output = validatePassword(password);
      expect(output.result).toBe(false);
      expect(output.errors).toContain(reason);
    });
  });
});
```

## Fake it → generalise (TPP)
```ts
// example 1: 1 → "1"         constant
export const fizzbuzz = (n: number) => '1';
// example 2: 2 → "2"         constant → scalar
export const fizzbuzz = (n: number) => String(n);
// example 3: 3 → "Fizz"      single conditional with early return (no else)
export const fizzbuzz = (n: number) => {
  if (n % 3 === 0) return 'Fizz';
  return String(n);
};
```

## Builders for fixtures
Before (test is mostly setup):
```ts
it('can detect a checkmate', () => {
  const game = new Game();
  game.move(Player.One, piece, position);
  game.move(Player.Two, piece, position);
  // ...20 more moves
  expect(game.getGameState()).toBe('end');
});
```
After (named initial state):
```ts
it('can detect a checkmate', () => {
  const game = GameBuilder.fromCommonGameState(GameStates.scholarsMate).build();
  expect(game.getGameState()).toBe('end');
  expect(game.getReason().type).toBe('checkmate');
});
```
In-memory repository seeded through a builder:
```ts
const users = new UserRepoBuilder().withRandomUsers(10).with(anAuthorWithThreePendingInvites()).build();
```

## Comments: why, not what
```ts
export function isPalindrome(text: string): boolean {
  const normalized = ignoreCaseAndSpaces(text);
  return normalized === reverse(normalized);
}
// Spaces are ignored because the spec treats "Was It A Rat I Saw" as a palindrome.
const ignoreCaseAndSpaces = (text: string) => text.toLowerCase().replace(/ /g, '');
const reverse = (text: string) => [...text].reverse().join('');
```
