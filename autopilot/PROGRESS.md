# Replog Autopilot — PROGRESS

## Iteration 1 — 2026-07-02 ~10:35 — Claude Fable 5 — Item A1

**Item:** A1. Pipe real user data into the planner prompt.

**What changed:**
- NEW `Replog/Domain/AI/AthleteContext.swift` — pure value types:
  - `PromptBudget` — token accounting for the ~4k on-device window (`contextWindow` 4096,
    `responseReserve` 1400, conservative ~3.5 chars/token estimator, `remainingTokens(afterFixed:)`).
  - `LiftDigest` — per-lift summary (last top set, current/best e1RM, trend % via the tested
    `ProgressAggregator`, session count) with `promptLine` / `shortNote` renderings.
  - `MuscleSetVolume` + `AthleteContext` — `make(history:catalog:now:windowDays:maxLifts:)`
    digests `HistoryEntry` (56-day relevance window, 10-lift cap, trailing-7-day working sets
    per primary muscle); `promptSection(maxTokens:)` trims least-relevant lifts to fit budget.
- `Replog/Domain/AI/AIPlanService.swift` — `generate(_:athlete:)` threads the context through;
  framing prompt appends the history section under whatever budget the fixed parts leave;
  selection prompt annotates logged candidates with `[logged: last X kg × R, trend]` plus a
  "prefer lifts that are progressing" hint.
- `Features/Onboarding/OnboardingViewModel.swift` — `generate(history:)` builds the context.
- `Features/Onboarding/OnboardingFlow.swift` — generating step fetches all `HistoryEntry`
  from the model context and passes them in (empty on first run → identical prompts as before).
- NEW `ReplogTests/AthleteContextTests.swift` (13 tests) + 3 new tests in
  `ReplogTests/AIPlanServiceTests.swift` (history embedding, budget margin, candidate annotation).

**Build:** clean, 0 errors / 0 warnings (fixed one isolation warning by making
`AthleteContext.empty` nonisolated).
**Tests:** 162/162 passed on iPhone 17 (was 146; +16 new, all logic-layer). Coverage of the new
file is effectively full — every branch of `make`/`promptSection`/`PromptBudget` is exercised.

**Screenshots:** none — the change is prompt/domain-level with no visible UI; the onboarding flow
UI is untouched.

**Assumptions / decisions:**
1. Backlog said "use `tokenCount(for:)`" — FoundationModels exposes **no public token-count API**
   (iOS 26 SDK), so `PromptBudget` estimates conservatively at ~3.5 chars/token and reserves
   1400 tokens for the structured response. Budget test asserts input + reserve ≤ 4096.
2. Goal/equipment/injuries/bodyweight were already in the prompt via `profileLines(_:)`;
   `AthleteContext` adds only the history digest rather than duplicating them.
3. History window = 56 days (stale lifts aren't coaching-relevant), max 10 lifts ranked by
   session count, then recency. Weekly volume = trailing 7 days, primary muscles only.
4. The deterministic `PlanGenerator` fallback intentionally ignores `AthleteContext` for now —
   consuming history deterministically is exactly item B1 (progression engine).

**NEEDS HUMAN REVIEW:**
- The live Apple Intelligence path (real model reading the history section and adapting its
  picks) cannot run in the simulator; the fallback is what tests exercise. Please verify
  on-device with a seeded history that a regenerated plan references logged lifts.

**Recommended next item:** A2 (planner eval harness — personas + property assertions); it now
can also assert prompt-level properties over `AthleteContext` personas.
