# Replog — Rep + Log

A native iOS gym planner with an on-device coach. Plan your training, log your working sets at the
gym, and watch the numbers move. No backend, no account, no network call — the planner, the coach,
the reports and the reasoning all run on the phone.

```
   ┌──────────────┐    ┌────────────────────┐    ┌──────────────┐    ┌──────────────────┐
   │  ONBOARDING  │───►│   62-PROGRAM LIB   │───►│  YOUR PLAN   │───►│  LOG YOUR SETS   │
   │  13 questions│    │  matched, ranked,  │    │ Plan▸Workout │    │  live session,   │
   │  goal · gear │    │  filled with real  │    │ ▸Item▸Set    │    │  rest timer,     │
   │  injuries    │    │  exercises by AI   │    │              │    │  trend arrows    │
   └──────────────┘    └────────────────────┘    └──────────────┘    └────────┬─────────┘
                                                                              │  Finish
             ┌────────────────────────────────────────────────────────────────┘
             ▼
   ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐    ┌──────────────┐
   │  HISTORY ENTRY   │───►│   THE COACH      │───►│  PROGRESS ONION  │    │   BADGES     │
   │  immutable, per  │    │ debrief · stalls │    │ 4 layers of      │    │  74 medals,  │
   │  exercise, per   │    │ streaks · weekly │    │ charts, down to  │    │  drawn not   │
   │  session         │    │ & monthly report │    │ one logged set   │    │  shipped     │
   └──────────────────┘    └──────────────────┘    └──────────────────┘    └──────────────┘
```

---

## Contents

