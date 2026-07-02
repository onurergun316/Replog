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

---

## Iteration 3 — 2026-07-02 ~10:55 — Claude Opus 4.8 — Item A3

**Item:** A3. Coaching memory store — the durable context the trainer "remembers" across weeks.

**What changed:**
- NEW `Replog/Models/Coaching.swift`:
  - `CoachingKind` enum (`note`, `progression`, `plateau`, `deload`, `bodyweight`,
    `weeklyReport`, `monthlyReport`, `planAdjustment`) with `displayName`.
  - `CoachingPayload` value type (`metrics: [String: Double]`, `tags: [String]`) with a
    lenient `init(from:)` so a bare `{}` and forward-compatible payloads decode to empties;
    `subscript(metric:)` accessor.
  - `CoachingLog @Model`: `id`, `date`, `kindRaw`(+typed `kind`), `summary`, optional
    `exId` / `planId` **id references** (not relationships — matching `HistoryEntry` /
    `ActiveSession.workoutId`, so the memory OUTLIVES the plan/exercise it concerned),
    and `payloadJSON`(+typed `payload`, the `HistoryEntry.sets` JSON pattern).
- `Replog/Models/ReplogStore.swift`:
  - Registered `CoachingLog.self` in `ReplogSchema.models`.
  - `ModelContext` helpers: `recordCoaching(_:summary:date:exId:planId:payload:)` (the single
    write path, `@discardableResult`), `coachingLogs(kind:limit:)` (newest-first, optional
    kind predicate + fetchLimit), `latestCoachingLog(kind:)`, `coachingLogs(forExercise:)`.
- NEW `ReplogTests/CoachingLogTests.swift` — 14 tests: kind/payload round-trips, lenient
  `{}` decode, save+fetch persistence, record/return, newest-first ordering, kind filter,
  limit, latest-of-kind, per-exercise filter, and the two cascade rules — **a log survives
  `ctx.delete(plan)`** (memory outlives the plan; `planId` still set, no cascade) and deleting
  a log leaves unrelated data intact.

**Reviewer pass:** id-reference (not `@Relationship`) is deliberate and matches the codebase's
cross-cutting-log convention (`HistoryEntry`, `ActiveSession.workoutId`) — a relationship with a
cascade inverse would have *deleted* the memory when a plan is removed, the opposite of the intent.
Enum/payload typed accessors mirror `Goal`/`Units`/`HistoryEntry.sets`. Predicate captures
`kind.rawValue` into a local (SwiftData `#Predicate` requirement). No retain cycles; models are
`@MainActor`-isolated as the rest of the layer. Additive only — no existing type or behavior changed.

**Build:** clean, 0 errors / 0 warnings (`** BUILD SUCCEEDED **`).
**Tests:** 190/190 passed on iPhone 17 (was 176; +14, all in `CoachingLogTests`, all logic-layer).
Coverage: the new file's every branch (`kind`/`payload` get+set, lenient decode, all four store
helpers, both cascade paths) is exercised.

**Screenshots:** none — model/store-layer change with no UI surface (the coaching feed/report UI
that will *render* these logs is D1/future).

**Assumptions / decisions:**
1. **Id references, not relationships.** `exId`/`planId` are plain optionals, so the coaching
   memory persists after its plan or exercise is gone. "relationships + cascade rules tested"
   (accept criteria) is honored by asserting the *no-cascade* property, which is the correct
   behavior for a durable memory and matches the house convention.
2. **`recordCoaching` is the single write path** (returns the inserted log, `@discardableResult`)
   so B1/B3/C1/D1 write memory one way. It inserts but does not `save()` — callers batch the save
   with their own transaction, as elsewhere in the codebase.
3. **`CoachingPayload` is a flexible `metrics`+`tags` bag** rather than a per-kind struct, so each
   future kind carries only what it needs without a schema change; lenient decoding keeps old rows
   readable as the payload evolves.
4. No `fetchLimit` on the unfiltered path unless `limit` is passed; `coachingLogs()` returns all.

**NEEDS HUMAN REVIEW:** none for this item — it is pure model/store logic fully covered by tests.
(Standing item from iters 1–2 still open: the live Apple Intelligence planner path is unexercised
in the simulator; verify on device.)

**Recommended next item:** B1 (Progression engine — pure `Domain/ProgressionEngine`). It is now
READY (A1 + A3 both done), keeps the MATH in code, is fully unit-testable across
progressing/stalling/regressing histories, and its recommendations can be recorded via the new
`recordCoaching(.progression, …)` / `recordCoaching(.deload, …)` write path — directly unblocking
B2, B3, and D1.

---

## Iteration 4 — 2026-07-02 ~11:40 — Claude Fable 5 — Item B1

