---
name: event-driven-decoupling
description: 'Temporal decoupling with domain events and handlers. Use when a requirement says after, when, then also, only when, before, notify, send email, retry, or when a command appends several awaited side effects. Ends each slice at its own state change and models success then failure with compensating events.'
---

# Event-Driven Decoupling (Temporal Decoupling)

Standing rule: **"The reality is that requirements are temporal."** When a slice completes it publishes an event for its own state change; handlers start the *next* slices. Never append follow-up work as a chain of awaited calls inside the command.

## When to use
- Requirement words: *after*, *when*, *then also*, *only when*, *if already*, *before*, *notify*, *send an email*, *retry*, *later*, *every day*.
- A command calls billing + email + inventory + analytics in sequence.
- An aggregate boundary is hard to find ("if you can't find the boundary, you're probably doing too much in one command").
- Designing module-to-module communication.

## Procedure
1. **Hear the time words.** Each one is a policy: "when X happens, do Y".
2. **End the slice at its own state change.** The Gherkin Then for the command is about that change ("an order should have been placed"), not every downstream effect.
3. **Name the event** in past tense, owned by the slice's context (`OrderPlaced`, `UserRegistered`, `InviteAccepted`). Payload: IDs and the facts handlers need, not whole aggregates.
4. **Publish, then react.** A coordinator (event bus) takes events and lets subscribers know. Each subscription calls a separate use case (a new vertical slice, possibly in another module). Subscriptions are wired in the composition root; controllers/use cases never subscribe themselves.
5. **Keep flow one-directional**: command → state change → event → bus → handler → next command.
6. **Model success first, then failure.** For each handler ask "what if this fails?" and design **compensating events** (charge fails → `CustomerChargeFailed` → notify, retry in 2 days, cancel and release inventory after 3).
7. **One state change per step, per context.** If a step must change several things atomically, that is one aggregate/transaction; otherwise split by events.
8. **Make handlers idempotent** (safe to run twice) and plan delivery: an in-process bus loses events on crash; production may need persistence / an outbox. Decide in `architecture-decisions`.
9. **Test at the right level** (`test-strategy`): the command's use-case test asserts the event was published (communication); each handler gets its own use-case test; widen the subject to include the bus only when verifying the whole chain.

## TypeScript illustration (translate idiomatically)
Before (one request awaits everything; one failure strands the rest):
```ts
export async function placeOrder(cmd: PlaceOrderCommand) {
  const order = await orders.save(Order.place(cmd));
  await billing.charge(order.customerId, order.total);   // slow third-party call
  await email.sendConfirmation(order);                   // if this throws...
  await inventory.decrement(order.items);                // ...stock is never updated
  await analytics.track('order_placed', order);
  return order;                                          // the user waited for all of it
}
```
After (slice ends at OrderPlaced; handlers start new slices):
```ts
export class PlaceOrder {
  constructor(private orders: OrdersRepository, private bus: EventBus) {}
  async execute(cmd: PlaceOrderCommand) {
    const order = Order.place(cmd);
    await this.orders.save(order);
    await this.bus.publish({ type: 'OrderPlaced', orderId: order.id, customerId: order.customerId, total: order.total });
    return order;
  }
}

// composition root: subscriptions
bus.subscribe('OrderPlaced', async (e) => {
  const charge = await chargeCustomer.execute({ customerId: e.customerId, amount: e.total });
  if (!charge.ok) await bus.publish({ type: 'CustomerChargeFailed', orderId: e.orderId, customerId: e.customerId, reason: charge.reason });
});
bus.subscribe('OrderPlaced', (e) => reserveInventory.execute({ orderId: e.orderId }));
bus.subscribe('OrderPlaced', (e) => sendOrderConfirmation.execute({ orderId: e.orderId }));
bus.subscribe('CustomerChargeFailed', async (e) => {
  await notifyCustomer.execute({ customerId: e.customerId, template: 'payment-failed' });
  await scheduleChargeRetry.execute({ orderId: e.orderId, after: { days: 2 } });
});
```

## Outputs
- Event list per feature in `docs/design/<feature>/event-storm.md` (event, producer context, consumers, compensations).
- Event types, handlers (one use case each), subscriptions in the composition root, tests per handler.

## Anti-patterns to refuse
- Continually appending functionality after the core action ("after job posted" helpers with sequential awaits).
- Mail/notification services as direct dependencies of core commands like `CreateUser`.
- Transaction scripts across subdomains (`makePurchase`: bill, update stock, email in one call).
- Asserting downstream side effects (emails) in the E2E test instead of with a spy at level 3.
- Handlers that are not safe to re-run.

## AI guardrails
Generated code appends side effects as sequential awaits by default and rarely handles the failure path. Spotting "after / when / if" requirements and asking for an event, its handlers and a compensating event is a human design decision; state it explicitly in the prompt.

Sources: essentials-physical--temporal-decoupling, ddd-feedbook--aggregates, architecture--monolith-vs-microservices
