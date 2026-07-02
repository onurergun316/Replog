# Replog AI Personal Trainer — BACKLOG

Ordered foundation-first, smallest and most reversible on top. The autopilot works
the top READY item each iteration. `HUMAN-REVIEW` items are blocked until the
owner unblocks them. Edit freely before launching.

Status key: READY · BLOCKED · HUMAN-REVIEW · DONE

---

## Epic A — Foundations (do these first; nothing personalises without them)

- [x] DONE (iter 1, 2026-07-02)  **A1. Pipe real user data into the planner prompt.**
  Build a pure `Domain/AI/AthleteContext` value type that summarises the user for
  the model: goal, equipment, injuries, bodyweight, and a compact digest of recent
  `HistoryEntry` (per-lift e1RM trend, last top set, weekly set volume per muscle).
  Feed it into `AIPlanService`. Budget the serialized context against the 4096-token
  window (use `tokenCount(for:)`); trim to the most recent/relevant.
  *Accept:* context struct is pure and unit-tested; prompt stays under budget with a
  measured margin; a persona with rich history produces a visibly different plan than
  an empty-history persona.

- [x] DONE (iter 2, 2026-07-02)  **A2. Planner eval harness.**
  Personas + property assertions per AUTOPILOT section 5.
  *Accept:* >=6 personas, all properties assert, suite green, documented fallback caveat.
  *Done:* `ReplogTests/PlannerEval.swift` (7 personas + pure `PlannerEvalMetrics`) and
  `ReplogTests/PlannerEvalTests.swift` (14 property tests: equipment never violated,
  machine-only/bodyweight guards, injuries excluded, reps/RPE contract, weekly-set band,
  balanced coverage, progressing/stalling trend signal, in-budget prompt, candidate-list
  equipment). Fallback caveat documented in the file header (deterministic engine runs in
  the sim; live model verified on device; history-signal properties assert the SIGNAL, with
  acting-on-it deferred to B-series).

- [ ] READY  **A3. Coaching memory store.**
  A SwiftData `@Model` `CoachingLog` (date, kind, summary, structured payload) plus
  fetch-or-create helpers in `ReplogStore`. This is the durable context the trainer
  "remembers" across weeks.
  *Accept:* model + relationships + cascade rules tested on the in-memory container.

## Epic B — Adaptive progression (the core "it adjusts over time" value)

- [ ] BLOCKED (needs A1, A3)  **B1. Progression engine (deterministic core).**
  Pure `Domain/ProgressionEngine`: given a lift's history, output a recommendation
  (increase load / increase reps / hold / deload) with a reason. Keep the MATH in
  code, not the model.
  *Accept:* rule table unit-tested across progressing / stalling / regressing histories.

- [ ] BLOCKED (needs B1)  **B2. Apply recommendations to the next session.**
  Surface B1 output when building a session (e.g. suggested next weight/reps on the
  log card) without auto-overwriting user input.
  *Accept:* suggestion visible, dismissible, seeded-launch screenshot captured.

- [ ] BLOCKED (needs A2, B1)  **B3. Plateau + deload detection.**
  Detect stalls across sessions and recommend a deload or exercise swap.
  *Accept:* detection is a pure tested function; recommendation recorded to `CoachingLog`.

## Epic C — Check-ins and tracking

- [ ] BLOCKED (needs A3)  **C1. Bodyweight check-in + history.**
  Prompt periodically for bodyweight, store a time series, show a trend.
  *Accept:* store + trend calc tested; entry UI seeded-launch screenshot captured.

- [ ] BLOCKED (needs A1)  **C2. Goal/sport-specific coaching module.**
  For each goal (muscle gain, fat loss, running, cycling, sport + custom), a small
  strategy that shapes the check-in questions and the advice emphasis.
  *Accept:* one strategy per goal, selected by `UserProfile.goal`, logic unit-tested.

## Epic D — Reports

- [ ] BLOCKED (needs A3, B1)  **D1. Weekly report.**
  Compose a weekly summary (volume, PRs, adherence, one coaching note) from
  `HistoryEntry` + `CoachingLog`; store as markdown, readable in Profile like the
  existing AI Coach reports.
  *Accept:* pure composer tested against fixed fixtures; report renders.

- [ ] BLOCKED (needs D1)  **D2. Monthly report.**
  Same pipeline, monthly rollup + trend commentary.
  *Accept:* composer tested; renders.

## Epic E — Notifications  (product-judgment, defer)

- [ ] HUMAN-REVIEW  **E1. Smart nudges ("come on, you can do it").**
  Local notifications for missed scheduled days / streak risk. Needs owner decisions:
  permission flow, copy/tone, frequency caps, and App Store review implications.
  Leave blocked; the autopilot may draft a proposal in `PROGRESS.md` but writes no code.

---

## Notes for the autopilot
- Prefer additive, reversible changes. New pure types + tests before touching UI.
- Keep each item shippable on its own; if an item is too big for one iteration,
  split it in place (append A1a/A1b) and do the smallest slice.
- Anything that would delete or migrate existing user data is HUMAN-REVIEW by default.