**Item:** B1. Progression engine (deterministic core) — increase load / increase reps / hold /
deload with a reason, math in code, not the model.

**What changed:**
- NEW `Replog/Domain/ProgressionEngine.swift` — pure double-progression rule table:
  - `ProgressionAction` (`increaseLoad`/`increaseReps`/`hold`/`deload`, `displayName`) and
    `ProgressionRecommendation` (`exId`, `action`, `suggestedWeightKg`, `suggestedReps`,
    one-sentence `reason` ready for the B2 log card / a B3 `CoachingLog`).
  - `recommend(exId:history:repRange:weightStepKg:units:)` — rules, first match wins:
    (1) bodyweight lift (topW 0) trends on **reps** (stored e1RM is weight-based, always 0)
    — +1 rep uncapped, or hold on a rep stall/regression, never a weight suggestion;
    (2) rep-range top reached → +1 weight step, reps reset to the range floor;
    (3) e1RM dropped 2 consecutive deltas → deload; (4) no e1RM improvement across
    3 deltas → plateau deload; (5) single down session → hold (noise, not a trend);
    (6) otherwise +1 rep (clamped into the range).
  - `deloadWeight(fromKg:stepKg:)` — ~10% off, snapped to the stepper increment, always
    strictly below the current weight, floored at 0.
  - `repRange(for goal:)` — 8–12 hypertrophy/recomp, 12–15 fat loss, 6–10 sport (brackets
    `PlanGenerator`'s fixed 10/13/8); goal+units convenience reuses `Formulas.weightStepKg`
    and formats reasons via `Formulas.formatWeight` in the user's display units.
- FIX `Replog/Models/Coaching.swift` — `CoachingPayload` is now `nonisolated`: a clean full
  build surfaced 2 Swift-6 warnings from iter 3 (MainActor-isolated Codable conformance used
  inside nonisolated JSONDecoder/JSONEncoder generics — the custom `init(from:)` suppressed
  the usual nonisolated synthesis). Behavior unchanged; all 14 CoachingLog tests still green.
- NEW `ReplogTests/ProgressionEngineTests.swift` — 21 tests: empty/single-session/order-
  invariance; progressing (+rep, range-top +load & reset, above-top, below-floor lift);
  priority (range top beats a regressing trail); off-day hold; 2-drop regression deload;
  4-session flat plateau deload; 3-session flat still pushes reps; dip-then-recovery is not
  a regression; bodyweight rep progression past the range top + bodyweight stall holds;
  deload snapping/strict-below (property-swept 2.5–200 kg)/zero-step/zero-weight; goal rep
  ranges bracket the generator prescription; goal convenience; lb step + lb-formatted reasons.

**Build:** clean, 0 errors / 0 warnings (** BUILD SUCCEEDED **) — after fixing the two
pre-existing iter-3 warnings above.
**Tests:** 211/211 passed on iPhone 17 (was 190; +21, all logic-layer). Every rule branch,
both deload reasons, both bodyweight paths and all `deloadWeight` edges are exercised.

**Screenshots:** none — pure Domain addition, no UI surface yet (that's B2).

**Assumptions / decisions:**
1. **Double progression** is the model: reps climb at fixed weight; load rises only when the
   goal's rep-range top is hit (then reps reset to the floor). Thresholds as named constants:
   `regressionDeltas = 2` (e1RM strictly down), `plateauDeltas = 3` (no improvement),
   `deloadFactor = 0.9`.
2. **Hitting the range top beats a bad trend** — reaching the top IS current success even if
   prior sessions regressed (tested).
3. **Bodyweight lifts trend on reps, not e1RM** — stored e1RM is `weight × (1 + reps/30)` = 0
   at 0 kg, so an e1RM-based stall signal would mark ANY 4-session bodyweight trail a plateau.
   Caught by hand-verifying test expectations; rep-delta logic added. Bodyweight stalls hold
   (form/quality cue) rather than "deload" a weight that doesn't exist.
4. The engine is **per-lift and history-in, recommendation-out pure**; no CoachingLog writes
   (that wiring is B3's acceptance) and no windowing — callers pass the (already relevant)
   entries, matching `ProgressAggregator`'s contract.
5. A single down session recommends **hold**, not deload — one bad day is noise; the reason
   string says so.

**NEEDS HUMAN REVIEW:** none for this item — pure tested math. (Standing item from iters 1–3:
the live Apple Intelligence planner path still can't run in the simulator; verify on device.)

**Recommended next item:** B2 (apply recommendations to the next session — surface
`ProgressionRecommendation` on the log card without overwriting user input). It is READY,
consumes B1 directly, and its acceptance (suggestion visible + dismissible + seeded-launch
screenshot) is the first user-visible payoff of the adaptive trainer. B3 is also READY if a
smaller item is preferred.
