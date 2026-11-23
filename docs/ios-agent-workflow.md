# How we build iOS apps with an agent

The working method used on this app. Give it to any agent building an iOS app for Hitesh so it follows the same
process. It has two parts: agree on everything first, then build it test-first with small commits and check the screens
on the simulator at the end.

## 0. Ground rules

- **Device:** iPhone 15 Pro Max only. Simulator tests and screenshots run on that device only. The app is installed on
  the phone as an unsigned `.ipa` through LiveContainer.
- **Git:** it is a personal repo, so commit straight to `main` and push after every green step. Every commit must be on
  GitHub. No branches or pull requests unless asked. Never rewrite history.
- **Private data never goes to GitHub:** personal databases, health data, paid course content and private agent skills
  stay git-ignored (e.g. `output/*` with `!` exceptions only for files the owner approves). Check `git check-ignore`
  before adding a new data file.
- **Talk plainly:** short updates, plain words, no jargon. When unsure, ask instead of guessing.

## 1. Gather requirements before any code

1. The owner lists features in the chat, often by voice and across several messages. Collect them all first.
2. Restate each feature as who / why / what, with a concrete example ("Given …, when …, then …").
3. Ask about anything unclear. Ask in small batches (3–5 questions), most important first.
4. Get an explicit **approval** of the full list before building anything. A new requirement mid-build is clarified on
   its own (only the change), approved, and then building resumes.

### Chat questions or a Lavish page?

| Use the chat (`ask_user` form) | Use a Lavish page (`npx -y lavish-axi`) |
|---|---|
| 1–5 quick decisions, yes/no, pick one | A full plan for approval (many features, each with examples) |
| A clarification during the build | Long lists to review one by one (e.g. hundreds of rule conflicts) |
| Anything answerable in under a minute | Anything visual (layouts, tables, before/after) |
| Confirming a single default | Decisions the owner wants to comment on line by line |

Lavish notes:
- Write the plan as one HTML page with numbered items and a decision ID per choice (D1, D2, …), so the owner's comments
  can refer to them.
- The owner's comments reach the agent only after they press **Send to Agent**. Queued comments live in the browser tab
  until then and are lost if the tab closes. Read them with `npx -y lavish-axi poll`.
- Version the page (plan v1 → v2 → v3), apply the comments, and ask for final approval on the last version.
- Save every plan and feedback file in the session folder, not the repo.

If the owner says "you decide", decide with clear rules, mark each decision high / medium / low confidence, and bring
only the low ones back (or to his research agent) with a short brief.

## 2. Build one feature at a time, test-first

For each approved feature:

1. **Spec:** a `.feature` file in `tests/<area>/<feature>/` with the approved scenarios (one success case and the
   failure cases, with real values).
2. **Failing test:** XCTest cases written from the scenarios. Run them and see them **fail for the right reason**
   (missing type or wrong value, not a typo).
3. **Code:** the smallest change that makes them pass. Domain logic lives in the Swift package (no SwiftUI there) so it
   can be tested with `swift test` without a simulator.
4. **Green:** run the whole `swift test` suite (fast, a few seconds) and the app build (`xcodebuild … build` for the
   simulator) to catch UI compile errors.
5. **Commit and push** to `main` with a short message: `feat:` for new behaviour, `fix:` for bug fixes, `refactor:`
   for restructuring, and a plain message for docs, tests or tooling. Keep a refactor in its own commit.
6. Update the README section for that feature in the same commit or the next one.

Extra rules:
- When a test is written after the code (e.g. a guard), break the code once on purpose to see the test fail, then
  restore it.
- Never weaken an approved scenario to make a test pass; ask instead.
- If the same failure survives two different fixes, stop, explain, and ask.
- Schema changes: bump the version, add a migration, and test that the owner's real database migrates.

## 3. Screens: screenshots first, then simulator tests

The UI is checked at the **end** of a phase, once all features are built (the simulator is slow, so it is not run per
feature):

1. **Screenshot tour:** a UI test class (e.g. `PhaseXTourUITests`) that walks every new or changed screen and takes
   screenshots, asserting almost nothing. Split it into short tests (under 3 minutes each), each opening its own screen.
   Run it on a copy of the owner's real data so the screens show real-length text.
2. **Screenshot review in Lavish (by the owner, not the agent):** put all exported simulator screenshots into a Lavish
   gallery page (`npx -y lavish-axi`, saved in the session folder with relative image paths) and wait on
   `npx -y lavish-axi poll`. **Never inspect or review screenshots yourself** — wait for the owner to mark or name the
   specific screenshots that need changes, inspect and fix **only** those marked screenshots, and rerun if needed.
3. **Acceptance UI tests:** one or two real tests per phase (tap through the main flow and assert the result) on the
   test fixture database.
4. **Full simulator suite:** run every class at the end, fix failures (including old tests that expected text the phase
   changed on purpose), then commit.

### The UI test runner (`scripts/run-ui-tests.sh`)

Every app gets a runner script like this one:
- **One class at a time**, at low CPU priority (`nice`), with per-test (90 s, max 180 s) and per-class time limits.
- **Progress:** each finished test prints `✓ [12/55] testName (23s)` or `✗ [...]`. In a terminal the bottom line
  redraws every 2 s with a bar, the running test and the time; when an agent captures the output it gets one plain line
  a minute instead. `.uitest-logs/progress.txt` always holds the latest line.
- A test that runs past its time limit counts as failed, and a minute of silence prints a warning.
- After the last test it waits for the result bundle (where the screenshots are) before stopping `xcodebuild`, which
  can hang on exit.
- **Cleanup on every exit, including Ctrl-C:** shut down all simulators, quit the Simulator app, and stop leftover
  `xcodebuild`, Xcode build services and test daemons. Without this the Mac stays slow after the run, because these
  keep gigabytes of memory.
- Never boot a simulator by hand for a quick screenshot without shutting it down afterwards (`xcrun simctl shutdown
  all`).
- Export screenshots with `xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path …` into the
  session folder next to the Lavish HTML gallery (using relative image paths), and keep `.shots/` and `.uitest-logs/`
  git-ignored. Only view or shrink (`sips -Z 700`) screenshots that the owner specifically marks in Lavish.

## 4. Review and report

1. Before committing, review against the checklist: comments explain why (not what), tests come from scenarios, no
   logic in views that belongs in the package, no premature abstractions, and no secrets or personal data in the diff.
2. **Final report** to the owner in plain language: what is in the app now, findings from his own data, decisions made
   along the way (with anything labelled as research or assumption), what was skipped and why, and what is still open.

## 5. Ship to the phone

1. Make sure `output/` has the owner's latest database (check that it has today's entries).
2. Build the Release `.ipa`. The build bundles the database and data files from `output/`. Then list the `.ipa`
   contents and confirm each bundled file is there.
3. Tell the owner: install in LiveContainer, tap **Load my data** on first launch, plus any one-time "apply" buttons.
   Warn him to export first if the phone has newer data.
4. Keep `output/` tidy: the current database, the test fixture, the bundled data files and the latest `.ipa`. Move old
   backups to the Trash instead of deleting them.

## Related guides

- [export-share-sheet-pattern.md](export-share-sheet-pattern.md): how the database export opens the iOS share sheet
  directly (AirDrop, Google Drive, Files) instead of going through the Files picker first.
