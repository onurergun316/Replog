# Replog — Claude Code Context

Replog ("Rep + Log") is a native iOS gym workout planner with an on-device "AI" twist.
Plan your training → log working sets at the gym → track progression over time.
SwiftUI, iOS 26.5, on-device only (no backend, no network).

## ⚠️ Working agreement (do this every time)
- **Never commit.** Make changes only; the owner reviews the diff and commits.
- Work only on the **`development`** branch.
- Write professional unit tests alongside code; keep the **logic layer ≥80% covered**.
- The product spec is the source of truth: `../README.md` and `../design_handoff_replog/`
  (per-screen notes + `screenshots/`). The bundled HTML prototype is **reference only**.

## Locked technical decisions
- **Persistence: SwiftData** (the spec says "Core Data"; we use its modern successor).
- **AI planner: on-device Apple Intelligence** (`FoundationModels`), in `Domain/AI/`. Two-stage,
  genuinely model-driven & non-deterministic (temperature 1.0): a **framing** call designs the split
  + per-day muscle/volume/rep scheme + report sections, then **per-day** calls pick specific exercises
  from a numbered list of real catalog candidates (already filtered to the user's equipment/injuries)
  and justify each. `PlanResolver` validates picks against the catalog (valid refs/images guaranteed);
  `ReportComposer` renders the saved report. The model is grounded in `CoachingKnowledge` (an
  evidence-based prompt cheat-sheet — edit it to steer the science). Still **on-device, no network**.
  `AIPlanService` falls back to the **deterministic `PlanGenerator`** (+ templated report) when the
  model is unavailable, flagged via `usedAppleIntelligence`. No raw-paper RAG yet (context is ~4k tokens).
- **Font: SF Rounded** (`.system(design: .rounded)`), no bundled fonts.
- **Images: HEIC**, ~420 px, q42 — the full Free Exercise DB (1746 photos) ships at ~18 MB.

## Data model — the "onion"
```
Plan ──< Workout ──< PlanItem(exId) ──< SetTemplate {weightKg, reps, rpe}
```
- **Static catalog** (read-only, bundled): `Exercise` + enums in `Catalog/`; 873 exercises loaded
  from `Resources/exercises.json` by `ExerciseCatalog`. User data references exercises by `exId`.
- **Live logging**: `ActiveSession ──< SessionExercise ──< LoggedSet` (with `done`, `prevWeight/Reps`).
  `ActiveSession.isOpen` drives pause/continue: closing with "X" sets it false (paused & persisted,
  resumable from Today); only Finish deletes the session. The active-session cover is bound to the
  first session where `isOpen`.
- **Plan report**: each AI-generated `Plan` stores `reportMarkdown` + `headline` (re-readable in Profile).
- **History**: `HistoryEntry` per exId, appended on Finish (drives Progress + next session's "previous").
- **Singletons**: `UserProfile` (full `name`, goal, `streak` = workout streak, `weekStreak`, doneDates,
  onboardingDone, totalWorkouts), `AppSettings` (units, darkMode, restTimerAuto, restSeconds).
  Fetch-or-create via `ModelContext` extensions in `Models/ReplogStore.swift` (incl. `recomputeStreaks`).
  Relationships cascade-delete.

## Key formulas (Domain/)
- Est. 1RM (Epley): `weight * (1 + reps/30)` — `Formulas.e1rm`.
- Units: store kg; display kg or lb (`kg*2.20462`, lb rounded to nearest 5). Steps: +2.5 kg / +5 lb.
- Trend arrows: a logged value vs the **same set index last session** → up/down/flat (`TrendCalculator`).
- Streaks: **schedule-aware**, two of them (`StreakEngine`, derived from the plans' scheduled weekdays):
  **workout streak** = consecutive scheduled workouts completed (a scheduled day that ends undone
  resets it; today's still-due workout gets grace); **week streak** = consecutive "perfect weeks"
  (every scheduled workout that week done) — a missed workout breaks both. `StreakCalendar` still
  provides the Today week-strip + completed-day recording. Finish only counts a **fully complete**
  workout toward streaks/history-day; a partial Finish saves history but warns and doesn't count.

## Project layout (`Replog/`)
- `App/` — entry, `RootView` (onboarding vs main + dark mode + active-session cover), `MainTabView`,
  navigation, environment, `DebugSeed` (DEBUG-only launch-env seeding — see below).
- `DesignSystem/` — color tokens (`Theme`), SF Rounded typography, reusable components
  (Pill, StepperControl, TrendArrow, SegmentedToggle, WeekStripView, Sparkline, FlowLayout, …).
- `Catalog/` — `Exercise` + enums (lenient decoding), `ExerciseCatalog`, `ExerciseImageView` (HEIC + cache).
- `Models/` — SwiftData `@Model` types + `ReplogStore` (schema, containers, singleton helpers).
- `Domain/` — pure logic: `Formulas`, `PlanGenerator`/`PlanFactory`, `QuizAnswers`, `TrendCalculator`,
  `ProgressAggregator`, `StreakCalendar`, `StreakEngine`, `Scheduling`, `SessionBuilder`, `SessionFinisher`.
  - `Domain/AI/` — Apple Intelligence: `AIPlanService` (the FoundationModels boundary + fallback),
    `PlanBlueprint` (`@Generable` framing/selection + report value types), `PlanResolver`
    (picks → real catalog items), `ReportComposer` (markdown + fallback report), `CoachingKnowledge`
    (science prompt block). The pure resolver/composer/prompts are fully tested; the live model call
    is a non-deterministic seam (not unit-tested) — verified on-device.
- `Features/` — `Onboarding` (quiz incl. name/surname **last**, height, weight, equipment-type
  multi-select that restricts the plan; real AI "Building your plan" + result/report), `Today`
  (streaks + Continue), `Plans` (list/detail/editor/picker; native swipe-to-delete), `Library`,
  `ExerciseDetail`, `Progress`, `Profile` (saved AI Coach Reports via `CoachReportView`), `ActiveSession`.
- Design: native iOS 26 controls + Liquid Glass + `.sensoryFeedback` haptics, over the warm brand
  (`DesignSystem/`). New files auto-join the targets (Xcode **synchronized file-system groups**).
- `Resources/` — `exercises.json` + `ExerciseImages/<id>__<n>.heic` (flat, unique names).
- `Scripts/build-exercise-db.sh` — one-shot dev tool that compresses the source DB (lives one level
  up at `../../free-exercise-db-main`, not committed) into `Resources/`. Re-run if you re-tune size.

### Image bundling note
Xcode flattens synchronized-group resources into the bundle root, so images use **flat unique
names** `<id>__<n>.heic` (every exercise has `0.jpg`/`1.jpg` → would collide as nested files).
`Exercise.imageResourceNames` reconstructs these; `ExerciseImageView` resolves via `Bundle.main`.

## Testing
- Framework: **Swift Testing** (`import Testing`), in `ReplogTests/`. No UI tests (owner's call).
- Logic layer (`Domain`/`Models`/`Catalog`/view models) is the coverage target (~80%); SwiftUI
  views are intentionally not unit-tested.
- Persistence/session tests use `ReplogSchema.inMemoryContainer()` and are `@MainActor`
  (models are MainActor-isolated under the project's default actor isolation).

## Build & test
```bash
# Build
xcodebuild -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Test with coverage (logic suites)
xcodebuild test -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES -only-testing:ReplogTests
```
There is no "iPhone 16" simulator installed here; use **iPhone 17**.

### DEBUG visual checks (no UI automation available)
Launch envs (DEBUG only, via `SIMCTL_CHILD_*`): `REPLOG_SEED=1` seeds a demo PPL plan + history +
marks onboarding done; `REPLOG_TAB=today|plans|library|progress|profile` picks the initial tab;
`REPLOG_ACTIVE=1` drops into a live workout. Example:
`SIMCTL_CHILD_REPLOG_SEED=1 SIMCTL_CHILD_REPLOG_TAB=progress xcrun simctl launch <sim> test.Replog`
(uninstall first for a deterministic, empty store).
