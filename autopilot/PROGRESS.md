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

---

## Iteration 2 — 2026-07-02 ~10:50 — Claude Opus 4.8 — Item A2

**Item:** A2. Planner eval harness (personas + property assertions, AUTOPILOT §5).

**What changed:**
- NEW `ReplogTests/PlannerEval.swift` — the harness:
  - `EvalPersona` (name + `QuizAnswers` + fabricated `HistoryEntry` trail) and `EvalPersonas`
    (`@MainActor`) with `progressing(…)` / `stalling(…)` history builders and `all(catalog:now:)`
    returning **7 personas**: fresh beginner (no history), intermediate w/ bench+squat
    progressing, machine-only, bodyweight-only, knee-injured runner, fat-loss home-dumbbell
    staller, advanced high-frequency recomp w/ mixed history.
  - `PlannerEvalMetrics` (pure): `exercises/equipmentUsed/primaryMusclesTrained/`
    `weeklySetsPerMuscle/prescribedReps/prescribedRPE` over a `GeneratedPlan` + catalog.
  - `EvalPrescription` — goal→reps, experience→RPE contract, and weekly-set guardrails
    (`minEffectiveSets = 2`, `maxRecoverableSets = 40`).
- NEW `ReplogTests/PlannerEvalTests.swift` — **14 property tests** over the roster:
  non-empty plan; day count == request (3–6); equipment never exceeds allowed;
  machine-only never gets `.bodyOnly` (and only `.machine`); bodyweight ⊆ {bodyOnly, bands};
  injured muscles never primary movers; reps==goal contract; RPE==experience contract;
  weekly sets/muscle in band; ≥4 muscles trained; progressing history → up trend, stalling →
  flat trend (`AthleteContext` signal); rich history → different, in-budget framing prompt;
  candidate list never offers unavailable equipment.

**Reviewer pass:** metrics are pure and `@MainActor` only where `HistoryEntry` (a `@Model`)
requires it; personas built from the real catalog so exId resolution and equipment filters
match production; no force-unwraps except `try! #require` in tests (idiomatic here). No
production code touched — additive test-only files.

**Build:** clean, 0 errors / 0 warnings (`** BUILD SUCCEEDED **`).
**Tests:** 176/176 passed on iPhone 17 (was 162; +14, all in `PlannerEvalTests`, all logic-layer).

**Screenshots:** none — test-only change, no UI surface.

**Assumptions / decisions:**
1. **Fallback caveat (documented in file header):** `FoundationModels` is unavailable in the
   simulator, so every persona's plan comes from the deterministic `PlanGenerator`. The
   properties constrain the PLAN (equipment/muscles/volume/prescription), so they guard both
   engines, but the live model's specific picks still need on-device verification.
2. **Progression property is asserted as a SIGNAL, not an action.** The deterministic engine
   does not yet adapt load/reps to history (that is B1). So the harness asserts that
   `AthleteContext.make` correctly reports an *up* trend for a progressing trail and *flat* for
   a stalled one — i.e. the data feeding the planner is right — and treats the deterministic
   prescription (reps/RPE) as a fixed contract. When B1 lands, `EvalPrescription` becomes
   history-aware bands and those two tests tighten into "next prescription increases".
3. **Weekly-set band = [2, 40] sets/muscle.** Evidence-based hypertrophy targets (10–20) are
   *not* asserted because the current volume-blind engine can't guarantee them for every muscle
   in a 3-day split; [2, 40] catches trivial/junk volume and is the honest guardrail until a
   volume-aware generator exists. Noted as future tightening.

**NEEDS HUMAN REVIEW:**
- The live Apple Intelligence planner path is still unexercised by tests (sim limitation). The
  eval harness now makes it cheap to re-run the same property checks against a real on-device
  plan — worth doing manually once to confirm the model honors equipment/injury constraints.

**Recommended next item:** A3 (Coaching memory store — `CoachingLog` `@Model` + `ReplogStore`
helpers). It is READY, has no blockers, and unblocks B1/B3/C1/D1.
