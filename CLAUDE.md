# Replog — Claude Code Context

Replog ("Rep + Log") is a native iOS gym workout planner with an on-device "AI" twist.
Plan your training → log working sets at the gym → track progression over time.
SwiftUI, iOS 26.5, on-device only (no backend, no network).

## ⚠️ Working agreement (do this every time)
- **Never commit.** Make changes only; the owner reviews the diff and commits.
- Work only on the **`development`** branch.
- Write professional unit tests alongside code; keep the **logic layer ≥70% covered**.
- The product spec is the source of truth: `../README.md` and `../design_handoff_replog/`
  (per-screen notes + `screenshots/`). The bundled HTML prototype is **reference only**.

## Locked technical decisions
- **Persistence: SwiftData** (the spec says "Core Data"; we use its modern successor).
- **AI planner: a deterministic rule-based engine** (`PlanGenerator`) that picks real catalog
  exercises from the quiz answers, shown behind a ~1.8 s "Building your plan" spinner. No LLM, no network.
- **Font: SF Rounded** (`.system(design: .rounded)`), no bundled fonts.
- **Images: HEIC**, ~420 px, q42 — the full Free Exercise DB (1746 photos) ships at ~18 MB.

## Data model — the "onion"
```
Plan ──< Workout ──< PlanItem(exId) ──< SetTemplate {weightKg, reps, rpe}
```
- **Static catalog** (read-only, bundled): `Exercise` + enums in `Catalog/`; 873 exercises loaded
  from `Resources/exercises.json` by `ExerciseCatalog`. User data references exercises by `exId`.
- **Live logging**: `ActiveSession ──< SessionExercise ──< LoggedSet` (with `done`, `prevWeight/Reps`).
- **History**: `HistoryEntry` per exId, appended on Finish (drives Progress + next session's "previous").
- **Singletons**: `UserProfile` (name, goal, streak, doneDates, onboardingDone), `AppSettings`
  (units, darkMode, restTimerAuto, restSeconds). Fetch-or-create via `ModelContext` extensions
  in `Models/ReplogStore.swift`. Relationships cascade-delete.

## Key formulas (Domain/)
- Est. 1RM (Epley): `weight * (1 + reps/30)` — `Formulas.e1rm`.
- Units: store kg; display kg or lb (`kg*2.20462`, lb rounded to nearest 5). Steps: +2.5 kg / +5 lb.
- Trend arrows: a logged value vs the **same set index last session** → up/down/flat (`TrendCalculator`).
- Streak: consecutive completed days ending today, with a same-day grace period (`StreakCalendar`).

## Project layout (`Replog/`)
- `App/` — entry, `RootView` (onboarding vs main + dark mode + active-session cover), `MainTabView`,
  navigation, environment, `DebugSeed` (DEBUG-only launch-env seeding — see below).
- `DesignSystem/` — color tokens (`Theme`), SF Rounded typography, reusable components
  (Pill, StepperControl, TrendArrow, SegmentedToggle, WeekStripView, Sparkline, FlowLayout, …).
- `Catalog/` — `Exercise` + enums (lenient decoding), `ExerciseCatalog`, `ExerciseImageView` (HEIC + cache).
- `Models/` — SwiftData `@Model` types + `ReplogStore` (schema, containers, singleton helpers).
- `Domain/` — pure logic: `Formulas`, `PlanGenerator`/`PlanFactory`, `QuizAnswers`, `TrendCalculator`,
  `ProgressAggregator`, `StreakCalendar`, `Scheduling`, `SessionBuilder`, `SessionFinisher`.
- `Features/` — `Onboarding`, `Today`, `Plans` (list/detail/editor/picker), `Library`,
  `ExerciseDetail`, `Progress`, `Profile`, `ActiveSession`.
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
