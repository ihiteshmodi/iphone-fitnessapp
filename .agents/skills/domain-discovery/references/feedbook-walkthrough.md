# FeedBook Walkthrough (course case study)

Load when running `domain-discovery` for the first time in a session, as a model of the expected artifacts.

Product: authors invite pre-readers to read a book draft and give feedback.

## 1. Subdomains (raw brain-dump)
Notion integration · book/text parsing · pre-readers / pre-reading · feedback cycles · invitations · users & identity · sign-up · scheduler / scheduled jobs · payments · credit card management · pre-reading sessions · browser sessions · emails · book feedback · emoji management · versioning.

## 2. Bounded contexts, classification, build/buy
| Subdomain(s) | Bounded context | Type | Build / buy |
|---|---|---|---|
| Pre-reading, invitations, feedback cycles, pre-readers, authors | FeedBook | Core | Build (our codebase) |
| Browser + pre-reading sessions | Sessions | Supporting | Build (no plug-and-play) |
| Notion integration + book parsing | Importing | Supporting | Own code + Notion API |
| Payments + credit cards | Billing | Generic | Buy (Stripe) |
| Scheduled jobs | Scheduling | Generic | Buy / library |
| Pre-reading data | Analytics | Generic | Buy (e.g. Mixpanel) |
| Emails, users & identity | External | Generic | Buy (mail provider, auth) |
| Book feedback + emoji | Feedback | to decide | to decide |

Folder consequence: `src/modules/feedbook/` (core), `src/modules/sessions/` (supporting), `src/modules/billing/` (thin wrapper around the provider), `src/shared/`.

Folder tips from the course:
- Package by domain: one folder per bounded context. Get team buy-in before changing conventions.
- Tech-first conventions (framework-style folders) can serve a tiny app early; switch to domain folders once there are several capabilities.
- Architecture rules can be enforced as tests (e.g. an arch-test library: value objects and entities may not import web controllers).
- Design it twice: revisiting the upfront design later often yields a different, better split.

## 3. Concrete scenario
```gherkin
Feature: Invite pre-readers
  Scenario: Inviting pre-readers to the platform
    Given I'm an author
      And I'm already on the platform
      And I already have my book uploaded
      And I haven't invited any pre-readers yet
    When I invite the following pre-readers in bulk: james@gmail.com, bill@email.com, sally@email.com
    Then they should get sent an email inviting them to be pre-readers
    When Sally accepts the invite
    Then I should get an email saying it was accepted
      And Sally should be a valid pre-reader
      And there should be unaccepted invites for James and Bill
```

## 4. First event storm (contains the smell)
| # | Command | Actor | Data | Event | Context |
|---|---|---|---|---|---|
| 1 | Create pre-reader invites | Author | Pre-reader invite | Pre-reader invite created | FeedBook |
| 2 | Send email | System | Email | Email sent | Email |
| 3 | Accept pre-reader invite | Pre-reader | Pre-reader invite | Pre-reader invite accepted | FeedBook |
| 4 | Create pre-reader account | System | Pre-reader account | Pre-reader account created | FeedBook ← SMELL |
| 5 | Send email to author | System | Email | Email sent | Email |

Smell: rows 3 → 4 are two events in the same context changing the same concept in one process.

Redesign: a pre-reader starts out **Invited** and transitions to **Accepted**. Domain rule: "In order to create a pre-reader, they start out invited." The extra "create account" step disappears.

## 5. Refined with views and data
| View | Actor | Command | Input data | Event | Context |
|---|---|---|---|---|---|
| Invite form | Author | Invite pre-readers | many × authorId, email | Pre-readers invited (carries preReaderInviteId) | FeedBook |
| — | System | Send email(s) | invite details; preReaderInviteId in link | Email(s) sent | Email |
| Email → accept page | Invitee | Accept pre-reader invite | preReaderInviteId | Pre-reader invite accepted | FeedBook |
| — | System | Send email | — | Email sent | Email |
| Register page | Invitee | Create user account | first, last, password (email known) | User account created | Users & Identity |
| — | System | Create pre-reader | valid invite + user account | Pre-reader created | FeedBook |
| Dashboard | — | (none) | — | (no state change) | — |

The views surfaced questions nobody had asked: how does an invited reader log in, do they choose a password, is a username needed? Those went back to the domain expert.

## 6. State pieces handed to state-machines-invariants
| Piece | Owned by | Transition |
|---|---|---|
| Pre-reader invite | FeedBook | Invited → Accepted via accept |
| Pre-reader | FeedBook | complexity is in creation (needs valid invite + user) |
| User | Users & Identity | must exist before a pre-reader |
| Email | External (generic) | created by handlers in many places |

Order matters: author → invite → user → pre-reader. Application rules (e.g. "only the inviting author may see this") are not domain invariants; keep them in the application layer.
