# Replog — Claude Code Context

Replog ("Rep + Log") is a native iOS gym workout planner with an on-device "AI" twist.
Plan your training → log working sets at the gym → track progression over time.
SwiftUI, iOS 26.5, on-device only (no backend, no network).

## ⚠️ Working agreement (do this every time)
- **Never push.** Pushing and anything touching `main` is the owner's, always.
- **Commit constantly**, one change per commit, so history pinpoints which commit caused what.
  There is no commit budget; err toward more, smaller commits. The owner reviews the commits.
  (This line used to read "never commit, the owner commits" — that was wrong, and it cost a
  session's work being handed over as one unreviewable pile of uncommitted edits.)
- Work only on the **`development`** branch.
- Write professional unit tests alongside code; keep the **logic layer ≥90% covered**
  (raised from 80% on 2026-08-29, when it reached ~91%).
- The product spec is the source of truth: `../README.md` and `../design_handoff_replog/`
  (per-screen notes + `screenshots/`). The bundled HTML prototype is **reference only**.
- **Build clean** (0 errors / 0 warnings) and run the tests on the one simulator below before
  calling anything done. (The mid-edit "Cannot find type … in scope" SourceKit diagnostics are cross-file
  indexing noise; trust `xcodebuild`, not the live diagnostics.)
- **One simulator, and it already exists.** The machine has a single iOS 26.5 runtime and a
  single device, `CapaCam-iPhone17Pro` (`0099037A-7A35-4AB6-9982-6950D9A63928`) — it belongs to
  another project, so **use it, never delete it, and never install a second runtime or device**
  (the owner's disk is tight). There is no device *named* "iPhone 17", so target it by id:
  `-destination 'platform=iOS Simulator,id=0099037A-7A35-4AB6-9982-6950D9A63928'`. Purge test
  clones afterwards (`xcrun simctl --set testing delete all`) and keep result bundles off the
  project disk. The zero-write `swiftc -typecheck` recipe below still needs no device at all.
- **The suite is green on `development`** (880+ cases, 0 failures) and the logic layer sits at
  ~91%. The four long-standing failures this file used to list were fixed on 2026-08-29; a red
  test now is almost certainly yours. Baseline against a stash before concluding otherwise.

## ⚙️ Delivery standard — the 4-pass method (apply to every numbered task list)
Whenever the owner hands over a **numbered** list of bugfixes/improvements (1, 2, 3, … n), take each
item through four internal passes before presenting the work — think of it as one engineer wearing
four hats, or four teams in sequence:
1. **Engineer** — implement to senior-iOS standard: clear architecture, performant, idiomatic
   SwiftUI/SwiftData, matching the surrounding conventions and DesignSystem tokens.
2. **Reviewer** — re-read the diff as a second iOS engineer: correctness, edge cases, retain cycles,
   `@MainActor` isolation, SwiftData relationship/save correctness, naming, dead code.
3. **QA/Testing** — verify behavior: add/update/delete unit tests (meaningful, no filler), build
   clean, run the suite, and DEBUG-seed launch for anything visual.
4. **PM** — confirm every numbered requirement is fully satisfied, then hand the diff to the owner as
   the final reviewer before they commit.
Keep the build green between items; number your own status back to the owner the same way they
numbered the request.

## Architecture conventions (senior iOS / SwiftUI)
- **MVVM where it earns its keep.** Feature UI state + intent + non-trivial logic live in a
  `@MainActor @Observable` view model (e.g. `LibraryViewModel`, `RestTimerModel`,
  `OnboardingViewModel`). Views stay declarative.
- **SwiftData stays in the View.** `@Query` and `@Bindable` model access belong in the View (Apple's
  guidance); don't smuggle them into view models. Persistence *writes* go through the pure Domain API
  (`SessionBuilder`, `SessionFinisher`, `PlanFactory`) which view models/views call. Simple derived
  values over `@Query` results can stay as computed properties on the View — that's idiomatic, not a
  reason to spin up a VM.
- **Reuse components, don't re-roll them.** Shared building blocks live in `DesignSystem/`
  (`NumericStepperField`, `StepperControl`, `Pill`, `FlowLayout`, `SegmentedToggle`, …) and
  `Catalog/` (`ExerciseThumbnail` for every list thumbnail, `ExerciseImageView` for raw photos).
- **Responsive & accessible.** Prefer flexible frames / `FlowLayout` / `ViewThatFits` over magic
  widths; keep SF Rounded fonts Dynamic-Type friendly; respect safe areas. Verify on a small
  (SE-class) and large (Pro Max) simulator.
- **Pure logic is testable.** Anything with branching (parsing, filtering, streaks, timers) gets a
  pure function/type in `Domain/` or a VM, covered by Swift Testing.
- **Keyboards dismiss everywhere.** Number/decimal pads have no return key, so: scroll containers use
  `.scrollDismissesKeyboard(.immediately)`, text screens use `.hideKeyboardOnTap()`
  (`DesignSystem/KeyboardDismiss.swift` — a *simultaneous* tap that never steals button taps), and
  `NumericStepperField` carries a keyboard-toolbar "Done".
- **Dismiss-only sheets** rely on the grabber / swipe-down (`.presentationDragIndicator(.visible)`),
  no "Done" button (e.g. `StatDetailSheet`). Keep "Done"/primary buttons only where they *do* something.
- **See `ARCHITECTURE.md`** (repo root) for the full architecture, patterns, naming, folder rationale,
  and ASCII diagrams.

## Locked technical decisions
- **Persistence: SwiftData** (the spec says "Core Data"; we use its modern successor).
- **AI planner: on-device Apple Intelligence** (`FoundationModels`), in `Domain/AI/`, now
  **program-driven**. `ProgramMatcher` first narrows the bundled 62-program library to a gated + scored
  shortlist for the athlete. Then two-stage, genuinely model-driven & non-deterministic (temperature
  1.0): a **framing** call picks ONE program from that shortlist (disclaimer programs excluded) + writes
  the report sections, then **per-day** calls fill each `ProgramSlot` with a specific exercise from a
  numbered list of real catalog candidates (filtered to the user's equipment/injuries via
  `PatternMapping` — an exercise's **missing equipment counts as bodyweight**, so a machine-only user
  never gets a bodyweight movement) and justify each. `ProgramPlanBuilder` validates slot picks and is
  the shared resolver; `ReportComposer` renders the saved report. Grounded in `CoachingKnowledge`. Still
  **on-device, no network**. Falls back deterministically: no model → `ProgramMatcher`'s top
  auto-pickable program built by the same slot resolver; if that can't materialise → the legacy
  `PlanGenerator` split. Flagged via `usedAppleIntelligence`. `Plan` stores `programId` + progression.
- **The coach: on-device & explainable.** `CoachEngine` produces a deterministic, priority-sorted
  `[CoachInsight]` (session debrief, stall alerts, adherence, milestones, bodyweight/readiness trends,
  check-in prompts) — every recommendation carries a plain-language REASON from the deterministic
  engines. `CoachVoice` may reword an insight into coach voice (fallback = verbatim); it never invents
  the decision. Surfaced as a post-Finish debrief sheet, one dismissible Today "Coach" card/day, and a
  Profile "Coach Insights" list — **every row of which opens `CoachInsightDetailSheet`**, built by
  the pure `CoachInsightDetail` (metrics in a fixed order, weights in the athlete's units, catalog
  ids in the tags resolved to lift names, the insight's own kind not repeated back as a chip). Weekly/monthly narrative reports (`WeeklyReportComposer`/
  `MonthlyReportComposer`, triggered on activation) list under Profile "Training Reports". Optional
  readiness check-in at session start modulates volume (`ReadinessModulator`). Capped, respectful local
  notifications (`NotificationPlanner`: ≤1/day, quiet hours, per-kind toggles, encouraging copy).
- **Font: SF Rounded** (`.system(design: .rounded)`), no bundled fonts. Weights pass through
  `Font.rounded`'s refined scale (900→700, 800/700→600 — SF Rounded closes up at 800+;
  hierarchy comes from size). Tune the app's voice ONLY there, never per call site.
- **Images: HEIC**, ~420 px, q42 — the full Free Exercise DB (1746 photos) ships at ~18 MB.
  `ExerciseImageView(contentMode:)` — thumbnails use `.fill` (uniform square crop, via
  `ExerciseThumbnail`); the ExerciseDetail hero uses `.fit` (whole movement, never cropped) with
  pinch/double-tap zoom. Plan cards render an even "film strip" (`ExerciseFilmStrip`).
  **Image layout rule:** `ExerciseImageView` uses `Color.clear.overlay { image }.clipShape(…)` so a
  `.fill` image is constrained to (and cropped by) its frame. Never wrap a `.fill` image in a bare
  `ZStack`+frame — it overflows and any border overlay lands on a mismatched, inset rect (the old
  "white square on the thumbnail" bug). One frame → one clip → one hairline, all on the same rect.

### External data (one level up, not committed)
The repo lives at `Project-Replog/Replog`. One level up (`../`) sit the source assets:
`../free-exercise-db-main/` — the raw Free Exercise DB (`exercises/*.json`, images, and
`schema.json`, the taxonomy source the bundled `Resources/exercises.json` is built from);
`../README.md` (product spec); `../design_handoff_replog/` (per-screen notes + `screenshots/`).
The catalog facets (level, equipment, force, category, mechanic, primary/secondary muscles) mirror
`schema.json` and drive the Library filter.

## Data model — the "onion"
```
Plan ──< Workout ──< PlanItem(exId, restSeconds?) ──< SetTemplate {weightKg, reps, rpe, estimated}
```
`Plan` also stores `programId` + `progression{Type,Rule,Deload}` (program-driven). `SetTemplate.estimated`
flags a computed starting-load seed (see Key formulas) so the live log renders it as a suggestion.
- **Rest timer**: `PlanItem.restSeconds`/`SessionExercise.restSeconds` (nil = app default) set the
  per-exercise rest; `SessionBuilder` copies plan → session. The default `AppSettings.restSeconds` is
  editable in Profile; the Workout Editor ("Rest for all exercises") and Plan Detail ("whole plan")
  toolbar buttons open `SetRestSheet` — a `NumericStepperField` (matching Profile's Rest duration) that
  bulk-applies. In the live workout, completing **any** set (re)starts the timer when `restTimerAuto`
  is on **or a timer is already running** (so checking a set resets the active countdown) —
  `RestTimerModel`. Profile Preferences order: Rest duration → auto-start → Units → Dark mode.
- **Ordering & drag-to-reorder**: every level of the onion carries an `order` (`Orderable`).
  Appends allocate `Reordering.nextOrder(after:)` — **never `collection.count`**, which collides
  after a delete and makes the `order` sort unstable. Plan Detail's workout cards and the Workout
  Editor's exercise cards are long-press draggable: `.onMove` → `Reordering.apply` (contiguous
  renumber + save). `List` is the *only* container with native reordering on iOS 26 (the
  `dragContainer`/`draggable(containerItemID:)` family is `@available(iOS, unavailable)`), hence the
  Workout Editor is a `List` styled with `plainListRow`, split into header/rows/actions sections so
  the drop indicator stays inside the draggable run. **No `EditButton`** — edit mode disables row
  content (the hidden `NavigationLink` and the Start button). **Never attach a custom gesture to a
  reorderable row**: the lift is a UIKit recognizer on the backing cell, `simultaneousGesture`
  composes only with *SwiftUI* gestures, and a row-level long press steals the touch so the row
  never lifts (learned on device — there is also no SwiftUI hook for the lift moment on iOS).
  `DragToReorder` therefore adds only the drop-commit haptic and the VoiceOver "Move up/down"
  actions; the system draws and announces the lift itself. Dragging a workout changes reading order
  only, never its weekday.
- **Extra workouts**: `Workout.isExtra` = a day-less workout run on any day ("Extra" pill left of
  Sunday in the editor's day picker; `slotLabel`/`slotTag` render "Extra" on cards). Extras never
  join the schedule (`scheduledDays` filters them), never lock a weekday, lead Today's "Add
  another" shelf, never claim the Today hero, and the 8th workout of a full week is created as one.
- **Static catalog** (read-only, bundled): `Exercise` + enums in `Catalog/`; 873 exercises loaded
  from `Resources/exercises.json` by `ExerciseCatalog`. User data references exercises by `exId`.
- **Live logging**: `ActiveSession ──< SessionExercise ──< LoggedSet` (with `done`, `prevWeight/Reps`).
  `ActiveSession.isOpen` drives pause/continue: closing with "X" sets it false (paused & persisted,
  resumable from Today); only a real Finish deletes the session. Finishing an **incomplete** workout
  offers "Save for later" (same pause path → Today shows "Continue") alongside "Finish anyway". The
  active-session cover is bound to the first session where `isOpen`.
- **Plan report**: each AI-generated `Plan` stores `reportMarkdown` + `headline` (re-readable in Profile).
- **History**: `HistoryEntry` per exId, appended on Finish (drives Progress + next session's "previous").
  Stores `topRPE` (the top set's logged RPE) so `LoadCalibrator`/`ProgressionEngine` can correct a
  starting-load estimate from real felt effort. `ReadinessEntry` = subjective session-start check-ins.
- **Singletons**: `UserProfile` (`name` = first name only, goal, `streak` = workout streak,
  `weekStreak`, doneDates, onboardingDone, totalWorkouts), `AppSettings` (units, darkMode,
  restTimerAuto, `restSeconds` = default rest, editable in Profile).
  Fetch-or-create via `ModelContext` extensions in `Models/ReplogStore.swift` (incl. `recomputeStreaks`).
  Relationships cascade-delete.

## Key formulas (Domain/)
- Est. 1RM (Epley): `weight * (1 + reps/30)` — `Formulas.e1rm`.
- **Starting loads are COMPUTED per user, never hardcoded** (`StartingLoadEstimator`). Program
  slots carry only sets/reps/RPE; the absolute kg is derived from movement pattern + loading type
  + user (sex, experience, bodyweight) via bodyweight-relative untrained-male 1RM anchors →
  Epley/RIR working load → sex scaling of the *estimate only* (~0.55 upper / ~0.68 lower) →
  experience multiplier → real-increment rounding with an empty-bar floor (never a sub-bar
  barbell load) and no external load for bodyweight moves. Seeds err LOW and are flagged
  `estimated` (SetTemplate/GeneratedSet) → shown as an "est" suggestion in the live log.
  `LoadCalibrator` (RIR-adjusted Epley) + `HistoryEntry.topRPE` let `ProgressionEngine` (opt-in
  `targetRPE`) recalibrate from the first logged set's felt RPE, so a bad seed self-corrects in
  1–2 sessions. **Progression RATES are never scaled by sex** — only the starting estimate.
- Units: store kg; display kg or lb (`kg*2.20462`, lb rounded to nearest 5). Steps: +2.5 kg / +5 lb.
- Trend arrows: a logged value vs the **same set index last session** → up/down/flat (`TrendCalculator`).
- Streaks: **schedule-aware over binary days** (`StreakEngine`): a day is *done* when ANY workout
  was fully completed that day — whichever weekday it was assigned to, or a day-less **Extra**;
  several finishes still count once. **Workout streak** = consecutive done days (rest days pass
  through; a past scheduled day with nothing done breaks it; today's still-due workout gets grace;
  empty schedule → plain consecutive done days). **Week streak** = consecutive "perfect weeks"
  (every scheduled day that week done, by any workout) — a missed scheduled day breaks both.
  `StreakCalendar` still provides the Today week-strip + completed-day recording. Finish only counts
  a **fully complete** workout toward streaks/history-day; a partial Finish saves history but warns
  and doesn't count.

## Project layout (`Replog/`)
- `App/` — entry, `RootView` (onboarding vs main + dark mode + active-session cover **+ the
  post-session celebration**), `MainTabView`, navigation, environment, `DebugSeed` (DEBUG-only
  launch-env seeding — see below).
  - **Finishing a workout celebrates from `RootView`, not from the workout screen.** Finishing
    DELETES the `ActiveSession`, and the workout is a `fullScreenCover(item:)` bound to that very
    session — so anything the workout view presented for itself was torn down mid-flight, which is
    why the badge moment used to be invisible. `ActiveWorkoutView` now hands what it earned to
    `onFinished`; `SessionCompletion` (a plain, fully-tested state machine in
    `Features/ActiveSession/`) holds it until the cover has gone; `RootView` then plays **the badge
    celebration first** (it is the rare thing, and it is what the athlete just tapped Finish for)
    and the coach's debrief after it. The rating ask waits for the whole sequence.
- `DesignSystem/` — color tokens (`Theme`), SF Rounded typography, reusable components
  (Pill, StepperControl, `NumericStepperField` (typeable +/- field), TrendArrow, SegmentedToggle,
  WeekStripView, Sparkline, FlowLayout, `DragToReorder` (reorder commit haptic + a11y move
  actions — never gestures on reorderable rows), …).
- `Catalog/` — `Exercise` + enums (lenient decoding), `ExerciseCatalog` (incl. `search(_:filter:)`),
  `ExerciseImageView` (HEIC + cache, `contentMode`) + `ExerciseThumbnail` (uniform list thumbnail).
  - `Catalog/ProgramLibrary/` — the bundled **62-program library** (`Resources/programs.json`):
    `WorkoutProgram` (+ `ProgramDay`/`ProgramSlot`/`ProgramAudience`/`ProgramProgression`, lenient like
    `Exercise`), `MovementPattern` (slot pattern enum with `.other`), `ProgramCatalog` (loader/queries).
- `Models/` — SwiftData `@Model` types + `ReplogStore` (schema, containers, singleton helpers).
  Includes `ReadinessEntry` (subjective check-ins) and the notification prefs on `AppSettings`.
- `Domain/` — pure logic: `Formulas`, `PlanGenerator`/`PlanFactory`, `QuizAnswers`, `TrendCalculator`,
  `ProgressAggregator`, `ProgressionEngine`, `StallDetector`, `StreakCalendar`, `StreakEngine`,
  `Scheduling` (incl. `WeekBrowser`), `SessionBuilder`, `SessionFinisher`, `BodyweightTracker`,
  `Reordering`, `CalendarMath`/`CalendarStats` (calendar grid math + range statistics),
  `ProgressAnalytics` (weekly volume buckets, muscle shares, rep-range mix, adherence, PR
  events, relative strength — the Progress dashboard's derivations), `RecentHighlight` (the
  heaviest logged est. 1RM plus the session around it — Today's highlight card and its sheet),
  `CoachInsightDetail` (a recorded coaching log opened up: ordered metrics, lift names, notes).
  - **One plan, one prescription per movement:** `PlanExerciseSync` mirrors an edit to a
    `PlanItem`'s sets (weight / reps / RPE / set count) onto every *other* workout in the SAME
    plan that prescribes that movement, occurrence-matched, and never across plans. The Workout
    Editor routes all three of its writes through it (`syncAcrossPlan`), and `PlanFactory
    .addExercise` adopts the plan's existing numbers instead of a generic 20 kg x 10. The logged
    half of the same rule is `TemplateWriteBack.propagateWithinPlan`.
  - **Program-driven planning:** `ProgramMatcher` (hard-gated + soft-scored program selection from
    `QuizAnswers`), `PatternMapping` (slot `MovementPattern` → catalog facets → real candidates),
    `RepScheme` (parses slot reps/intensity into `SetTemplate` targets — ranges→lower bound,
    time/hold→seconds, RPE from intensity; convention in `ARCHITECTURE.md`),
    `StartingLoadEstimator` (science-based per-user starting kg — never hardcoded) +
    `LoadCalibrator` (RPE→true-load, self-corrects a seed in 1–2 sessions).
  - **The coach:** `ReadinessModulator` (readiness → session modulation + weekly pattern),
    `WeeklyReportComposer`/`MonthlyReportComposer` + `ReportScheduler` (activation + best-effort
    `BGTaskScheduler`), `NotificationPlanner` (pure: what to schedule; caps + quiet hours + toggles)
    / `NotificationScheduler` (thin `UNUserNotificationCenter` boundary).
  - `Domain/AI/` — Apple Intelligence: `AIPlanService` (program-driven two-stage: pick a program from a
    `ProgramMatcher` shortlist, then fill each slot with a real exercise; deterministic fallback via
    `ProgramMatcher`'s top pick → `ProgramPlanBuilder` → legacy `PlanGenerator`), `ProgramPlanBuilder`
    (the shared slot resolver), `PlanBlueprint` (`@Generable` program-framing/selection + report value
    types), `ReportComposer` (markdown + fallback), `CoachEngine` (explainable `[CoachInsight]`) +
    `CoachContextBuilder` (store glue) + `CoachVoice` (optional reword, fallback verbatim),
    `AthleteContext`, `CoachingKnowledge`. The pure resolvers/composers/planner/coach are fully tested;
    the live model calls are non-deterministic seams (not unit-tested) — verified on-device.
- `Features/` — `Badges` (`BadgeCelebrationOverlay`: the medal tumbles in from above and SINKS
  slowly into place under a tightening ladder of soft haptics, strikes with a heavy tap + shockwave,
  then stays alive — a slow 3D tilt, a few points of vertical drift, and a halo breathing in the
  medal's own palette. All drawn, no assets; Reduce Motion keeps the medal, the copy and the success
  haptic and moves none of it), `Onboarding` (quiz: **first name only, asked last**; `Gender` (default `.male`),
  goal (no emojis), sport when goal is Sport (running/swimming/football/basketball/cycling/boxing/
  volleyball/**Other + free-text** `customSport`), height, weight, equipment-type multi-select that
  restricts the plan; real AI "Building your plan" + result/report — each generated day on the result
  screen opens a read-only `GeneratedWorkoutPreview`), `Today` (streak flame is an orange SF Symbol;
  "Add another" cards tap through to the workout; the three stat cards open `StatDetailSheet` history
  sheets; **the Recent Highlight card opens `RecentHighlightSheet`** — the set that produced the best
  est. 1RM, the rest of that session with its top set marked, the plan/day it belonged to, what it
  beat, the lift's line since, and a link through to full progress), `Plans` (list/detail/editor/picker; native swipe-to-delete), `Library` (search + a
  multi-facet `LibraryFilter`/`LibraryFilterSheet` — level, equipment, force, type, mechanic, muscles;
  the **muscles facet is AND** (must train every selected muscle) with a **scope toggle**
  (`MuscleScope`: primary-only vs primary+secondary), the rest OR-within/AND-across;
  driven by `LibraryViewModel`. Swipe a row **or** "Select" → multi-pick → `AddToWorkoutSheet(exIds:)`
  to add one/many exercises to one/many workouts), `ExerciseDetail` (tag grid = Equipment/Level/Force/
  Type only — **mechanic is a filter, not shown here**; "In your workouts" grouped by plan via pure
  `Domain/WorkoutMembership.grouped`; "Add to workout" → `AddToWorkoutSheet`; when opened from Progress
  it defaults to the **Progress** tab (left)), `Progress`
  (the 4th tab — a 4-layer "onion" dashboard: L1 `ProgressHomeView` = Calendar push card + Swift
  Charts cards (Strength hero, Volume, Muscle balance donut, Consistency, Body) → L2 domain screens
  with `RangePicker` windows (`StrengthDetailView` incl. the PR feed, `VolumeDetailView` incl.
  rep-range mix, `BalanceDetailView` incl. push/pull, `ConsistencyDetailView`, `BodyDetailView`
  incl. relative strength + readiness) → L3 one muscle (`MuscleDetailView`) or one exercise
  (`ExerciseDetailView`) → L4 the tap-to-expand session log. Charts use the monochrome accent ramp
  (`ProgressPalette`), driven by pure `Domain/ProgressAnalytics`),
  `Calendar` (inside Progress, pushed `embedded: true` — see **`CALENDAR_DESIGN.md`**, repo root:
  paged Sunday-first month grid (`MonthGridView` + pure `CalendarMath`), tap for a day's detail,
  long-press-drag multi-select (`DragSelectGesture`, a UIKit recognizer via
  `UIGestureRecognizerRepresentable` — never a SwiftUI long press, see DragToReorder) →
  `RangeSummaryView` totals/averages from pure `CalendarStats`),
  `Profile` (saved AI Coach Reports via `CoachReportView`; the three
  lifetime-stat cards open `StatDetailSheet`), `ActiveSession` (typeable weight/reps via
  `NumericStepperField`; `RestTimerModel`; a native confetti+haptics `CelebrationOverlay` when every
  set is complete). `StatDetailSheet` reconstructs completed workouts via pure `Domain/WorkoutHistory`.
- Design: native iOS 26 controls + Liquid Glass + `.sensoryFeedback` haptics, over the warm brand
  (`DesignSystem/`). New files auto-join the targets (Xcode **synchronized file-system groups**).
- `Resources/` — `exercises.json` + `programs.json` (the 62-program library) + `ExerciseImages/<id>__<n>.heic` (flat, unique names).
- `Scripts/build-exercise-db.sh` — one-shot dev tool that compresses the source DB (lives one level
  up at `../../free-exercise-db-main`, not committed) into `Resources/`. Re-run if you re-tune size.

### Image bundling note
Xcode flattens synchronized-group resources into the bundle root, so images use **flat unique
names** `<id>__<n>.heic` (every exercise has `0.jpg`/`1.jpg` → would collide as nested files).
`Exercise.imageResourceNames` reconstructs these; `ExerciseImageView` resolves via `Bundle.main`.

## Testing
- Framework: **Swift Testing** (`import Testing`), in `ReplogTests/`. **No UI tests** (owner's
  call) — the template `ReplogUITests` target was removed from the project on 2026-08-29, so
  `ReplogTests` is the only test target. Anything visual is checked by launching a DEBUG-seeded
  build (below), never by UI automation.
- Logic layer (`Domain`/`Models`/`Catalog`/view models) is the coverage target (**≥90%**, ~91%
  today); SwiftUI views are intentionally not unit-tested. What is left uncovered there is the
  set of framework seams that cannot be exercised in a unit test — StoreKit (`SubscriptionStore`),
  `UNUserNotificationCenter` (`NotificationScheduler`) and FoundationModels (`AIPlanService`,
  `CoachVoice`) — plus the SwiftUI views themselves.
- Persistence/session tests use `ReplogSchema.inMemoryContainer()` and are `@MainActor`
  (models are MainActor-isolated under the project's default actor isolation).

## Build & test
```bash
# Build
xcodebuild -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,id=0099037A-7A35-4AB6-9982-6950D9A63928' build

# Test with coverage (logic suites)
xcodebuild test -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,id=0099037A-7A35-4AB6-9982-6950D9A63928' \
  -enableCodeCoverage YES -only-testing:ReplogTests
```
There is no simulator *named* "iPhone 16" or "iPhone 17" here — target the one device by id.

### Verifying without a build (when disk is tight)
`xcodebuild` writes DerivedData; `swiftc -typecheck` writes **nothing** and still catches every
type error and warning the compiler would. Match the project's real settings or you'll chase
phantom actor-isolation errors (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_VERSION = 5.0`,
`SWIFT_APPROACHABLE_CONCURRENCY`, `MemberImportVisibility` — all in `project.pbxproj`):
```bash
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
FLAGS=(-target arm64-apple-ios26.5-simulator -sdk "$SDK" -swift-version 5
       -default-isolation MainActor -D DEBUG
       -enable-upcoming-feature MemberImportVisibility
       -enable-upcoming-feature InferSendableFromCaptures
       -enable-upcoming-feature GlobalActorIsolatedTypesUsability
       -enable-upcoming-feature NonisolatedNonsendingByDefault
       -enable-upcoming-feature InferIsolatedConformances)
swiftc -typecheck -module-name Replog "${FLAGS[@]}" $(find Replog -name '*.swift')
```
The test target needs the app module on disk first (~1.6 MB, delete it after) plus the Testing
framework and its macro plugin:
```bash
swiftc -emit-module -module-name Replog -emit-module-path /tmp/Replog.swiftmodule \
  -enable-testing "${FLAGS[@]}" $(find Replog -name '*.swift')
swiftc -typecheck -module-name ReplogTests "${FLAGS[@]}" -I /tmp \
  -F "$(xcode-select -p)/Platforms/iPhoneSimulator.platform/Developer/Library/Frameworks" \
  -plugin-path "$(xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing" \
  $(find ReplogTests -name '*.swift')
```
This is a substitute for "builds clean", not for running the suite — it type-checks, it doesn't
execute. Note `zsh` doesn't word-split a plain `$FLAGS`; use an array or inline the flags.

### DEBUG visual checks (no UI automation available)
Launch envs (DEBUG only, via `SIMCTL_CHILD_*`): `REPLOG_SEED=1` seeds a demo PPL plan + history +
marks onboarding done; `REPLOG_TAB=today|plans|library|progress|profile` picks the initial tab ("calendar" → progress);
`REPLOG_ACTIVE=1` drops into a live workout (`REPLOG_COMPLETE=1` with it = every set done, so the
completion celebration is up); `REPLOG_BADGE=1|2|<badge id>` raises the badge unlock celebration;
`REPLOG_SHEET=highlight|insight` opens Today's Recent Highlight sheet / Profile's top Coach Insight
sheet. The last two exist because a badge unlock and a sheet behind a tap cannot otherwise be seen
at all without UI automation. Example:
`SIMCTL_CHILD_REPLOG_SEED=1 SIMCTL_CHILD_REPLOG_TAB=progress xcrun simctl launch <sim> test.Replog`
(uninstall first for a deterministic, empty store).
