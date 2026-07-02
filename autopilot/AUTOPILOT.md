# AUTOPILOT brief — Replog

You are running unattended, with no human present. You will not be asked to
confirm anything and you must never wait for a yes/no. Decide, act, verify,
checkpoint, record, and exit. Another instance of you will start the next
iteration. Treat this file as your standing orders for a SINGLE iteration.

## 0. First, load your state (in this order)
1. `autopilot/PROGRESS.md`  — what previous iterations did and what is next.
2. `autopilot/BACKLOG.md`   — the prioritized task list (source of truth for scope).
3. `CLAUDE.md` and `ARCHITECTURE.md` — the project's conventions and layering.
If `PROGRESS.md` or `BACKLOG.md` do not exist, create them (see section 6/7).

## 1. The mission (north star, NOT this iteration's task)
Evolve Replog from "AI only at onboarding" into a genuine on-device AI personal
trainer: it analyses logged history over time and adapts the plan (reps, load,
exercise choice, whole split); periodically checks bodyweight and tracks it;
gives goal-specific coaching (muscle gain, fat loss, running, cycling, sport);
remembers coaching context and keeps past reports readable; publishes weekly and
monthly reports; and nudges the user with notifications. Precision comes from
feeding real USER data into the planner and from deterministic domain math, not
from a bigger model. Build toward this ONE backlog item at a time.

## 2. Absolute rules (never violate)
- **One item per iteration.** Pick the single highest-priority READY item in
  `BACKLOG.md` that fits in one iteration. Do not start a second item.
- **Decide, never ask.** If a choice is ambiguous, pick the most REVERSIBLE
  option, write the assumption in `PROGRESS.md`, and proceed.
- **Green gate.** Before an item counts as done, the build must be clean
  (0 errors, 0 warnings) and the test suite must pass on iPhone 17. If you
  cannot get green within this iteration, revert your changes so the tree stays
  green (`git restore .` / `git reset --hard HEAD`), record why in `PROGRESS.md`,
  and choose a different item.
- **Checkpoint, never onto development.** When green, `git add -A` and commit to
  the CURRENT autopilot branch only. Never commit or merge to `development` or
  `main`. This checkpoint is the rollback mechanism; it does not violate the
  owner's "no commits to development" rule.
- **Stay inside the repo.** Never delete or modify anything outside the repo
  working tree. Never run `rm -rf` on anything except build artifacts under the
  project's DerivedData. The external data dirs one level up (`../free-exercise-db-main`,
  `../README.md`, `../design_handoff_replog/`) are READ ONLY.
- **Follow the house style.** MVVM-where-it-earns-it, SwiftData `@Query` stays in
  Views, writes go through `Domain` services, reuse `DesignSystem` + `Catalog`
  components, keep the logic layer >=80% covered with meaningful Swift Testing
  tests. Obey the 4-pass method below.

## 3. The 4-pass method (apply to the chosen item)
1. **Engineer** — implement to senior-iOS standard: clean architecture,
   idiomatic SwiftUI/SwiftData, matching surrounding conventions and DesignSystem
   tokens.
2. **Reviewer** — re-read your own diff as a second engineer: correctness, edge
   cases, retain cycles, `@MainActor` isolation, SwiftData relationship/save
   correctness, naming, dead code.
3. **QA** — add/update meaningful unit tests, build clean, run the suite, and do
   the visual check in section 4 for anything user-facing.
4. **PM** — confirm the backlog item's acceptance criteria are fully met before
   you checkpoint.

## 4. Verification you CAN do (and its limits)
Build and test:
```
xcodebuild -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild test -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES -only-testing:ReplogTests
```
Visual check (layout only): boot an iPhone 17 sim, install, then
`SIMCTL_CHILD_REPLOG_SEED=1 SIMCTL_CHILD_REPLOG_TAB=<tab> xcrun simctl launch <sim> test.Replog`,
capture with `xcrun simctl io <sim> screenshot`, and view the PNG. Report layout
bugs, clipping, and obvious breakage.
**You cannot judge animation smoothness, gesture feel, or haptics from a
screenshot. Do not pretend to.** List anything that needs a human eye under a
"NEEDS HUMAN REVIEW" heading in `PROGRESS.md` instead of guessing.

## 5. Assessing the AI planner (do this, not vibes)
Build/extend an eval harness in `ReplogTests/` (or `Domain/AI/`): define synthetic
user personas (goal, equipment, injuries, and a fabricated `HistoryEntry` trail),
run the planner, and assert PROPERTIES, e.g.:
- a machine-only user never receives a bodyweight-only movement;
- prescribed weekly sets per muscle land in the target band for the goal;
- when history shows a lift progressing, the next prescription increases load or
  reps (and backs off when history stalls).
If `FoundationModels` is unavailable in the simulator, the deterministic
`PlanGenerator` fallback is what runs. Test that, and note in `PROGRESS.md` that
the live model path was not exercised so the owner can verify on device.

## 6. Bootstrapping when the backlog is empty (planning-only iteration)
If `BACKLOG.md` has no READY items, DO NOT write code. Decompose the mission into
small, independently verifiable, mostly-reversible items with explicit acceptance
criteria, ordered foundation-first. Flag any item that is irreversible or a
product-judgment call (notification copy/frequency, anything affecting App Store
review, anything that deletes user data) as `HUMAN-REVIEW` and leave it blocked.
Write `BACKLOG.md`, update `PROGRESS.md`, and exit.

## 7. End-of-iteration contract (always do this last)
Append to `autopilot/PROGRESS.md`:
- iteration number, timestamp, model, backlog item worked;
- what changed (files/types), build result, test result + coverage delta;
- screenshots captured and what they showed;
- assumptions you made;
- `NEEDS HUMAN REVIEW:` items;
- the single recommended next item.
Then stop. Do not begin another item.
