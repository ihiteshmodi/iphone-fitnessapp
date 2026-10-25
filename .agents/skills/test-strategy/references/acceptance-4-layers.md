# 4-Layer Acceptance Tests (TypeScript illustration)

Load when writing an E2E acceptance test (level 5).

A concrete example (Given/When/Then) put straight into the codebase: a **shared executable specification** that can drive the backend or the frontend. It is where work crosses from *what* to *how*.

| Layer | Name | Content | Owned by |
|---|---|---|---|
| 1 | Acceptance criteria | `.feature` file: Given/When/Then in the user's language | Product / user (approved by a human) |
| 2 | Test runner | Binds scenarios to test code (a Gherkin binding for your runner) | Test infrastructure |
| 3 | Test code / DSL | Step bodies that read like the scenario: `shop.aCustomer('James')`, `shop.purchase(james)`. No HTTP, no selectors | Developers |
| 4 | Protocol driver | "Acts as the user": API client for the backend, page object for the frontend. Swappable per channel | Developers, per platform |

UI or API changes stay in layer 4; the spec doesn't change. **One acceptance test per feature, shared by frontend, backend, mobile, desktop**; never rewritten per environment.

## Layer 1
```gherkin
Feature: Buy tickets
  Scenario: James buys three tickets for his company
    Given James has three tickets in his cart
    When James purchases the tickets
    Then an order should have been placed
```

## Layers 2–3 (Gherkin binding; shown with a vitest-cucumber style API)
```ts
describeFeature(feature, ({ Scenario }) => {
  Scenario('James buys three tickets for his company', ({ Given, When, Then }) => {
    let james: Customer;
    Given('James has three tickets in his cart', async () => {
      james = await shop.aCustomer('James').withTicketsInCart(3);
    });
    When('James purchases the tickets', async () => {
      await shop.purchase(james);
    });
    Then('an order should have been placed', async () => {
      expect(await shop.ordersFor(james)).toHaveLength(1);
    });
  });
});
```
No Gherkin binding available? Keep the `.feature` file as the spec and write a plain `describe`/`it` whose steps call the same DSL, one `it` per scenario.

## Layer 4: protocol driver
```ts
interface ShopDriver {
  aCustomer(name: string): CustomerBuilder;
  purchase(customer: Customer): Promise<void>;
  ordersFor(customer: Customer): Promise<OrderDTO[]>;
}

class ShopApiDriver implements ShopDriver {
  constructor(private baseUrl: string) {}
  async purchase(customer: Customer) {
    const res = await fetch(`${this.baseUrl}/orders`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ customerId: customer.id }),
    });
    if (res.status !== 201) throw new Error(`purchase failed: ${res.status}`);
  }
  // ...
}
// Frontend: a ShopPageDriver implements the same interface with a browser automation page object.
```

## Rules
- Then-clauses: past tense for things that happened ("placed", "sent"), present for UI state. Describe how the user interacts.
- Result verification only. "I should get an email" is verified at level 3 with a spy; the frontend might only assert the "check your email" page.
- Idempotent: tests can run over and over against the same environment (unique data per run, reset or isolated fixtures).
- Existing code: start with a characterization test that pins current input → output end to end, then move in a layer.
- Reusable page objects / drivers pay off: new features become "mix a couple of drivers together."