| §  | Section                                                                |
|----|------------------------------------------------------------------------|
| 1  | [At a glance](#1-at-a-glance)                                          |
| 2  | [Getting started](#2-getting-started)                                  |
| 3  | [Repository map](#3-repository-map)                                    |
| 4  | [Architecture](#4-architecture)                                        |
| 5  | [Design patterns, and why these ones](#5-design-patterns-and-why-these-ones) |
| 6  | [App lifecycle & navigation](#6-app-lifecycle--navigation)             |
| 7  | [The data model — the "onion"](#7-the-data-model--the-onion)           |
| 8  | [The reference catalogs](#8-the-reference-catalogs)                    |
| 9  | [Planning: from quiz to plan](#9-planning-from-quiz-to-plan)           |
| 10 | [Loads, progression & the feedback loop](#10-loads-progression--the-feedback-loop) |
| 11 | [The live session](#11-the-live-session)                               |
| 12 | [The coach](#12-the-coach)                                             |
| 13 | [Streaks & the calendar](#13-streaks--the-calendar)                    |
| 14 | [Progress — the four-layer onion](#14-progress--the-four-layer-onion)  |
| 15 | [Badges & medals](#15-badges--medals)                                  |
| 16 | [Replog Premium — the subscription](#16-replog-premium--the-subscription) |
| 17 | [Design system](#17-design-system)                                     |
| 18 | [Testing](#18-testing)                                                 |
| 19 | [Conventions & gotchas](#19-conventions--gotchas)                      |
| 20 | [Roadmap & known gaps](#20-roadmap--known-gaps)                        |

---

## 1. At a glance

| | |
|---|---|
| **Platform** | iOS 26.5+ · iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`) |
| **Language / UI** | Swift 5 language mode · SwiftUI + Swift Charts (UIKit only where SwiftUI can't reach) |
| **Concurrency** | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` · `SWIFT_APPROACHABLE_CONCURRENCY = YES` |
| **Bundle id** | `test.Replog` · version 1.0 |
| **Architecture** | Layered: `App → Features → {DesignSystem, Domain, Catalog} → Models`. **MV + selective MVVM** |
| **Persistence** | **SwiftData** — 15 `@Model` types, one on-disk store, cascade deletes |
| **"AI"** | Apple **`FoundationModels`** (on-device Apple Intelligence), always with a deterministic fallback |
| **Network** | **None.** No URLSession, no backend, no analytics, no account |
| **Monetization** | Freemium. **One free day**, then read-only. Replog Premium: $4.99/mo · $29.99/yr with a 3-day trial. StoreKit 2 |
| **Third-party deps** | **None.** No SPM, no CocoaPods, no Carthage |
| **Bundled data** | 873 exercises · 1 746 photos · 62 training programs · 67 weight comparisons · 74 badges |
| **Source size** | 151 app `.swift` files (~25.6k lines) |
| **Tests** | **759 tests** across 67 Swift Testing suites (~10k lines) |
| **Resources** | ≈19 MB (HEIC image set dominates) |

### The six things that make this app what it is

1. **Nothing is hardcoded that could be computed.** Starting weights are derived from the athlete's
   sex, experience and bodyweight against published untrained standards — never a magic number.
2. **Every recommendation carries a reason.** The deterministic engines decide; the language model
   may only *reword* the already-reasoned sentence. It never invents a number.
3. **The model always has an understudy.** Apple Intelligence unavailable, erroring, or on an
   unsupported device → the app degrades through two deterministic fallbacks and still ships a plan.
4. **Pure core, imperative shell.** Every branch worth testing lives in `Domain/` as a `static`
   function over value types. SwiftData reads and writes stay in the view.
5. **A plan is a scope.** History, progression, stall detection and write-back are all scoped *per
   plan*, so benching 100 kg in a strength block never rewrites the 70 kg in a hypertrophy plan.
6. **Paying gates writing, never reading.** A free athlete keeps every screen, every chart and
   every number they ever logged. What Premium buys is the ability to add to it — see [§16](#16-replog-premium--the-subscription).

---

## 2. Getting started

```bash
git clone <repo> && cd Replog
open Replog.xcodeproj      # no package resolution, no pod install — it just opens
```

**Build** — the canonical check:

```bash
xcodebuild -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

**Test** with coverage:

```bash
xcodebuild test -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES -only-testing:ReplogTests
```

> **Use iPhone 17.** There is no iPhone 16 simulator installed on the project's machine.

> **SourceKit lies in this project.** Mid-edit "Cannot find type … in scope" diagnostics are
> cross-file indexing noise. Trust `xcodebuild`, not the live squiggles.

### Type-checking without a build (when disk is tight)

`xcodebuild` writes DerivedData; `swiftc -typecheck` writes **nothing** and still catches every type
error and warning. You must match the project's real settings or you'll chase phantom
actor-isolation errors:

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

This type-checks; it does **not** execute. It is not a substitute for running the suite.

### DEBUG launch seeding (no UI automation in this project)

Visual checks are driven by launch environment variables, DEBUG-only, via `App/DebugSeed.swift`:

| Variable | Effect |
|---|---|
| `REPLOG_SEED=1` | Seed a demo PPL plan + history and mark onboarding done |
| `REPLOG_TAB=…` | Initial tab: `today` `plans` `library` `progress` `profile` (`calendar` → progress) |
| `REPLOG_ACTIVE=1` | Drop straight into a live workout |
| `REPLOG_MINIMAL=1` | Skip the demo plan, so below-the-fold Today cards land in a screenshot |
| `REPLOG_BODYWEIGHT=1` | Open Today with the bodyweight check-in sheet already presented |
| `REPLOG_DARK=1` | Start in dark mode |

```bash
SIMCTL_CHILD_REPLOG_SEED=1 SIMCTL_CHILD_REPLOG_TAB=progress \
  xcrun simctl launch <sim> test.Replog
```

---

## 3. Repository map

```
Replog/                              ← repo root (the Xcode project lives here)
│
├── Replog.xcodeproj ............ Synchronized file-system groups: new files auto-join targets.
│
├── Replog/                      ══ THE APP ══ 137 swift files
│   ├── ReplogApp.swift ......... @main. Builds the container, bootstraps singletons, runs the
│   │                             backfills + badge sweep, refreshes reports on activation.
│   │
│   ├── App/ (6) ................ Composition root. The only layer that knows every feature.
│   │   ├── RootView ............ onboarding vs main · colour scheme · active-session cover
│   │   ├── MainTabView ......... the 5 tabs
│   │   ├── PlanNavigation ...... Plan▸Workout drill-down destinations
│   │   ├── ProgressNavigation .. `ProgressRoute` — every Progress push, value-based (see §14)
│   │   ├── AppEnvironment ...... `\.exerciseCatalog` injection + `ExerciseRef`
│   │   └── DebugSeed ........... #if DEBUG launch-env seeding
│   │
│   ├── Models/ (10) ............ SwiftData @Model graph + `ReplogStore` (schema, containers,
│   │                             fetch-or-create singletons, every query helper). §7
│   │
│   ├── Catalog/ (9) ............ Read-only reference data + its image pipeline. §8
│   │   ├── Exercise · Enums · ExerciseCatalog · ExerciseImageView
│   │   ├── ProgramLibrary/ ..... WorkoutProgram · MovementPattern · ProgramCatalog
│   │   └── Comparisons/ ........ WeightComparison · ComparisonCatalog ("that's three Smart cars")
│   │
│   ├── Domain/ (55) ............ THE BRAIN. Pure `enum` namespaces of `static` functions. §9–§15
│   │   ├── (40 at root) ........ Formulas · StreakEngine · ProgressionEngine · StallDetector ·
│   │   │                         StartingLoadEstimator · LoadCalibrator · LoadResolver ·
│   │   │                         BodyweightLoad · ProgramMatcher · PatternMapping · RepScheme ·
│   │   │                         SessionBuilder/Finisher · TemplateWriteBack · ProgressAnalytics ·
│   │   │                         CalendarMath/Stats · Weekly/MonthlyReportComposer · …
│   │   ├── AI/ (9) ............. AIPlanService · ProgramPlanBuilder · PlanBlueprint (@Generable) ·
│   │   │                         CoachEngine · CoachVoice · CoachContextBuilder · AthleteContext ·
│   │   │                         CoachingKnowledge · ReportComposer
│   │   ├── Badges/ (6) ......... Badge · BadgeCriterion · BadgeCatalog · BadgeEngine ·
│   │   │                         BadgeSnapshot · BadgeAwarding · MedalPalettes
│   │   └── Subscription/ (8) ... AccessPolicy (the gate) · PremiumGate · SubscriptionStore
│   │                             (StoreKit) · EntitlementReconciler · SubscriptionSummary ·
│   │                             PremiumPlan · PlanOffer · ReviewPrompt
│   │
│   ├── Features/ (46) .......... One folder per screen. View + (where earned) an @Observable VM.
│   │   ├── Onboarding/ ......... the 13-step quiz + "Building your plan" + result & report
│   │   ├── Today/ .............. hero, week strip, extras shelf, stats, coach card, bodyweight
│   │   ├── Plans/ .............. list · detail · workout editor · pickers · rest sheet
│   │   ├── Library/ ............ search + 6-facet filter (`LibraryViewModel`)
│   │   ├── ExerciseDetail/ ..... Guide | Progress movement page
│   │   ├── ActiveSession/ ...... the logging loop · rest timer · readiness · celebration
│   │   ├── Progress/ (14) ...... the 4-layer dashboard onion
│   │   ├── Calendar/ ........... paged month grid + drag-select range summary
│   │   ├── Coach/ .............. debrief sheet · Today card · insight list
│   │   ├── Badges/ · Profile/ .. celebration overlay · trophy cabinet · reports · preferences ·
│   │   │                         subscription status · legal
│   │   ├── Paywall/ ............ PaywallView · PlanOptionRow · LockedBanner
│   │   ├── Legal/ .............. renders the bundled privacy policy & terms
│   │   └── Programs/ ........... reader view for a bundled library program
│   │
│   ├── DesignSystem/ (10) ...... Theme tokens · SF Rounded type scale · Pill/Stepper/
│   │                             NumericStepperField/SegmentedToggle/FlowLayout/Sparkline/
│   │                             SearchField/WeekStripView/MedalView · KeyboardDismiss ·
│   │                             DragToReorder
│   │
│   ├── Resources/ .............. exercises.json (1.0 MB) · programs.json (319 KB) ·
│   │                             comparisons.json (25 KB) · ExerciseImages/*.heic (1 746 files) ·
│   │                             Legal/privacy-policy.md · Legal/terms-of-use.md
│   │
│   └── Scripts/build-exercise-db.sh ... one-shot dev tool: compresses the source Free Exercise DB
│                                        (lives at ../../free-exercise-db-main, not committed).
│
├── Configuration/Replog.storekit ... local store for developing the paywall. OUTSIDE Replog/
│                                     on purpose — that folder is a synchronized root group, so
│                                     anything inside it ships in the app bundle.
│
├── ReplogTests/ (62) ........... Swift Testing. 759 @Test cases · 67 suites · 1 eval harness.
├── ReplogUITests/ (2) .......... Xcode's default stubs. Not a real suite — see §20.
├── Scripts/render-app-icon.swift
│
└── docs at root:
    ARCHITECTURE.md ............. layering, dependency rule, naming, rationale
    CALENDAR_DESIGN.md .......... the Calendar's interaction bible
    PROGRESS_DESIGN.md .......... the Progress onion + the bodyweight-load table & citations
    PROGRESS_SPARSE_DATA.md ..... what every Progress card shows at 0/1/2/5+ data points
    TESTPLAN.md · REMEMBER.md · CLAUDE.md
```

---

## 4. Architecture

Five layers. **Arrows only point downward.** `Domain` never imports `Features`; `Models` never
import `Domain`; nothing imports `App`. The compile graph stays acyclic and the logic layer stays
testable with no simulator and no UI.

```
   ┌────────────────────────────────────────────────────────────────────────────────┐
   │  APP                        ReplogApp · RootView · MainTabView · Nav routes     │
   │  App/                       Composition root: builds the ModelContainer, wires  │
   │                             the catalog into @Environment, runs the one-time    │
   │                             backfills, refreshes reports + notifications.       │
   └──────────────────────────────────────┬─────────────────────────────────────────┘
                                          │ composes
                                          ▼
   ┌────────────────────────────────────────────────────────────────────────────────┐
   │  FEATURES                   One folder per screen: a SwiftUI View, plus an      │
   │  Features/**                @MainActor @Observable view model ONLY where the    │
   │                             screen owns real state (LibraryViewModel,           │
   │                             OnboardingViewModel, RestTimerModel).               │
   │                             @Query and @Bindable live HERE, in the View.        │
   └────────┬────────────────────────┬──────────────────────────┬───────────────────┘
            │ renders with           │ calls (the write API)    │ reads
            ▼                        ▼                          ▼
   ┌──────────────────┐   ┌────────────────────────┐   ┌────────────────────────────┐
   │  DESIGNSYSTEM    │   │  DOMAIN                │   │  CATALOG                   │
   │  DesignSystem/   │   │  Domain/ (55 files)    │   │  Catalog/                  │
   │                  │   │                        │   │                            │
   │  Colour tokens,  │   │  Pure logic + use-case │   │  Static, read-only,        │
   │  SF Rounded type │   │  services. Value types │   │  immutable reference data. │
   │  scale, shared   │   │  in, value types out.  │   │  873 exercises ·           │
   │  components,     │   │  Zero SwiftUI imports  │   │  62 programs ·             │
   │  cross-cutting   │   │  (except @MainActor    │   │  67 comparisons.           │
   │  modifiers.      │   │  store-touching glue). │   │  Loaded once, `Sendable`.  │
   │  No feature      │   │                        │   │  Injected via              │
   │  knowledge.      │   │  Domain/AI/ isolates   │   │  @Environment.             │
   │                  │   │  every model seam.     │   │                            │
   └──────────────────┘   └───────────┬────────────┘   └────────────────────────────┘
                                      │ reads / writes
                                      ▼
   ┌────────────────────────────────────────────────────────────────────────────────┐
   │  MODELS                     15 SwiftData @Model classes + ReplogStore:          │
   │  Models/                    the schema, the container factories, every          │
   │                             fetch-or-create singleton and query helper.         │
   │                             Free of business rules, so the schema stays stable. │
   └────────────────────────────────────────────────────────────────────────────────┘
```

### What lives where, and why it's grouped that way

| Layer | Holds | Why it is its own layer |
|---|---|---|
| `App/` | Entry, root, tabs, nav routes, environment, debug seeding | The **composition root**. The only place that knows about all features, so features never learn about each other. |
| `Features/` | One folder per screen | **Vertical slices.** Everything for a screen is co-located; a new engineer opens one folder and is productive. |
| `Domain/` | Pure rules, use-case services, the AI seams | The **brain**. `static` functions over value types → deterministic, millisecond tests, ≥80 % coverage without a simulator. |
| `Catalog/` | Exercises, programs, comparisons, image loading | **Read-only reference data.** It never mutates and loads once, so it is effectively an in-memory read repository. Decoupling it from user data means the dataset can be rebuilt with no migration. |
| `Models/` | The SwiftData graph + store helpers | The **persisted entities** and the persistence seams, kept free of rules so the schema is boring and serialisable. |
| `DesignSystem/` | Tokens + reusable components | One visual language. Change a token, restyle the app. Components have no feature knowledge, so they're independently previewable. |

---

## 5. Design patterns, and why these ones

### 5.1 MV + selective MVVM — not "MVVM everywhere"

SwiftUI is already a reactive Model-View system: `@Query`, `@Bindable` and `@Environment` bind the
view straight to state. A view model is added **only where a screen owns genuine state or logic**.

```
   Genuinely owns state → gets a VM              Just derives from @Query → stays in the View
   ────────────────────────────────              ────────────────────────────────────────────
   LibraryViewModel     query + 6-facet filter   TodayView.streak       = StreakEngine.…(plans)
   OnboardingViewModel  13-step machine, async   PlanDetailView         computed card rows
   RestTimerModel       countdown + ring state   ProfileView.trainingReports
```

**`@Query`/`@Bindable` never leave the View** — that's Apple's guidance, and view models can't host
`@Query` anyway. Persistence *writes* go through pure Domain services (`SessionBuilder`,
`SessionFinisher`, `PlanFactory`, `TemplateWriteBack`) that the view or VM calls.

Reactive state uses **Observation** (`@Observable`, `@Bindable`) rather than
`ObservableObject`/`@Published` — less boilerplate, finer-grained invalidation.

### 5.2 Functional core, imperative shell

Business operations are `enum` namespaces of `static` functions with explicit inputs and outputs and
no hidden state:

```swift
enum SessionFinisher   { static func finish(_:profile:context:date:saveAdditions:) -> Summary }
enum StreakEngine      { static func workoutStreak(scheduledDays:doneDates:today:calendar:) -> Int }
enum ProgressionEngine { static func recommend(exId:history:goal:units:targetRPE:) -> …? }
enum BadgeEngine       { static func progress(_:in:) -> Progress }
```

The pure core is wrapped by a thin imperative shell (the views that fetch and save). This is the
single biggest lever on coverage — which is why the logic layer sits at ≥80 % with no UI tests.

### 5.3 In-memory read repository (`ExerciseCatalog`, `ProgramCatalog`, `ComparisonCatalog`)

Each loads its dataset once, exposes `byID` lookups and query methods, fails **soft to empty** on a
missing or malformed resource, and is `nonisolated final class … : Sendable`. Features depend on the
*queries*, never on JSON decoding.

### 5.4 Dependency injection through the SwiftUI Environment

The container and the catalog are provided at the composition root and read with `@Environment`.
Previews and tests inject `ReplogSchema.inMemoryContainer()` or `ExerciseCatalog(exercises:)`
trivially. The only deliberate global is the image cache.

### 5.5 Graceful degradation (Strategy), everywhere a model is involved

Every model seam has a deterministic understudy that produces the **same output type**:

```
   AIPlanService.generate  ──►  live 2-stage model  ──fails──►  ProgramMatcher top pick
                                                     ──fails──►  legacy PlanGenerator split
   CoachVoice.reword       ──►  live reword          ──fails──►  the deterministic body, verbatim
   CoachEngine             ──►  (never uses a model at all — it IS the decision)
```

The engine that actually ran is recorded on the result (`usedAppleIntelligence`).

### 5.6 Lenient decoding as a policy

`Exercise`, `WorkoutProgram`, `ProgramSlot`, `CoachingPayload`, `WeightComparison` and
`MovementPattern` all decode leniently: only truly required fields throw; unknown enum values
survive (`MovementPattern.other(raw)`, `ProgramSex.other(raw)`); a malformed row is skipped rather
than taking the whole file down. **A missing fun fact must never cost the athlete their session
summary.**

### 5.7 The `kindRaw` / `kind` pattern

SwiftData stores enums as raw strings with a typed computed accessor. Used on `Workout.dayRaw`,
`CoachingLog.kindRaw`, `UserProfile.goalRaw`, `AppSettings.unitsRaw`, `ReadinessEntry.sleepRaw`,
`SessionExercise.suggestionActionRaw`. Storage stays trivially migratable; call sites stay typed.

### 5.8 Composition over inheritance

There are no view subclasses. Screens are assembled from small components and view modifiers
(`.cardSurface()`, `.hideKeyboardOnTap()`, `.plainListRow()`, `ExerciseThumbnail`).

---

## 6. App lifecycle & navigation

```
  COLD START
      │
      ▼
  ┌──────────────────────────────────────────────────────────────────────────────┐
  │ ReplogApp.init()                                                             │
  │                                                                              │
  │  1. ReplogSchema.container()   creates Application Support if missing;       │
  │                                on a corrupt/incompatible store wipes it once │
  │                                and retries; last resort = in-memory, so the  │
  │                                app ALWAYS launches.                          │
  │  2. context.userProfile() + .appSettings()   ← bootstrapped HERE, not in a   │
  │                                view body (mutating during body would thrash  │
  │                                rendering and flash a blank screen).          │
  │  3. SessionAttributionBackfill.run   ⚠ ORDER MATTERS. This stamps history    │
  │  4. TemplateBackfill.run              with its workout+plan; the template    │
  │                                       repair reads history *per plan*. Run   │
  │                                       the other way round and every plan     │
  │                                       looks like it has no history at all.   │
  │  5. context.syncCustomExercises()    merge user exercises into the catalog   │
  │  6. BadgeAwarding.award()            idempotent: two years of prior training │
  │                                      must not open to an empty cabinet.      │
  └───────────────────────────────────┬──────────────────────────────────────────┘
                                      ▼
  ┌──────────────────────────────────────────────────────────────────────────────┐
  │ RootView            .tint(.accent) · .preferredColorScheme(darkMode)         │
  │                     .fullScreenCover(item: first session where isOpen)       │
  │                       └─ dismissed by swipe ⇒ isOpen = false (PAUSE,         │
  │                          never destroy — only Finish deletes a session)      │
  └───────────┬──────────────────────────────────────┬───────────────────────────┘
     onboardingDone == false                onboardingDone == true
              │                                      │
              ▼                                      ▼
   ┌────────────────────┐         ┌─────────────────────────────────────────────┐
   │ OnboardingFlow     │────────►│ MainTabView — 5 tabs, each its own          │
   │ 13 steps + spinner │ finish  │ NavigationStack                             │
   │ + result + report  │         │                                             │
   └────────────────────┘         │  🏠 Today   📚 Plans   📖 Library           │
                                  │  📈 Progress   👤 Profile                   │
                                  └─────────────────────────────────────────────┘

  scenePhase → .active
      ├─ ReportScheduler.runOnActivation(context:)   publish any due weekly/monthly report
      └─ NotificationCoordinator.refresh(context:)   re-plan local notifications
```

> **Why five tabs and no Calendar tab.** An iPhone tab bar holds five; a sixth folds into a system
> "More" list. The Progress dashboard owns the fourth slot and the Calendar lives one tap inside it.

> **There is no `BGTaskScheduler` path.** Reports are read in-app, and opening the app always runs
> `runOnActivation`, so a background task would add a Background Mode / Info.plist surface for zero
> user-visible gain — and iOS might never run it anyway.

---

## 7. The data model — the "onion"

15 `@Model` types, registered in `ReplogSchema.models`. Cascade deletes mean removing a plan removes
its whole subtree.

```
  ══ THE TEMPLATE ═════════════════════════════════════════════════════════════════════
   Plan ──┬─< Workout ──< PlanItem ──< SetTemplate
          │   name, day/isExtra   exId    weightKg · reps · rpe
          │   notes, order        order   estimated · updatedAt   ← §10
          │                       restSeconds?
          │
          ├ id · name · colorHex · order · createdAt
          ├ reportMarkdown + headline      the saved AI report, re-readable in Profile
          └ programId + progression{Type,Rule,Deload}   ← which library program built it

                        │  SessionBuilder.start(workout:) copies template → live
                        ▼
  ══ THE LIVE INSTANCE ════════════════════════════════════════════════════════════════
   ActiveSession ──< SessionExercise ──< LoggedSet
    workoutId ·         exId · order          weightKg · reps · rpe · done
    planId ·            doneOrder             prevWeight/prevReps  → trend arrows
    startedAt ·         restSeconds?          estimated            → the "est" badge
    isOpen ·            suggestion{…}
    readinessNote       suggestionDismissed

                        │  SessionFinisher.finish() — the session is DELETED
                        ▼
  ══ THE IMMUTABLE RECORD ═════════════════════════════════════════════════════════════
   HistoryEntry   exId · date(= session START) · topW · topR · e1rm · topRPE · setsJSON
                  sessionId · workoutId · planId · workoutName · planName · durationSeconds

  ══ SINGLETONS ═══════════════   ══ FLAT, QUERYABLE RECORDS ═══════════════════════════
   UserProfile                     CoachingLog     the coach's durable memory (kind,
     name · goal · streak                          summary, payload JSON, bodyMarkdown)
     weekStreak · doneDates         BodyweightEntry one per calendar day
     onboardingDone                 ReadinessEntry  one per calendar day
     totalWorkouts                  BadgeAward      badgeId + the context it was won in
   AppSettings                      CustomExercise  user-created, merged into the catalog
     units · darkMode                               (@Attribute(.externalStorage) photos)
     restTimerAuto · restSeconds
     notification prefs · backfill versions
```

### The three lives of a number

`PlanItem`/`SetTemplate` are the **template**. `SessionExercise`/`LoggedSet` are the **live
instance**. `HistoryEntry` is the **immutable record**. Templates reference the static catalog only
by `exId`, so user data and reference data are fully decoupled and the catalog can be re-tuned with
no migration.

### The design decisions worth understanding

| Decision | Why |
|---|---|
| **`HistoryEntry.date` is the session's *start*.** | A workout begun at 23:00 and finished at 00:15 belongs to the 23:00 day. This is also what makes an early-bird/night-owl badge mean anything. |
| **`planId` on history is the scope key.** | Bench at 100 kg in a strength block must not rewrite the 70 kg in a hypertrophy plan. Carry-forward, progression and stall detection read `history(forExercise:inPlan:)`. A row with `planId == nil` deliberately influences no plan. |
| **`SetTemplate.updatedAt`, not `estimated`, gates write-back.** | `estimated` is informational. Manually-added sets leave it `false`, so gating on it silently skipped most real plans. `updatedAt` asks the honest question: has anything deliberately set this number since the athlete last lifted it? |
| **Ids, not relationships, on the memory records.** | `CoachingLog.planId`, `BadgeAward.planName`, `ActiveSession.workoutId` are plain values, so the memory **outlives** the plan or exercise it concerns. Names are captured at the time, so a later rename can't rewrite history. |
| **JSON in a String column** (`setsJSON`, `payloadJSON`) | Structured detail that is read on demand and never queried on. Decoded through a computed property; lenient, so a bare `{}` decodes to empty rather than throwing. |
| **`Orderable` everywhere.** | Every level carries `order`. Appends allocate `Reordering.nextOrder(after:)` — **never `collection.count`**, which collides after a delete and makes the sort unstable. |
| **Awards are never revoked.** | A badge earned is earned. `BadgeAwarding` only ever inserts. |

### `Workout.isExtra` — the day-less workout

An "Extra" is run on any day. Extras never join `scheduledDays` (so they can't create a streak
obligation), never lock a weekday in the picker, never claim the Today hero, and lead the "Add
another" shelf. The 8th workout of a full week is created as one.

---

## 8. The reference catalogs

Three bundled, read-only datasets. All three fail soft to empty.

```
  ┌──────────────────────────┐  ┌──────────────────────────┐  ┌───────────────────────┐
  │ ExerciseCatalog          │  │ ProgramCatalog           │  │ ComparisonCatalog     │
  │ exercises.json  1.0 MB   │  │ programs.json   319 KB   │  │ comparisons.json 25KB │
  │                          │  │                          │  │                       │
  │ 873 exercises from the   │  │ 62 curated programs      │  │ 36 objects            │
  │ Free Exercise DB         │  │  11 hypertrophy          │  │ 19 animals            │
  │ + 1 746 HEIC photos      │  │  10 sport conditioning   │  │ 12 strength feats     │
  │                          │  │   9 strength             │  │                       │
  │ facets: level · equip ·  │  │   8 endurance            │  │ turns a tonnage into  │
  │ force · category ·       │  │   7 general fitness      │  │ a picture:            │
  │ mechanic · primary +     │  │   5 fat loss  … etc      │  │ "that's three Smart   │
  │ secondary muscles        │  │                          │  │  cars"                │
  │                          │  │ each: audience gates,    │  │                       │
  │ + the user's own         │  │ days[]→slots[], science  │  │ animal figures are    │
  │   CustomExercise rows,   │  │ rationale, evidence,     │  │ hedged ("reportedly") │
  │   merged in via          │  │ progression, cautions,   │  │ — folklore is never   │
  │   `setCustom` (lock-     │  │ medical disclaimer       │  │ stated as fact        │
  │   guarded, Sendable)     │  │                          │  │                       │
  └──────────────────────────┘  └──────────────────────────┘  └───────────────────────┘
```

### Custom exercises are first-class

A `CustomExercise` row is merged into `ExerciseCatalog` at launch and after every create/delete, so
it resolves by `exId` **exactly** like a bundled entry — usable in workouts, the live log, Progress,
badges and bodyweight detection. Deleting one purges every `PlanItem` and `SessionExercise` that
references it, but **preserves finished history**: that's a factual record of training that happened.

### Image bundling — the flat-name rule

Xcode flattens synchronized-group resources into the bundle root. Every exercise in the source DB
has `0.jpg`/`1.jpg`, which would collide, so `Scripts/build-exercise-db.sh` emits flat unique names:

```
   source:   Battling_Ropes/0.jpg     →     bundled:  Battling_Ropes__0.heic
   Exercise.imageResourceNames rebuilds these; ExerciseImageView resolves via Bundle.main.
   HEIC · ~420–520 px · q42–50 · 1 746 photos ≈ 18 MB
```

> **The image layout rule.** `ExerciseImageView` uses `Color.clear.overlay { image }.clipShape(…)`
> so a `.fill` image is constrained to *and cropped by* its frame. **Never** wrap a `.fill` image in
> a bare `ZStack` + frame — it overflows, and any border overlay then lands on a mismatched, inset
> rect. That was the old "white square on the thumbnail" bug. One frame → one clip → one hairline,
> all on the same rect.

`.fill` for thumbnails (uniform square crop, via `ExerciseThumbnail`); `.fit` for the detail hero,
so no part of the movement is ever cropped away.

---

## 9. Planning: from quiz to plan

Plan generation is **program-driven**: nothing is invented from scratch. The model chooses from real,
curated programs, and then chooses real catalog exercises to fill them.

```
 ONBOARDING (13 steps; name asked LAST, first name only)
 welcome → goal → [sport] → experience → gender → age → height → weight
         → days/week → minutes/session → injuries → equipment access → equipment types → name
                                              │
                                              ▼  QuizAnswers  →  MatchContext
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │ ① ProgramMatcher.rank()          62 programs → a gated, scored shortlist                │
 │                                                                                         │
 │   HARD GATES (drop entirely)              SOFT SCORING (rank the survivors)             │
 │   ────────────────────────────            ─────────────────────────────────             │
 │   equipment you don't have          ✗     sport match          +100  (GPP fallback +40) │
 │   age outside the audience band     ✗     goal token overlap    +12 each                │
 │   a different sport's program       ✗     days/week fit         +20 − 7·gap             │
 │   an unmet prerequisite             ✗     experience fit        +18                     │
 │   a medical disclaimer (auto-pick)  ✗     sex-focus nudge       +15 / +8  (NEVER a gate)│
 │                                                                                         │
 │   Equipment convention: bodyweight + calisthenics staples always pass; app-modelled     │
 │   strength gear gates strictly; cardio gear the app can't model stays permissive.       │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │  top 5 auto-pickable
                                              ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │ ② FRAMING CALL  (Apple Intelligence, temperature 1.0, @Generable ProgramFraming)        │
 │                                                                                         │
 │   in:  the numbered shortlist + the athlete's profile + AthleteContext (their REAL      │
 │        logged training, token-budgeted — see below)                                     │
 │   out: chosenProgramNumber · justification · headline · philosophy · whyThisSplit ·     │
 │        scienceNotes · safetyNotes · encouragement                                       │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │  one chosen program, N days
                                              ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │ ③ PER-DAY SELECTION CALLS  (one per day, @Generable DaySelection)                       │
 │                                                                                         │
 │   For each ProgramSlot the day prescribes:                                              │
 │     PatternMapping.candidates(pattern, slotMuscles, allowedEquipment, avoidMuscles)     │
 │       └─ MovementPattern → catalog facets (category · force · mechanic · muscles ·      │
 │          name keywords) → up to 5 REAL exercises, de-duplicated across the day          │
 │                                                                                         │
 │   The model picks one candidate NUMBER per slot and gives a reason.                     │
 │   ProgramPlanBuilder.resolveDay VALIDATES each pick against that slot's candidate set;  │
 │   an invalid or missing pick silently falls back to the slot's top candidate.           │
 └─────────────────────────────────────────────────────────────────────────────────────────┘
                                              │
                                              ▼
                    GeneratedPlan  →  PlanFactory.insert  →  SwiftData Plan
                    PlanReport     →  ReportComposer.markdown  →  Plan.reportMarkdown
```

### The fallback ladder

```
   Apple Intelligence available?  ──no──►  ┐
   Framing/selection call threw?  ──yes─►  ├──► programFallback(shortlist[0])
   Chosen program has no days?    ──yes─►  ┘       ProgramPlanBuilder with NO picks:
                                                   every slot takes its top candidate.
                                                            │  still empty?
                                                            ▼
                                                   legacyFallback → PlanGenerator
                                                   (the original deterministic split engine)
```

`ProgramPlanBuilder` is the **shared spine**: the live path and the deterministic path run the same
resolver, so a program-driven plan exists with or without a model. `Result.usedAppleIntelligence`
records which ran. Unresolvable slots (a swim slot with no catalog match) are skipped; a day with no
resolvable slots is dropped.

### Slot rep/time convention (`RepScheme`)

The library authors reps as prose, so the parser is lenient and always returns a usable target:

| Slot `reps` | Parsed as |
|---|---|
| `"5"`, `"8-12"` | the **lower bound** — start there, earn the top of the range, *then* add load (double progression) |
| `"10/side"`, `"12-15 each"` | the per-side count, flagged `isPerSide` |
| `"30-60s"`, `"3 min"` | the **duration in seconds** (lower bound, minutes ×60, clamped ≤600), stored in `reps` and flagged `isTimed` — `SetTemplate` has no duration field |
| `intensity: "RPE 8"` / `"RPE 7-9"` | 8 / the harder bound; otherwise a level default (7/8/9) |
| anything unparseable | 10 reps |

### Grounding the model

Two pure mechanisms keep the on-device model (≈4 096-token window) honest:

- **`CoachingKnowledge.grounded(_:)`** prepends a curated exercise-science cheat-sheet to every
  system prompt. This is the practical way to "feed science" into a small on-device model — distil
  principles, don't dump papers.
- **`AthleteContext`** digests the athlete's real logged training (trailing 56 days, top 10 lifts by
  session count) into per-lift lines and weekly sets-per-muscle. **`PromptBudget`** estimates tokens
  at ~3.5 chars/token and `promptSection(maxTokens:)` drops the least-relevant lifts until the
  section fits. The framing prompt trims *candidates* first (never below 3), then trims history.

---

## 10. Loads, progression & the feedback loop

**Starting weights are never hardcoded.** Program slots carry only sets/reps/RPE; the absolute
kilogram is computed, then corrected by what the athlete actually lifts.

### 10.1 The estimate (`StartingLoadEstimator`)

```
   bodyweight-relative untrained-MALE 1RM anchor, per movement pattern
     lower compound 0.70 × BW   ·  upper push 0.45 × BW
     upper pull     0.42 × BW   ·  isolation  0.15 × BW      (rounded DOWN from published bands)
            │
            ▼  Epley inverse: the load leaving (10 − RPE) reps in reserve at the target reps
     refWorking = base1RM / (1 + repsToFailure/30)
            │
            ▼  × sex coefficient — applied to the ESTIMATE ONLY, never to a progression rate
     female upper 0.55 · female lower 0.68     (the ~2× upper/lower gap is the key finding:
     unspecified   0.775 / 0.84                 Bishop et al. 1987 · Miller et al. 1993)
            │
            ▼  × experience   beginner 1.0 · intermediate 1.4 · advanced 1.8
            ▼  × age taper    ≥60 → 0.90 · ≥70 → 0.80
            ▼  ÷ 2 for dumbbells (load per hand)
            │
            ▼  ROUND to a real increment, with a floor
     barbell → 2.5 kg steps, never below the 20 kg empty bar
     dumbbell → 1 kg under 10 kg, else 2.5 kg   ·  machine → 5 kg  ·  cable → 2.5 kg
     bodyweight → 0 kg and "progress by reps or a harder variation"
            │
            ▼
     LoadEstimate{ kg, isBodyweight, note }   flagged `estimated` → the "est" badge in the log
```

Seeds deliberately **err low**, because the correction is fast and upward is safer than downward.

### 10.2 The correction (`LoadCalibrator`) — a bad seed self-corrects in 1–2 sessions

```
   You logged 40 kg × 8 and tapped RPE 6, but the plan wanted RPE 8.
        │
        ▼  RIR-adjusted Epley: RPE 6 ⇒ 4 reps in reserve ⇒ really 12 reps from failure
   inferred e1RM = 40 × (1 + 12/30) = 56 kg
        │
        ▼  the load that hits RPE 8 at 8 reps ⇒ 10 reps from failure
   working  = 56 / (1 + 10/30) = 42 kg  →  snapped to the stepper ⇒ 42.5 kg
```

`ProgressionEngine` runs this **only** after the first logged session of a lift and only when the
felt RPE is ≥2 off target — then the double-progression rules take over. Because the RPE scale
saturates at 10, a wildly heavy seed converges over two sessions rather than one; another reason the
estimator errs low.

### 10.3 The next-session prescription (`ProgressionEngine`) — first match wins

| # | Condition | Action |
|---|---|---|
| 0 | First session, felt RPE ≥2 off target | **Calibrate** (§10.2) |
| 1 | Bodyweight lift (`topW == 0`) | Reps are the only lever → **add a rep**, or **hold** if reps stalled |
| 2 | Top of the rep range reached | **Add load** (+1 step), rebuild from the range floor |
| 3 | e1RM dropped 2 sessions in a row | **Deload** ~10 %, snapped, always strictly lower |
| 4 | No e1RM improvement across 3 sessions | **Deload** ~10 % |
| 5 | The latest session alone dipped | **Hold** — one down session is noise, not a trend |
| 6 | otherwise | **Add a rep** (double progression) |

Rep ranges come from the goal: build muscle / recomp `8…12`, lose weight `12…15`, sport `6…10`.

### 10.4 The long-horizon eye (`StallDetector`)

Where `ProgressionEngine` prescribes the next session, `StallDetector` watches the trailing trend
and writes to the coach's memory **once per stall**:

```
   deload first  ──►  still stuck after a back-off  ──►  swap the exercise
                                                          (same primary muscle, same equipment,
                                                           ranked by mechanic then level)
```

A ≥5 % session-over-session top-weight drop reads as a *deliberate back-off*, so a rebuild in
progress is never reported as a stall. A bodyweight lift has no load to shed, so its only remedy is
`.swapExercise`.

### 10.5 The loop closes: `TemplateWriteBack`

A plan's templates are the athlete's **current working numbers**, not a frozen prescription.

```
   Fully complete session  ──►  write the logged weight/reps back onto the plan's SetTemplates
                           ──►  propagate WITHIN THE PLAN to every workout prescribing that lift
                                (train bench Monday, and Thursday's bench starts from it)
                           ──►  NEVER across plans (that's a different program, different loads)

   Partial session → no write-back. A partial finish is not evidence the prescription changed.
   Surplus templates are left alone, so a readiness-trimmed session can't permanently shrink a plan.
```

> **Known caveat, documented in the source:** a plan that deliberately prescribes the same lift at
> two intensities (heavy 100×5 Monday, volume 70×12 Thursday) will have the volume day overwritten,
> because within one plan the last log wins. Split across two plans, or use different variations.

### 10.6 What a bodyweight set is worth (`BodyweightLoad` + `LoadResolver`)

A pull-up moves nearly all of you; a crunch lifts your head and shoulders. Logging both as "0 kg"
made every calisthenics set worth **nothing** — no tonnage, no e1RM, no PR, no place in Strength.

```
   ┌──────────────────────────────────────────────────────────────────────────────────┐
   │ BodyweightLoad.factor(for:)   a keyword/family table over the catalog, grounded   │
   │   in force-plate GRF work (Ebben 2011 · Gouvali & Boudolos 2005) and Dempster /   │
   │   de Leva segment masses: head+neck ~8 % BW · head-arms-trunk ~68 % · legs ~32 %  │
   │   Values deliberately err LOW — under-crediting is a smaller lie.                 │
   │   Stretching and cardio are EXCLUDED (a hamstring stretch is not tonnage; that    │
   │   exclusion covers 85 of the catalog's 188 equipment-free entries).               │
   └──────────────────────────────────────────────────────────────────────────────────┘
                                        │
   ┌────────────────────────────────────▼─────────────────────────────────────────────┐
   │ LoadResolver — the ONE place the app decides what a recorded set loaded.          │
   │   effectiveKg = addedKg + factor × bodyweight-at-that-date                        │
   │   timed holds → rep-equivalents at 3 s each                                       │
   │                                                                                   │
   │   Resolved at READ time, never baked into HistoryEntry. Three consequences,       │
   │   all deliberate: old sessions are credited retroactively with NO migration;      │
   │   re-tuning the table re-values the past automatically; and the stored `e1rm`     │
   │   stops being the source of truth for analytics.                                  │
   └───────────────────────────────────────────────────────────────────────────────────┘
```

Historical tonnage is credited at the bodyweight the athlete **was**, not the one they are now
(`BodyweightResolver`). Relative-strength ratios use the *heaviest* weigh-in ever recorded, so a
ratio can never be inflated by having stepped on the scale light once.

---

## 11. The live session

```
   TAP START
       │
       ├─► (optional) ReadinessCheckInSheet — three one-tap ratings, never blocking
       │        "Skip" starts untouched · "Start" applies the modulation + records the check-in
       │
       ▼
   SessionBuilder.start(workout:into:readiness:)
       │  for each PlanItem, in order:
       │    • history = context.history(forExercise:inPlan:)   ← SCOPED TO THIS PLAN
       │    • suggestion = ProgressionEngine.recommend(…, targetRPE: template.rpe)
       │      (stored on the SessionExercise, so it survives pause/resume)
       │    • for each SetTemplate:
       │        seed = template.supersededBy(lastSession.date) ? lastSession's set : template
       │        prevWeight/prevReps = the SAME SET INDEX last session   → trend arrows
       │        estimated = template.estimated && seed == nil           → the "est" badge
       │
       │  readiness reduces volume?  → delete the LAST set of each multi-set exercise
       │                               + store a plain-language reason on session.readinessNote
       ▼
   ┌──────────────────────────────────────────────────────────────────────────────────┐
   │ ActiveWorkoutView (full-screen cover)                                            │
   │                                                                                  │
   │   running timer  ·  optional rest-timer ring in the header                       │
   │   ┌───────────────────────────────────────────────────────────────┐              │
   │   │ ExerciseLogCard                                               │              │
   │   │  ┌ SuggestionBanner — the coach's prescription + its REASON.  │              │
   │   │  │  "Apply" copies onto UNCOMPLETED sets only; swipe = never  │              │
   │   │  │  show again this session. User input is never overwritten. │              │
   │   │  ├ SetLogRow × n  — tap to edit inline (NumericStepperField)  │              │
   │   │  │  ▲▼ trend arrows vs the same set index last session        │              │
   │   │  │  "est" badge while the weight is still a computed seed     │              │
   │   │  └ Add set · swipe-to-delete                                  │              │
   │   └───────────────────────────────────────────────────────────────┘              │
   │   finished exercises spring to the bottom (doneOrder)                            │
   │                                                                                  │
   │   Completing ANY set (re)starts the rest timer when restTimerAuto is on OR a      │
   │   timer is already running — so checking a set resets the live countdown.         │
   │                                                                                  │
   │   Every set done → CelebrationOverlay (native confetti + success haptics)         │
   └──────────────────────────────────────────────────────────────────────────────────┘
       │
       ├─ "X"  → isOpen = false   PAUSED and persisted; Today shows "Continue"
       │
       ▼ FINISH
   SessionFinisher.finish(session:profile:context:date:saveAdditions:)
       │  loggedDate = session.startedAt  (a 23:00 session finished at 00:15 is a 23:00 workout)
       │  duration   = now − startedAt    (captured BEFORE the session is deleted)
       │
       │  per exercise with ≥1 completed set:
       │    top set = max by e1RM, REPS BREAK THE TIE  ← every bodyweight set scores e1RM 0, so
       │              ranking on e1RM alone let a 5-rep warm-up be recorded as the top set of a
       │              12-rep session, hiding a real PR
       │    → insert HistoryEntry (stamped with sessionId · workoutId · planId · names · duration)
       │    → StallDetector.detectAndRecord(...)
       │
       │  fully complete only:
       │    → TemplateWriteBack.applyIfComplete   (§10.5)
       │    → profile.totalWorkouts += 1 ; mark the day done
       │  always:
       │    → context.recomputeStreaks  →  delete the session  →  save
       ▼
   CoachDebriefView  →  BadgeCelebrationOverlay (if anything landed)
```

An **incomplete** finish offers "Save for later" (the same pause path) alongside "Finish anyway";
finishing anyway still saves history but warns, and does not count toward streaks.

---

## 12. The coach

On-device, explainable, and structurally incapable of inventing a number.

```
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │ CoachContextBuilder    @MainActor glue: reads the store into a plain value type  │
   │                        (goal · units · justFinished · historyByExercise ·        │
   │                         streaks · bodyweight · readiness pattern · deload rule)  │
   └───────────────────────────────────┬─────────────────────────────────────────────┘
                                       ▼
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │ CoachEngine.insights(ctx) -> [CoachInsight]    PURE · DETERMINISTIC · SORTED     │
   │                                                                                 │
   │   sessionDebrief   volume vs last time + a picture of the tonnage + the next-    │
   │                    session recommendation, quoting ProgressionEngine's reason    │
   │   stallAlert       from StallDetector — at most ONE at a time (longest-running)  │
   │   adherence        a scheduled workout still undone, streak on the line          │
   │   milestone        PRs · streak milestones {3,5,7,10,14,21,30,50,75,100} ·       │
   │                    every 4th completed program week                             │
   │   bodyweightTrend  direction + weekly rate, judged FOR the athlete's goal        │
   │   readinessTrend   a recurring weekly pattern (3 low-sleep days, …)              │
   │   checkInPrompt    a weigh-in is due                                             │
   │   welcome          only when nothing else applies and there's no history at all  │
   │                                                                                 │
   │   sort: priority DESC (urgent > high > normal > low), ties by kind.sortRank      │
   └───────────────────────────────────┬─────────────────────────────────────────────┘
                                       ▼
   ┌─────────────────────────────────────────────────────────────────────────────────┐
   │ CoachVoice.reword(_:)   OPTIONAL Apple Intelligence pass, temperature 0.6        │
   │                                                                                 │
   │   "Rephrase ONLY its wording … Never change the numbers, the recommendation,     │
   │    or the meaning — do not invent anything. Keep it under 45 words."             │
   │                                                                                 │
   │   Only `body` may change. title, metrics and tags are untouched. Unavailable or  │
   │   erroring or empty → the deterministic body, VERBATIM.                          │
   └───────────────────────────────────┬─────────────────────────────────────────────┘
                                       ▼
     ┌──────────────────┐   ┌────────────────────┐   ┌──────────────────────────────┐
     │ Post-Finish      │   │ Today "Coach" card │   │ Profile → Coach Insights     │
     │ debrief sheet    │   │ top insight only,  │   │ grouped by period or kind    │
     │ (all insights)   │   │ ≤1 per day,        │   │ (CoachInsightFeed)           │
     │                  │   │ dismissible        │   │                              │
     └──────────────────┘   └────────────────────┘   └──────────────────────────────┘
```

### The coach's durable memory

Every surfaced insight, detected stall, recommended deload and published report is written to
`CoachingLog` — a dated, typed, id-referenced note that outlives the plan it concerned.
`CoachInsightFeed.shouldRecord` keeps the log honest: four copies of "3-day streak!" in a row say
nothing the first one didn't.

### Narrative reports

`WeeklyReportComposer` and `MonthlyReportComposer` are pure markdown compositions — adherence, sets
and volume, new records, bodyweight trend, plus (monthly) one key insight and one recommended
adjustment. `ReportScheduler.runOnActivation` publishes any report whose period boundary has passed,
idempotently, once per period. They surface under Profile → **Training Reports**, rendered by
`CoachReportView` (a lightweight line-based markdown renderer: `#`/`##`, `- ` bullets, `> ` callouts,
paragraphs).

### Notifications — capped and respectful

`NotificationPlanner` is pure and decides *what*; `NotificationScheduler` is the thin
`UNUserNotificationCenter` boundary that talks to the OS. The rules are enforced in the pure layer so
they're unit-testable:

```
   master switch off               → nothing, ever
   per-kind toggles                → streakRisk · workoutReminder · reportReady · checkInDue
   AT MOST ONE per calendar day    → highest priority wins (streakRisk 3 > reminder 2 > … )
   quiet hours (default 21:00–09:00) → never fires inside them; shifted to the next open time
   copy is always encouraging      → never guilt-based
```

### Readiness modulation

Three one-tap ratings at session start (sleep · soreness · stress, each good/moderate/poor) sum to a
fatigue load 0–6, which maps to: train as planned · cap intensity with a note · trim the last set of
each multi-set exercise. The reason is stored on the session in plain language ("Trimmed a set today
— you reported poor sleep"). `ReadinessModulator.recentPattern` spots a recurring weekly pattern for
the coach.

---

## 13. Streaks & the calendar

Streaks are **schedule-aware over binary days**. A day is *done* when **any** workout was fully
completed that day — whichever weekday it was assigned to, or a day-less Extra. Finishing twice
still counts once.

```
   WORKOUT STREAK  (StreakEngine.workoutStreak)
   walk back from today:
     ┌─ done day?                       → +1, keep walking
     ├─ past SCHEDULED day, nothing done → BREAK
     ├─ rest day, nothing done           → pass through silently
     └─ TODAY still due                  → grace, not a miss
   Empty schedule (extras only) ⇒ every day is "expected" ⇒ plain consecutive done days.

   WEEK STREAK  (StreakEngine.weekStreak)   consecutive "perfect weeks"
     current week: +1 if every ELAPSED scheduled day is done and ≥1 has been.
                   A missed elapsed day ⇒ the whole streak is 0.
     prior weeks:  each counts only if ALL its scheduled days were completed.
   Extras on rest days boost the workout streak but can't perfect a week.
```

Weeks are **Sunday-first everywhere, regardless of locale**, so the Today strip, `StreakEngine`,
`CalendarMath` and the Progress week buckets all agree.

### The Calendar (inside Progress, pushed with `embedded: true`)

```
   ┌────────────────────────────────────────────────────┐
   │  streak header                                     │
   ├────────────────────────────────────────────────────┤
   │  Su Mo Tu We Th Fr Sa   ← horizontally PAGED months│
   │  ·  ·  1  2  3  4  5      fixed 42 cells (6×7) so  │
   │  6  7  8  9 10 11 12      month heights never jump │
   │ 13 14 ●15 16 ○17 18 19    ● accent fill = trained  │
   │ 20 21 22 23 24 25 26      ○ ring       = today     │
   │ 27 28 ·29 ·30 ·31 ·  ·    · dot        = scheduled │
   ├────────────────────────────────────────────────────┤
   │  tap a day        → DayDetailView (set-by-set)     │
   │  long-press-drag  → RangeSummaryView               │
   │                     totals + per-training-day      │
   │                     averages (CalendarStats)       │
   └────────────────────────────────────────────────────┘
```

> **`DragSelectGesture` is a real UIKit `UILongPressGestureRecognizer`**, bridged via
> `UIGestureRecognizerRepresentable`. A SwiftUI `LongPressGesture` would win the touch race against
> the scroll views without arbitrating; the UIKit recognizer participates in the system's
> arbitration, so scrolling and month-paging win when the finger moves early and the press wins only
> on a genuine hold. Same lesson as `DragToReorder` (§19).

---

## 14. Progress — the four-layer onion

The fourth tab. Every layer answers the question the layer above it raised.

```
  ┌─ L1 · ProgressHomeView ─────────────────────────────────────────────────────────┐
  │   Calendar push card                                                            │
  │   ┌───────────────┐ ┌───────────────┐ ┌───────────────┐                         │
  │   │ STRENGTH hero │ │ VOLUME        │ │ MUSCLE BALANCE│  each = a glanceable    │
  │   │ e1RM lines    │ │ weekly bars   │ │ donut         │  headline + mini chart  │
  │   └───────────────┘ └───────────────┘ └───────────────┘                         │
  │   ┌───────────────┐ ┌───────────────┐                                           │
  │   │ CONSISTENCY   │ │ BODY          │                                           │
  │   └───────────────┘ └───────────────┘                                           │
  └───────────────────────────────────┬─────────────────────────────────────────────┘
                                      ▼  each card drills in, with a RangePicker window
  ┌─ L2 · domain screens ───────────────────────────────────────────────────────────┐
  │  StrengthDetailView    e1RM per lift · the PR feed · every trained exercise      │
  │  VolumeDetailView      weekly tonnage · totals & averages · rep-range mix        │
  │  BalanceDetailView     the donut · push/pull split · every muscle's share        │
  │  ConsistencyDetailView adherence per week · both streaks · scheduled vs done     │
  │  BodyDetailView        bodyweight trend & rate · relative strength · readiness   │
  └───────────────────────────────────┬─────────────────────────────────────────────┘
                                      ▼  "which movements is that made of?"
  ┌─ L3 · one thing, opened up ─────────────────────────────────────────────────────┐
  │  MuscleDetailView · ExerciseDetailView(Progress tab) · WeekDetailView            │
  │  VolumeStatDetailView (one headline number, decomposed)                          │
  │  LoadSplitDetailView (external vs bodyweight — and it EXPLAINS the crediting,    │
  │                       because the user logged "0 kg × 12" and got charged 400 kg)│
  │  RepRangeDetailView (1–5 / 6–12 / 13+, and what each range is FOR)               │
  │  ForceSplitDetailView (push : pull ratio — the imbalance that shows up as a      │
  │                        cranky shoulder long before it shows up as a missed lift) │
  └───────────────────────────────────┬─────────────────────────────────────────────┘
                                      ▼
  ┌─ L4 · TrainingDayView ──────────────────────────────────────────────────────────┐
  │  one training day, split by session, every exercise pushing to its own history   │
  │  → tap-to-expand the individual logged sets                                      │
  └─────────────────────────────────────────────────────────────────────────────────┘
```

All of it is driven by pure `Domain/ProgressAnalytics` (week buckets, muscle shares, rep-range mix,
adherence, PR events, session grouping, tonnage by plan/workout, load splits, relative strength) with
the catalog dependency injected as a closure, so it tests without the bundle.

### Two rules the Progress tab lives by

**① One stack, one push mechanism.** Every Progress link is **value-based** (`NavigationLink(value:)`
→ `ProgressRoute`). Destination-based pushes aren't represented in the stack's path, and mixing the
two left two disagreeing sources of truth: a detail would begin to appear, the destination-based push
would re-assert over the top, and the appended value stayed in the path *for good* — seven taps on an
exercise row left seven phantom entries to walk back through.

**② `ChartDensity` — how much chart the data has earned.** A count is meaningful on session one; a
rate, a share, a delta and a trend are not — they need a denominator. Drawing them anyway is what
made Progress look broken to a new athlete: a line through one point, an average over one week that
equalled the total, a share of 100 %.

```
   .none      0 marks   →  a typed empty state. Never an axis.
   .single    1 mark    →  bars can show it; lines cannot — state the value in words
   .sparse    2–4       →  reduced chart, no axes, symbols always visible
   .full      5+        →  the chart as designed
```

Every card switches on this rather than inventing its own threshold — one tested decision instead of
a dozen scattered ones. See `PROGRESS_SPARSE_DATA.md`.

### The chart palette

`ProgressPalette` is a **monochrome accent ramp** — distinguishable opacities of the brand accent,
never a rainbow. Data viz stays on-brand.

---

## 15. Badges & medals

74 badges across 7 families, and every one of them is **drawn**, not shipped.

```
  ┌──────────────┬───────┬─────────────────────────────────────────────────────────────┐
  │ FAMILY       │ COUNT │ WHAT IT RECOGNISES                                          │
  ├──────────────┼───────┼─────────────────────────────────────────────────────────────┤
  │ Foundations  │   8   │ Sessions finished, 1 → 500                                  │
  │ Rhythm       │  16   │ Day streaks, week streaks, perfect weeks, early starts      │
  │ Strength     │  13   │ PRs, bests-in-one-session, bodyweight multiples per pattern  │
  │ Work         │  13   │ Tonnage, session tonnage, sets, reps                        │
  │ Atlas        │  10   │ Distinct exercises / muscles / equipment / categories /      │
  │              │       │ COMPOUNDS — so "exploring" isn't ten curl variations        │
  │ Craft        │   8   │ Push-pull balance, rep-range sweep, comebacks, dormant bests │
  │ Curiosities  │   6   │ HIDDEN until they happen. Early birds, night owls, weekends  │
  └──────────────┴───────┴─────────────────────────────────────────────────────────────┘
```

### The criterion is a typed enum, not a string + a loose threshold

```swift
case bodyweightMultiple(pattern: StrengthPattern, times: Double)
case pushPullBalance(withinPercent: Double, minTonnage: Double)
case earlyStart(sessions: Int, withinDays: Int)
case sessionsBefore(hour: Int, count: Int)
```

The thresholds in this file are sessions, days, weeks, kilograms, multiples of bodyweight and counts
of distinct things. A single `threshold: Double` column would let a kilogram be compared against a
week without the compiler noticing. **Every case is answerable from `BadgeSnapshot`, so a badge that
cannot be evaluated cannot be written down in the first place.**

### The pipeline

```
   BadgeAwarding.snapshot(context:)     ONE pass over history, grouped into sessions by
        │                               sessionId (falling back to the exact timestamp)
        │  A best is only a best against what came BEFORE it — the walk is in date order,
        │  and the first time a lift is logged is a BASELINE, not a record (otherwise every
        │  new movement ever tried would hand out a "personal best").
        ▼
   BadgeSnapshot   the complete, closed contract of what a badge may reason about
        │
        ▼
   BadgeEngine.progress(_:in:) -> Progress{ current, target, isBinary }
        │   isMet = current >= target · fraction = 0…1 · label = "7 / 10"
        │   A binary criterion is 0 or 1 — never a teasing 60 %.
        ▼
   BadgeEngine.upNext(...)   the closest unearned rungs, curiosities excluded
        │
        ▼
   BadgeAwarding.award(context:)   IDEMPOTENT — already-earned ids are skipped, so it runs
                                   at launch AND after every session without duplicating
```

### Why they're drawn

Fifty-odd medals as artwork would be megabytes of assets that can't be restyled and can't adapt to
dark mode. Drawn from **a shape × a motif × a palette** they are a few kilobytes of code, sharp at
any size, and a new badge costs three enum cases rather than a trip to a designer.

```
   8 shapes    circle · oval · rect · triangle · shield · hexagon · diamond · starburst
   12 motifs   chevrons · rays · bars · laurel · concentricRings · crossedBars ·
               ascendingSteps · flame · wave · grid · orbit · peak
   25 palettes bronze→steel→gold→jewel→elite, each a (plate, device, highlight) triple,
               checked for legibility on BOTH the warm cream and the near-black background
```

The **motif stays constant down a ladder** while shape and tier escalate, so a progression is
recognisable at a glance on a grid of fifty. The hex strings live in `Domain/MedalPalettes` (not the
DesignSystem) so `BadgeCatalog` can be validated without SwiftUI — a badge naming a palette that
doesn't exist would otherwise fall back to a default colour silently.

**Locked badges are shown, not hidden.** A grey silhouette with "7 / 10 workouts" under it is an
invitation; a bare locked grid reads as a list of things you have failed to do. Curiosities are the
exception — they keep a vague hint on purpose.

**The celebration is deliberately a different shape from the end-of-workout one.** That one rains
down; this one detonates outward — fireworks from several origins, a shockwave, a medal that slams in
and shakes on impact, a glint sweeping across it, and a haptic sequence timed to the visuals rather
than one buzz. A badge is rarer than a finished session, so it gets the louder moment.

---

## 16. Replog Premium — the subscription

Replog is free to download and free to use **for one calendar day** — the day of first launch.
That day is the whole product: onboard, get an AI-built programme, train, log every set, finish,
read the debrief. Nothing is withheld.

When the day ends the app becomes **read-only**. Every tab still opens, every chart still draws,
the Library stays entirely usable — but everything that *writes* asks for a subscription.

```
   ┌──────────────────────────────────────────────────────────────────────────────┐
   │  READ-ONLY (a free athlete, day expired)                                     │
   │                                                                              │
   │  Today     visible · hero button reads "Unlock to train" · coach card hidden │
   │  Plans     visible · name fields disabled · reorder off · banner explains     │
   │  Library   FULLY usable — 873 exercises, all six filter facets, every photo  │
   │  Progress  visible · every chart, every drill-down, the whole session log    │
   │  Profile   visible · subscription status · restore · legal                   │
   │                                                                              │
   │  GATED → paywall:  start a workout · log · finish · create or edit a plan     │
   │                    add an exercise · bodyweight & readiness check-ins         │
   │                    custom exercises · generate a plan with AI                 │
   └──────────────────────────────────────────────────────────────────────────────┘
```

Reading stays open deliberately. A reviewer has to be able to evaluate the app (3.1.1 / 2.1), and
somebody who logged a real workout and then cannot see it reads that as their own data being held
hostage — which is a one-star review, not a conversion.

### 16.1 The products

| | Monthly | Yearly |
|---|---|---|
| Product id | `test.Replog.premium.monthly` | `test.Replog.premium.yearly` |
| Price | $4.99 | $29.99 (**SAVE 50%**) |
| Free trial | none | **3 days**, offered only to eligible accounts |
| Service level | 2 | **1** (higher) |

One subscription group, "Replog Premium". Yearly sits at the higher service level so StoreKit
treats monthly→yearly as an **upgrade** and applies it immediately with proration it calculates
itself. **We never compute proration.** Yearly→monthly is a downgrade and defers to the renewal
date, which is why a pending plan change in practice only ever describes a downgrade.

> **No price, period or saving appears anywhere in Swift.** Every figure comes from
> `Product.displayPrice` in the athlete's own storefront, and the SAVE badge is computed from the
> two real prices by `PremiumPricing`. Guideline 3.1.2(c) — and the only way the paywall stays
> honest if a price is changed in App Store Connect without a new build.

> **The trial is advertised from eligibility, not from the product.** A product keeps its
> introductory offer attached whether or not *this* Apple Account may still take it, so reading
> the product alone shows a returning customer "3 days free, then $29.99" and then charges them
> in full. `SubscriptionStore.introEligibleTerms` asks `isEligibleForIntroOffer` and is re-read
> after every entitlement refresh, so buying the yearly plan stops the paywall offering the trial
> it just consumed. An account we cannot confirm is treated as **ineligible** — under-promising
> is the only safe direction to be wrong in, and `PlanOffer` already degrades cleanly with no
> trial (`callToAction` becomes "Subscribe Now", the disclosure drops the "free").

### 16.2 The architecture

```
  Domain/Subscription/                        ← pure, unit-tested
  ┌────────────────────┐  ┌──────────────────────┐  ┌────────────────────────┐
  │ AccessPolicy       │  │ SubscriptionSummary  │  │ PremiumPlan            │
  │ THE gate decision  │  │ every Profile string │  │ ids · savings maths    │
  │ premium/freeDay/   │  │ for every state      │  │ PlanOffer: the priced  │
  │ locked             │  │                      │  │ plan the paywall reads │
  └────────────────────┘  └──────────────────────┘  └────────────────────────┘
  ┌────────────────────┐  ┌──────────────────────┐
  │ EntitlementRecon.  │  │ ReviewPrompt         │
  │ which plan wins ·  │  │ when to ask          │
  │ the grant window   │  │                      │
  └────────────────────┘  └──────────────────────┘
           ▲                                            ▲
           │ used by                                    │ used by
  ┌────────┴─────────────────────┐          ┌───────────┴──────────────────┐
  │ SubscriptionStore            │          │ PremiumGate                  │
  │ @MainActor @Observable       │─────────▶│ @MainActor @Observable       │
  │ the ONLY StoreKit state      │ isPremium│ access · paywall · the        │
  │ products · entitlement ·     │          │ pending action                │
  │ purchase · restore           │          │                              │
  └──────────────────────────────┘          └───────────┬──────────────────┘
                                                        │ .environment(…)
                                                        ▼
                         every screen:  gate.require { …the write… }
```

`PremiumGate` mirrors its two inputs — `isPremium` from the store, `freeDayDate` from
`AppSettings` — rather than reaching for them. `RootView` is the one view that already has both
and keeps them current. That keeps SwiftData access in the View, where CLAUDE.md wants it, and it
makes the gate testable with no store at all.

### 16.3 `gate.require` — one word per call site

```swift
Button("Start Workout") { gate.require { start(workout) } }
```

Unlocked, it runs. Locked, it **keeps the closure**, opens the paywall, and runs it if they
subscribe — so buying Premium from a Start button starts the workout instead of returning you to
the screen to press the same button again. Dismissing the paywall drops the closure, so a
"Delete plan" you thought better of can never fire later from an unrelated paywall.

**Why the gate is at entry, not at the store.** `PlanDetailView`, `WorkoutEditorView` and
`ActiveWorkoutView` bind `@Bindable` directly to `@Model` properties — a keystroke *is* the
mutation, and two of them call `context.insert` directly, bypassing `PlanFactory`. A `save()`-
layer or factory-layer gate would be silently bypassed. So text fields are `.disabled()`,
drag-to-reorder is switched off outright (a reorder is committed by the system before any handler
could refuse it), and every action routes through a named intent that asks the gate.

### 16.4 Rules worth knowing

| Rule | Why |
|---|---|
| A first launch **after 20:00** rolls the free day to tomorrow | Installing at 23:50 would otherwise buy ten minutes |
| Access is granted **on or before** the free day | So the late installer keeps the evening that earned the roll |
| A session **started** on the free day is always finishable | It is already theirs; a workout you can see but never close is worse than the slack |
| All **three** ways back into a paused session ask `allowsFinishing` | Hero, Plan Detail's Start and the resume banner. `RootView`'s cover binding asks too — presenting that screen *is* granting every write in the logging loop, and `isOpen` is just a stored flag |
| `resetAll()` must never clear `freeDayDate` | Otherwise "Reset all data" is an infinite free trial |
| Ambient writes stay ungated | Launch backfills, badge awarding, report scheduling all operate on training that already happened |
| The coach card is hidden when locked | Every insight it produces is an instruction to go and train |

### 16.5 The StoreKit layer

Five things in `SubscriptionStore` are load-bearing, each a real bug if dropped:

1. **`Transaction.currentEntitlements` is the truth.** `Product.SubscriptionInfo.status` is
   enrichment only — it frequently returns nothing, so anything that lets it revoke entitlement
   logs paying athletes out.
2. **Refreshes are chained.** Roughly seven call sites overlap in practice; unchained they
   interleave and whichever finishes *last* wins, possibly the one that read stale entitlements.
3. **A verified purchase opens a short optimistic window** (`EntitlementReconciler`) during which
   an **empty** read cannot revoke. Without it, the purchase's own refresh reads nothing yet,
   concludes "lapsed", and writes the athlete back to free — they paid, and the app locked anyway.
   A read that *found* something stays authoritative, so refunds and downgrades still land at once.
4. **The `Transaction.updates` listener starts at launch and is never cancelled**, so renewals,
   refunds and Ask-to-Buy approvals arrive.
5. **Trial eligibility is asked, not assumed** — see the note in [§16.1](#161-the-products). This is
   the one bug in the feature that takes real money from somebody who was told it would not.

> **Refresh-on-return is critical.** Cancelling or switching inside Apple's
> `.manageSubscriptionsSheet` only flips *renewal info* — no transaction is created — so
> `Transaction.updates` never fires. `SubscriptionSection` refreshes on that sheet's dismissal and
> `ReplogApp` refreshes on `scenePhase == .active`. Remove either and Profile shows stale state
> indefinitely.

### 16.6 Legal & the review prompt

Both documents ship as **bundled markdown** (`Resources/Legal/`), rendered through
`CoachReportView`, linked from the paywall footer and from Profile → Legal. They work offline,
like the rest of the app, and cannot drift from the version the build was reviewed against.

The privacy policy is unusually short because it is true: no servers, no network requests, no
account, no analytics, no third-party SDKs. The terms lead with the training disclaimer rather
than burying it — this app prescribes specific weights to somebody it has never seen lift.

The **review prompt** is Apple's own, requested once, after three distinct days with a completed
workout, fired as the workout cover dismisses. We never show our own stars and forward only the
happy ones: guideline 1.1.7 exists to stop that, and a rating you filtered for tells you nothing.

### 16.7 Developing against it

`Configuration/Replog.storekit` defines both products locally and is set on the scheme's **Run**
action (`Edit Scheme → Run → Options → StoreKit Configuration`). It sits **outside** `Replog/` on
purpose — that folder is a synchronized root group, so anything inside it becomes a bundled
resource, and a file listing your price plan has no business inside the shipped app. It is a
`PBXFileReference` with no build-file entry, so it is in the navigator but in no target.

Test carries no reference and does not need one: every subscription suite is pure and touches no
StoreKit. Set it there too if a `StoreKitTest`-based suite is ever added.

> **Let Xcode own the scheme.** Editing `Replog.xcscheme` on disk while the project is open gets
> silently overwritten on Xcode's next save. Set it from the Edit Scheme dialog instead.

```bash
# force any access state without buying anything or waiting for midnight
SIMCTL_CHILD_REPLOG_ACCESS=locked  …   # read-only
SIMCTL_CHILD_REPLOG_ACCESS=premium …   # subscribed
SIMCTL_CHILD_REPLOG_ACCESS=freeday …   # inside the free day
```

> With the config on the **Run** action, ⌘R buys from a local fake store. Those transactions live
> in the app container, vanish when the app is deleted, and cannot be restored against the real
> App Store. Clear the reference and use a Sandbox account to exercise the real thing.

---

## 17. Design system

Warm brand over native iOS 26 controls, Liquid Glass, and `.sensoryFeedback` haptics.

### Colour tokens — dynamic, no asset catalog

```swift
Color(light: "#FBF7F2", dark: "#16120E")   // resolves per colour scheme via UIColor { traits in … }
```

| Token | Light | Dark | For |
|---|---|---|---|
| `bg` | `#FBF7F2` | `#16120E` | the warm page |
| `surface` / `surface2` | `#FFFFFF` / `#F6EFE6` | `#211B15` / `#2C241D` | cards, insets |
| `textPrimary` / `text2` / `text3` | `#2A2320` / `#8B7E72` / `#B9AEA2` | `#F6EFE7` / `#A99C8E` / `#6E635A` | the type ramp |
| `accent` / `accentPress` / `accentSoft` | `#FF6A3D` / `#E85320` / `#FFEAE0` | `#FF7A4D` / `#E0673A` / `#3A2417` | the brand orange |
| `up` / `down` | `#2FA779` / `#E5573F` | `#43C08D` / `#F0735A` | trend arrows |
| `border` / `track` | `#EFE6D9` / `#EFE6DD` | `#332A21` | hairlines, rails |

Shape tokens live in `enum Radius` (card 22 · cardLarge 26 · chip 11 · sheet 28 · pill 999), and
`.cardSurface()` is the one standard card treatment: fill + 1 pt border + a 5 %-opacity shadow.

> Tokens are **semantic, never literal** — `Color.textPrimary`, `Color.surface2`, never `Color.gray`.

### Type — SF Rounded, tuned in exactly one place

No bundled fonts. Call sites pass the spec's *semantic* emphasis (up to `.black`); the rendered
weight goes through a refined scale:

```
   .black          →  .bold       (700)      SF Rounded's counters close up at 800–900, and
   .heavy / .bold  →  .semibold   (600)      legibility research puts glanceable UI text in the
   lighter         →  unchanged              400–700 band, with hierarchy carried by SIZE.
```

The mapping is monotonic (it can never invert two call sites) and lives in `Font.rounded` alone — so
**the app's whole voice is tuned there, never per call site**. Named scale: `screenTitle` 30,
`cardTitle` 17, `bodyText` 15, `metric` 24, `bigMetric` 46. Every number and timer gets
`.tabularNumbers()`.

### Shared components

`Pill` · `LevelBadge` · `TrendArrow` · `StepperControl` · `NumericStepperField` (typeable +/- with a
keyboard-toolbar "Done") · `PrimaryButton` · `SegmentedToggle` · `SectionHeader` · `FlowLayout` ·
`Sparkline` · `SearchField` + `FilterChipRow` · `WeekStripView` · `MedalView` · `ExerciseThumbnail`.

> **Reuse, don't re-roll.** Every list thumbnail is `ExerciseThumbnail`; every raw photo is
> `ExerciseImageView`; every search field is `SearchField`.

### Two cross-cutting modifiers

**`KeyboardDismiss`** — number and decimal pads have no return key, so tapping away must always work.
Scroll containers use `.scrollDismissesKeyboard(.immediately)`; text screens use `.hideKeyboardOnTap()`
(a *simultaneous* tap gesture that never steals button taps).

**`DragToReorder`** — see the gotcha in §19. It adds *only* the drop-commit haptic and the VoiceOver
"Move up / Move down" actions, because those are the only things that can't compete for a touch.

### Sheet conventions

Dismiss-only sheets rely on the grabber and swipe-down (`.presentationDragIndicator(.visible)`) with
**no "Done" button** — `StatDetailSheet`, `AddToWorkoutSheet`. A "Done"/primary button appears only
where it actually *does* something.

---

## 18. Testing

**682 tests · 55 Swift Testing suites · 1 eval harness.** `import Testing`, no XCTest in the logic
suites, no third-party frameworks. The logic layer (`Domain` / `Models` / `Catalog` / view models) is
the coverage target at ≈80 %; SwiftUI views are **intentionally not unit-tested** — they're verified
by DEBUG-seed launches and screenshots, because layout is better judged by eye than by brittle
snapshot assertions.

| Suite | # | Covers |
|---|---:|---|
| `ProgressAnalyticsTests` | 28 | Week buckets, muscle shares, rep-range mix, adherence, PR events, load splits |
| `WeeklyReportTests` | 26 | The weekly narrative composition + `publishIfDue` idempotence |
| `StallDetectorTests` | 26 | Regression vs plateau, back-off recognition, deload→swap escalation, record-once |
| `ProgressionEngineTests` | 26 | All 6 rules + the RPE calibration path + deload snapping |
| `BodyweightLoadTests` | 23 | The crediting table, `.other` disambiguation, timed holds, exclusions |
| `BadgeEngineTests` | 23 | Every criterion's progress + `upNext` ordering |
| `BodyweightTests` | 21 | Tracker snapshot, due dates, direction & rate, one-per-day logging |
| `ActiveSessionTests` | 21 | Build → log → finish, top-set tie-breaks, pause/resume, partial finishes |
| `VolumeNarratorTests` | 19 | Count-band scoring, seed rotation, hedging unverified figures |
| `TemplateWriteBackTests` | 19 | Complete-only, upward-only, within-plan propagation, additions |
| `LoadResolverTests` | 19 | Bodyweight-at-date, rep-equivalents, external vs bodyweight volume |
| `ProgramCatalogTests` | 18 | All 62 programs decode; schema invariants hold |
| `StreakCalendarTests` · `ProgramMatcherTests` | 15 · 15 | Week strip & window · every hard gate and soft score |
| `RepSchemeTests` · `PlannerEvalTests` · `PlanScopedHistoryTests` · `LibraryFilterTests` · `CoachingLogTests` | 14 each | Rep prose parsing · persona properties · plan scoping · 6-facet AND/OR · memory writes |
| `StartingLoadEstimatorTests` | 13 | Anchors, the sex gap, experience/age scaling, every rounding floor |
| `ReorderingTests` · `QuizAnswersTests` · `OnboardingViewModelTests` · `DomainModelTests` · `CoachEngineTests` · `BadgeAwardingTests` · `AthleteContextTests` | 12 each | Reorder math · intake derivations · step machine · model invariants · insight priority · snapshot building · digest + token budget |
| `StreakEngineTests` · `PlanGeneratorTests` · `PatternMappingTests` · `CoachInsightFeedTests` | 11 each | Both streaks · the legacy split · every pattern resolves · grouping + `shouldRecord` |
| `ReadinessModulatorTests` · `NotificationPlannerTests` · `MonthlyReportTests` · `ChartDensityTests` · `CalendarDomainTests` | 10 each | Modulation & patterns · caps/quiet hours/priority · monthly rollup · the density ladder · grid math & stats |
| …and 15 more suites | 4–9 each | Persistence, catalog, calibration, formulas, `AIPlanService` fallbacks, backfills, routes, membership, trends |

### Two things that make these tests unusual

**Persistence tests are real.** They use `ReplogSchema.inMemoryContainer()` and run `@MainActor`
(models are MainActor-isolated under the project's default actor isolation) — so `SessionBuilder` →
`SessionFinisher` → `TemplateWriteBack` → streaks is exercised end-to-end against a real SwiftData
graph, not a mock.

**`PlannerEval` is a property-based eval harness, not a test file.** It builds synthetic athlete
personas (goal, equipment, injuries, and a fabricated `HistoryEntry` trail from the *real* catalog so
exIds resolve and equipment filters behave exactly as in production), then asserts the **properties
every good program must satisfy** — regardless of which specific exercises the engine picks.

> **The documented caveat, stated in the file itself:** `FoundationModels` is unavailable in the iOS
> Simulator, so these runs exercise the **deterministic** engine, not the live Apple Intelligence
> path. The properties are written to hold for *both* engines (they constrain the plan, not the
> wording), but the live model's picks must still be verified on device. The live model calls are
> deliberately untested seams.

---

## 19. Conventions & gotchas

### Naming

- **Types:** `UpperCamelCase`. Views end in `View` or name the thing they are (`ExerciseLogCard`,
  `CelebrationOverlay`). View models end in `ViewModel` / `Model`.
- **Domain services:** an `enum` namespace named for the operation, verb-first methods —
  `SessionFinisher.finish`, `WorkoutHistory.completedDays`, `PlanFactory.addExercise`.
- **Pure results:** `Generated*` for generator output, `*Row` / `*Ref` for view-local wrappers.
- **Booleans:** `is… / has… / should…` (`isOpen`, `hasReport`, `usedAppleIntelligence`).
- **Files:** one primary type per file, named after it. Tests mirror it: `Foo` → `FooTests`.

### Working agreement

- Work on **`development`**. `main` is the release line.
- **Never commit without the owner's review** of the diff.
- Build clean — **0 errors, 0 warnings** — and run the suite on **iPhone 17** before calling anything
  done.
- Numbered task lists go through the **4-pass method** (Engineer → Reviewer → QA → PM) documented in
  `CLAUDE.md`.

### The gotchas that will cost you an afternoon

**1. Never attach a custom gesture to a reorderable row.** The reorder lift is a UIKit recognizer on
the `List`'s backing collection-view cell. SwiftUI's `simultaneousGesture` composes only with
*SwiftUI* gestures — a row-level long press recognises inside the lift window, steals the touch, and
the row never lifts. Learned on device; there is also no SwiftUI hook for the lift moment on iOS 26.

**2. `List` is the only container with native reordering on iOS 26.** The
`dragContainer`/`draggable(containerItemID:)` family is `@available(iOS, unavailable)`. That's why
`WorkoutEditorView` is a `List` styled with `plainListRow`, split into header/rows/actions sections
so the drop indicator stays inside the draggable run.

**3. No `EditButton`.** Edit mode disables row content — the hidden `NavigationLink` and the Start
button both die.

**4. Never append with `collection.count`.** Use `Reordering.nextOrder(after:)`. `count` collides
after a delete and makes the `order` sort unstable.

**5. Run the backfills in order.** `SessionAttributionBackfill` **before** `TemplateBackfill`. The
template repair reads history *per plan*; without attribution every plan looks empty.

**6. Never mutate the context inside a view body.** The singletons are bootstrapped in
`ReplogApp.init` for exactly this reason — mutating during `body` thrashes rendering and can flash a
blank screen.

**7. Reps break the e1RM tie when picking a top set.** Every bodyweight set scores e1RM 0, so ranking
on e1RM alone picked an arbitrary set — a 5-rep warm-up could be recorded as the top set of a 12-rep
session, hiding a real PR.

**8. An optional-UUID comparison inside `#Predicate` is a trap.** `history(forExercise:inPlan:)`
filters in memory on purpose — it's one exercise's entries, at most one row per session.

**9. Keep every Progress link value-based.** See §14 ①.

**10. `.fill` images need `Color.clear.overlay{…}.clipShape(…)`.** See §8.

**11. `zsh` doesn't word-split a plain `$FLAGS`.** Use an array or inline the flags in the
`swiftc -typecheck` recipe.

---

## 20. Roadmap & known gaps

| # | Item | Notes |
|---|---|---|
| 0 | **Three legal placeholders must be filled before submission.** | `[SUPPORT EMAIL]`, `[DEVELOPER NAME]` and `[JURISDICTION]` in `Resources/Legal/*.md`. App Store Connect also needs a **hosted** privacy policy URL — in-app text does not satisfy it; publish the bundled copy so the two cannot disagree. |
| 1 | **`ReplogUITests` is Xcode's default stub.** | Two generated methods (`testExample`, `testLaunchPerformance`). The owner's call was no UI tests; the target exists but asserts nothing. Either delete it or make it real — right now it implies coverage that isn't there. |
| 2 | **Localization.** | 100 % hardcoded English, no `.xcstrings`. Large surface: much of the coach's copy is computed and interpolated, so it won't auto-extract from `Text("literal")`. |
| 3 | **Accessibility sweep.** | `DragToReorder` ships VoiceOver move actions and the type scale is Dynamic-Type friendly, but a full label/trait audit across 46 feature files hasn't been done. |
| 4 | **The live model paths are untested by construction.** | `FoundationModels` isn't in the simulator, so `AIPlanService.generateWithAI` and `CoachVoice.reword` are only verified on device. `PlannerEval` covers the properties; nothing covers the model's actual picks. |
| 5 | **Same-lift-two-intensities write-back.** | Documented in §10.5 — within one plan the last log wins. Needs either per-workout scoping or an explicit "this is my volume day" marker. |
| 6 | **`ProgramSlot` timed schemes ride in `reps`.** | `SetTemplate` has no duration field, so seconds are stored in `reps` behind `isTimed`. Works, but it's an encoding the model layer doesn't enforce. |
| 7 | **`ARCHITECTURE.md` predates Badges & Comparisons.** | Its folder tables don't mention `Domain/Badges/`, `Catalog/Comparisons/`, or several newer Progress screens. This README is the current map. |

---

## Data & attributions

- **Exercises + photos:** the [Free Exercise DB](https://github.com/yuhonas/free-exercise-db). The
  catalog facets (level, equipment, force, category, mechanic, primary/secondary muscles) mirror its
  `schema.json`, which is also what drives the Library filter.
- **Strength standards:** conservative untrained bands (exrx.net / StrengthLevel), rounded down.
- **Sex differences in starting strength:** Bishop et al. 1987; Miller et al. 1993.
- **Bodyweight load fractions:** Ebben et al. 2011 (JSCR); Gouvali & Boudolos 2005; Dempster / de
  Leva segment masses. Full table and citations in `PROGRESS_DESIGN.md` §3.
- **Animal strength comparisons** are largely folklore and are hedged in copy ("reportedly") rather
  than stated as fact.
