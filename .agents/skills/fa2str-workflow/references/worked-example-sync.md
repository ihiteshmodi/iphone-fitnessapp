# Worked Example: Outer + Inner Loop for a Sync Feature (TypeScript illustration)

Load the first time you run the per-feature steps in a session.

Feature: Notion tasks sync to Google Calendar.

## Find (feature level)
Who: a business owner working from Notion. Why: stop double-entering tasks. Capabilities: sync dated tasks to the calendar without duplicates.

## Architect
- Components: `SyncTasks` use case, `TaskSource` gateway (Notion), `CalendarGateway` (Google), `SyncLinks` store (task id → event id), scheduled trigger.
- Testing strategy: one E2E acceptance test against a test workspace + test calendar (outer loop); use-case tests with in-memory fakes and a calendar spy (inner loop); contract tests over fake and real gateways (level 4).

## Automate
Unit/use-case tests run in the commit phase; the E2E test runs in the acceptance phase against staging.

## Outer loop (level 5): acceptance criteria → executable spec
```gherkin
Feature: Sync Notion tasks to Google Calendar
  Scenario: A dated task appears on my calendar
    Given I have a Notion task "Write newsletter" on 2026-10-01 at 09:00
    When the sync runs
    Then my Google Calendar shows "Write newsletter" from 09:00 to 09:30 on 2026-10-01
```
```ts
// tests/e2e/syncTasks.e2e.ts — result verification only; drivers hide Notion/Google/HTTP details
describe('Sync Notion tasks to Google Calendar', () => {
  const notion = new NotionTestDriver(process.env.NOTION_TEST_WORKSPACE!);
  const calendar = new CalendarTestDriver(process.env.GCAL_TEST_CALENDAR!);
  const app = new SyncAppDriver(process.env.APP_URL!);

  beforeEach(async () => { await notion.reset(); await calendar.reset(); });

  it('a dated task appears on my calendar', async () => {
    await notion.createTask({ title: 'Write newsletter', date: '2026-10-01', time: '09:00' });
    await app.triggerSync();
    const events = await calendar.eventsOn('2026-10-01');
    expect(events).toContainEqual(expect.objectContaining({
      summary: 'Write newsletter', start: '2026-10-01T09:00', end: '2026-10-01T09:30',
    }));
  });
});
```

## Inner loop (level 3): use-case tests, no network, milliseconds
```ts
describe('SyncTasks', () => {
  const dated = { id: 't1', title: 'Write newsletter', date: '2026-10-01', time: '09:00' };

  it('creates a calendar event for a new dated task', async () => {
    const calendar = new CalendarSpy();
    const links = new InMemorySyncLinks();
    const syncTasks = new SyncTasks(new InMemoryTaskSource([dated]), calendar, links);

    const result = await syncTasks.execute();

    expect(result).toEqual({ created: 1, skipped: 0 });       // result
    expect(calendar.createdEvents()).toHaveLength(1);         // communication
    expect(await links.eventIdFor('t1')).toBeDefined();       // state
  });

  it('does not duplicate a task that was already synced', async () => {
    const calendar = new CalendarSpy();
    const links = new InMemorySyncLinks({ t1: 'evt_42' });    // indirect input
    const syncTasks = new SyncTasks(new InMemoryTaskSource([dated]), calendar, links);

    const result = await syncTasks.execute();

    expect(result).toEqual({ created: 0, skipped: 1 });
    expect(calendar.createdEvents()).toHaveLength(0);
  });
});
```

## The use case that made them pass
```ts
export class SyncTasks {
  constructor(
    private readonly tasks: TaskSource,
    private readonly calendar: CalendarGateway,
    private readonly links: SyncLinks,
  ) {}

  async execute(): Promise<{ created: number; skipped: number }> {
    let created = 0;
    let skipped = 0;
    for (const task of await this.tasks.listChangedTasks()) {
      const decision = toCalendarEvent(task);           // needed a new construct → FA²STR one level down
      if (decision.kind === 'skip' || (await this.links.eventIdFor(task.id))) { skipped++; continue; }
      const eventId = await this.calendar.createEvent(decision.event);
      await this.links.link(task.id, eventId);
      created++;
    }
    return { created, skipped };
  }
}
```

## n loops: drilling into level 1
`toCalendarEvent` is a pure function, so run FA²STR at the stateless guess point:
| Knowing | Input | Expected |
|---|---|---|
| Undated tasks are not synced | `{ title: 'Someday idea' }` | `skip / no-date` |
| Archived tasks are not synced | `{ …, archived: true }` | `skip / archived` |
| Date-only tasks become all-day events | `{ title: 'Pay invoices', date: '2026-10-02' }` | `allDay: true` |
| Timed tasks default to 30 minutes | `{ …, time: '09:00' }` | `09:00 → 09:30` |
| A duration is respected, even past midnight (most complex) | `{ …, time: '23:30', durationMinutes: 90 }` | `23:30 → 01:00 next day` |

Red → fake it → green → commit, one row at a time; parameterize the two skip rows once their shape repeats; refactor the repeated date maths on the third occurrence. Then return to the use-case test.

`CalendarSpy` and the in-memory fakes need contract tests against the real gateways (level 4) to stay honest — see `test-doubles-and-contracts`.
