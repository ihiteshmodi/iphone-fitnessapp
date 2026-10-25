# Pipeline and Skeleton Examples

Load when writing the CI workflow or the first E2E test. GitHub Actions + Node shown; translate to your CI and language.

## Minimal three-phase pipeline
```yaml
# .github/workflows/pipeline.yml
name: pipeline
on:
  push:
    branches: [main]
  pull_request:

jobs:
  commit-phase:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm run lint
      - run: npm run build
      - run: npm run test:unit          # high-value unit + use-case tests: no DB, no web server

  acceptance-phase:
    needs: commit-phase
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: docker compose up -d --build --wait   # production-like environment
      - run: npm run test:e2e
        env:
          APP_URL: http://localhost:3000
      - run: docker compose down

  deploy:
    if: github.ref == 'refs/heads/main'
    needs: acceptance-phase
    runs-on: ubuntu-latest
    environment: production            # configure required reviewers for a manual gate
    steps:
      - uses: actions/checkout@v4
      - run: ./scripts/deploy.sh production
```

## Skeleton E2E test (result verification only)
```ts
// tests/users/registration/registration.e2e.spec.ts
const APP_URL = process.env.APP_URL ?? 'http://localhost:3000';

describe('walking skeleton: registration', () => {
  it('registers a user through the deployed API and reads it back', async () => {
    const email = `skeleton+${Date.now()}@example.com`;

    const created = await fetch(`${APP_URL}/users`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'S3cure-pass!' }),
    });
    expect(created.status).toBe(201);

    const fetched = await fetch(`${APP_URL}/users?email=${encodeURIComponent(email)}`);
    expect((await fetched.json()).email).toBe(email);
  });
});
```
As the suite grows, move HTTP details into a protocol driver so the spec reads like the scenario (4-layer acceptance tests in `test-strategy`).

## Skeleton vs components-first
| | Components first | Skeleton first |
|---|---|---|
| What you do | Weeks of UI components and core logic, no DB/server; deploy at the end | Thinnest slice across everything, deployed first; snag after snag |
| Outcome | Unknown deploy time; infrastructure surprises land last | Something deployed (even if crude) early; real constraints known |

## Scripts the skeleton should leave behind
- `dev` (run locally), `test:unit` (fast, commit phase), `test:e2e` (acceptance phase, needs `APP_URL`), `build`, `lint`.
- Don't name the target-URL variable `BASE_URL` in Vite/Vitest projects: Vite sets `process.env.BASE_URL` itself (to `/`).
- `docker compose up` (or equivalent) starts DB + app in a production-like way.
- README sections: how to run, how to test, how to deploy.
