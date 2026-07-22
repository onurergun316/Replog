# Replog — Architecture

_A guide to how Replog is structured, the patterns it uses, and **why** — written so a new engineer
(or a fresh AI session) can understand the system, extend it safely, and recognise that these choices
are the ones senior iOS teams and large product organisations converge on._

Replog is a native, **on-device-only** iOS app (SwiftUI + SwiftData, iOS 26). No backend, no network.
"Plan your training → log working sets → track progression," with an on-device Apple-Intelligence
plan generator that degrades gracefully to a deterministic generator.

---

## 1. Guiding principles

1. **A clear dependency direction.** UI depends on domain logic depends on models. Never the reverse.
2. **Push logic out of views.** SwiftUI views describe _what_ the UI looks like for a given state;
   _how_ state changes lives in view models and pure `Domain` services.
3. **Value types for logic, reference types for identity.** Pure calculations use `struct`/`enum`;
   persisted, identity-bearing entities are SwiftData `@Model` classes.
4. **Make the illegal state unrepresentable, then make the legal state testable.** Branching logic is
   isolated into pure functions so it can be unit-tested without a simulator UI.
5. **Design-system first.** Every screen is assembled from shared tokens and components, so the app
   looks like one product, not twelve.

---

## 2. The layered architecture (at a glance)

```
                 ┌───────────────────────────────────────────────┐
                 │                     App                        │  entry, RootView, tabs,
                 │  ReplogApp · RootView · MainTabView · Nav      │  environment wiring, DebugSeed
                 └───────────────────────────────────────────────┘
                                     │ composes
                                     ▼
   ┌───────────────────────────────────────────────────────────────────────────┐
   │                                Features                                     │  one folder per screen
   │  Onboarding · Today · Plans · Library · ExerciseDetail · Progress ·         │  View + feature ViewModel
   │  Profile · ActiveSession                                                    │  (@MainActor @Observable)
   └───────────────────────────────────────────────────────────────────────────┘
        │ render with                │ call (write API)              │ read
        ▼                            ▼                               ▼
   ┌─────────────────┐   ┌────────────────────────────┐   ┌────────────────────────┐
   │  DesignSystem   │   │           Domain           │   │        Catalog         │
   │  Theme, type,   │   │  Pure logic + services:    │   │  Static reference data:│
   │  components,    │   │  Formulas, StreakEngine,   │   │  Exercise, enums,      │
   │  NumericField,  │   │  PlanGenerator, Session-   │   │  ExerciseCatalog,      │
   │  KeyboardDismiss│   │  Builder/Finisher, AI/…    │   │  image loading         │
   └─────────────────┘   └────────────────────────────┘   └────────────────────────┘
                                     │ read / write
                                     ▼
                 ┌───────────────────────────────────────────────┐
                 │                    Models                      │  SwiftData @Model graph +
                 │  Plan/Workout/PlanItem/SetTemplate · Session   │  ReplogStore (schema, singletons,
                 │  UserProfile · AppSettings · HistoryEntry      │  fetch-or-create helpers)
                 └───────────────────────────────────────────────┘
```

**Rule of dependencies:** arrows only point downward. `Domain` never imports `Features`; `Models`
never import `Domain`. This keeps the compile graph acyclic and the logic layer testable in isolation.

---

## 3. What each group is, and why it's grouped that way

| Folder | Contains | Why it's its own layer |
|---|---|---|
| `App/` | `ReplogApp` (entry), `RootView` (onboarding vs main + dark mode + active-session cover), `MainTabView`, navigation destinations, `AppEnvironment`, `DebugSeed`. | Composition root. It's the only place that knows about _all_ features and wires the object graph (model container, catalog, environment). Isolating it keeps features unaware of each other. |
| `DesignSystem/` | Color tokens (`Theme`), SF-Rounded typography, reusable components (`Pill`, `StepperControl`, `NumericStepperField`, `SegmentedToggle`, `FlowLayout`, `WeekStripView`, …), cross-cutting modifiers (`KeyboardDismiss`, `DragToReorder`). | A single visual language. Components have no feature knowledge, so they're reusable and independently previewable. Changing a token restyles the whole app. |
| `Catalog/` | `Exercise` (+ lenient-decoding `Enums`), `ExerciseCatalog` (the read-only index), `ExerciseImageView`/`ExerciseThumbnail` (HEIC + cache), and `Catalog/ProgramLibrary/` (`WorkoutProgram`, `MovementPattern`, `ProgramCatalog` — the bundled 62-program library). | The **static, read-only reference datasets** (873 exercises from the Free Exercise DB + the curated program library). Separated from user data because they never mutate and load once — effectively in-memory read repositories. |
| `Models/` | SwiftData `@Model` types (the "onion") + `ReplogStore` (schema, containers, singleton fetch-or-create, `recomputeStreaks`). | The **persisted domain entities** and the persistence seams. Kept free of business rules so the schema is stable and the models are trivially serialisable. |
| `Domain/` | Pure logic & use-case services: `Formulas`, `PlanGenerator`/`PlanFactory`, `QuizAnswers`, `TrendCalculator`, `ProgressAggregator`, `ProgressionEngine`, `StallDetector`, `StreakEngine`/`StreakCalendar`, `Scheduling`, `SessionBuilder`, `SessionFinisher`, `WorkoutHistory`, `BodyweightTracker`, `Reordering`; the **AI PT** additions — `ProgramMatcher` (gated + scored program selection), `PatternMapping` (slot → catalog facets), `RepScheme` (slot rep/time parsing), `ReadinessModulator`, `WeeklyReportComposer`/`MonthlyReportComposer` + `ReportScheduler`, `NotificationPlanner`/`NotificationScheduler`; and `Domain/AI/` (`AIPlanService`, `ProgramPlanBuilder`, `CoachEngine`/`CoachContextBuilder`/`CoachVoice`, `AthleteContext`, `PlanBlueprint`, `ReportComposer`, `CoachingKnowledge`). | The **brain**. Every non-trivial rule lives here as a pure `struct`/`enum` (mostly `static` functions) so it's testable without UI and reusable across features. `Domain/AI/` isolates the model seams (planner, coach voice) — each with a deterministic fallback so the app is fully functional without Apple Intelligence. |
| `Features/` | One folder per screen: a SwiftUI `View` plus, where the screen owns real state/logic, an `@Observable` view model. | Vertical slices. Everything for a screen is co-located, so features can be built, reviewed, and reasoned about independently. |
| `Resources/` | `exercises.json` + flattened HEIC images. | Bundled assets, addressed by flat unique names (`<id>__<n>.heic`) because Xcode flattens synchronized-group resources into the bundle root. |

---

## 4. Design patterns used (and why iOS teams prefer them)

### 4.1 MV + MVVM hybrid (state-driven UI)
SwiftUI is already a reactive **Model-View** system: `@Query`, `@Bindable`, and `@Environment` bind the
view directly to state. We add a **view model only where a screen owns genuine state or logic**
(`LibraryViewModel`, `RestTimerModel`, `OnboardingViewModel`). Views that merely derive values from a
`@Query` keep those as computed properties — inventing a VM there would fight the framework.

- **SwiftData access (`@Query`/`@Bindable`) stays in the View** — Apple's guidance; view models can't
  host `@Query`. Persistence _writes_ go through the pure `Domain` services (`SessionBuilder`,
  `SessionFinisher`, `PlanFactory`), which the view/VM calls.
- **Why:** minimum ceremony, maximum testability. State machines and parsing live in `@Observable`
  types you can unit-test; glue stays in the view where SwiftUI wants it.

### 4.2 Use-case services as pure enums (`SessionFinisher`, `PlanGenerator`, `WorkoutHistory`)
Business operations are `enum` namespaces of `static` functions with explicit inputs/outputs (no hidden
state). This is the functional-core / imperative-shell pattern: a **pure core** (`Domain`) wrapped by a
thin **imperative shell** (the views that fetch/save). Pure cores are the single biggest lever for test
coverage — hence the logic layer sits ≥80%.

### 4.3 In-memory read repository (`ExerciseCatalog`)
`ExerciseCatalog` loads the dataset once, exposes `byID` lookups and `search(_:filter:)`, and is
injected via `@Environment`. This is the Repository pattern for read-only reference data: features
depend on the _interface_ (lookups/queries), not on JSON decoding.

### 4.4 Dependency injection via the SwiftUI `Environment`
The model container and catalog are provided at the composition root and read with `@Environment`.
No singletons reach into views (except the deliberately-global image cache). This makes previews and
tests trivial — inject an in-memory container (`ReplogSchema.inMemoryContainer()`) or a seeded catalog.

### 4.5 Value semantics + `@Observable`
Logic types are `struct`/`enum` (thread-safe, `Sendable`, copy-on-write). Reactive state uses the
Observation framework (`@Observable`, `@Bindable`) rather than `ObservableObject`/`@Published` — less
boilerplate, finer-grained invalidation.

### 4.6 Graceful degradation (Strategy) + program-driven planning
Planning is **program-driven**: `ProgramMatcher` (pure) ranks the bundled 62-program library
(`Catalog/ProgramLibrary/`) for the athlete via hard gates (equipment, age, sport, prerequisite,
disclaimer) + soft scoring, and `AIPlanService` runs two model stages over the shortlist — stage 1
picks one program + writes the report; stage 2 fills each program *slot* with a real catalog
exercise. `PatternMapping` (pure, tested) maps a slot's `MovementPattern` to catalog facets
(category/force/mechanic/muscles/keywords) so a slot resolves to real exercises the athlete can
perform; `ProgramPlanBuilder` (pure, tested) is the shared spine that both the model path and the
deterministic fallback use. When Apple Intelligence is unavailable it **falls back** to
`ProgramMatcher`'s top auto-pickable program built by the same slot resolver (no model), and if that
yields nothing (e.g. a program with no discrete days) to the legacy `PlanGenerator` split — same
output type, swapped strategy, flagged via `usedAppleIntelligence`.

**Slot rep/time convention** (`Domain/RepScheme.swift`, parsed into `SetTemplate` targets):
- A plain count or range (`"5"`, `"8-12"`) → the **lower bound** (start there, earn the top of the
  range, then add load — the double-progression the library favours).
- A per-side scheme (`"10/side"`, `"12-15 each"`) → the per-side count, flagged `isPerSide`.
- A time/hold/interval scheme (`"30-60s"`, `"3 min"`) → the **duration in seconds** (lower bound),
  stored in `reps` and flagged `isTimed`, since `SetTemplate` has no duration field (minutes ×60,
  clamped ≤600s). RPE is read from a slot's `intensity` (`"RPE 8"` → 8; range → the harder bound),
  else a level default. `Plan` stores the source `programId` + progression metadata for the coach
  and reports; unresolvable slots (e.g. a swim slot with no catalog match) are skipped.

### 4.7 Composition over inheritance (DesignSystem)
There are no view subclasses. Screens are composed from small components and view modifiers
(`.cardSurface()`, `.hideKeyboardOnTap()`, `ExerciseThumbnail`). Reuse happens by composition, which is
how idiomatic SwiftUI scales.

---

## 5. Data flow (one representative loop: logging a set)

```
   User taps a set  ─────────────────────────────────────────────┐
        │                                                         │
        ▼                                                         │
  ExerciseLogCard (View)  ── onCheck ──▶  ActiveWorkoutView       │
        │                                    │ toggle(set)        │
        │                                    ▼                    │
        │                         mutate LoggedSet.done (Model)   │  SwiftData
        │                                    │                    │  persists +
        │                                    ├─ RestTimerModel.start(…)   republishes
        │                                    └─ context.save()    │
        ▼                                                         ▼
  view re-renders from the new @Query/@Bindable state  ◀──────────┘
        │
        └─ when session.isComplete → CelebrationOverlay + haptics
```

**Finishing** calls `SessionFinisher.finish(...)` (a pure Domain service): it writes `HistoryEntry`
rows, updates the streaks via `context.recomputeStreaks` (→ `StreakEngine`), and deletes the session.
The flow is effectively unidirectional: intent → Domain/Model mutation → SwiftData republish → re-render.

---

## 6. The persisted "onion" (Models)

```
 Plan ──< Workout ──< PlanItem(exId, restSeconds?) ──< SetTemplate {weightKg, reps, rpe}
                                     │
 (live logging)                     │ SessionBuilder.start copies the template →
                                     ▼
 ActiveSession(isOpen) ──< SessionExercise(exId, restSeconds?) ──< LoggedSet {done, prev…}
                                     │ SessionFinisher.finish on a complete workout
                                     ▼
 HistoryEntry(exId, date, topW/topR, e1rm, setsJSON)   ← drives Progress + next session's "previous"

 Singletons: UserProfile (name, goal, streak, weekStreak, doneDates, totalWorkouts)
             AppSettings (units, darkMode, restTimerAuto, restSeconds)
```

`PlanItem`/`SetTemplate` are the **template**; `SessionExercise`/`LoggedSet` are the **live instance**;
`HistoryEntry` is the **immutable record**. Templates reference the static catalog only by `exId` — user
data and reference data are decoupled, so the catalog can be rebuilt/re-tuned without migrations.

---

## 7. Naming conventions

- **Types:** `UpperCamelCase`. Views end in `View` (`LibraryView`) or name the thing they are
  (`ExerciseLogCard`, `CelebrationOverlay`). View models end in `ViewModel`/`Model`
  (`LibraryViewModel`, `RestTimerModel`).
- **Domain services:** an `enum` namespace named for the operation, verb-first methods
  (`SessionFinisher.finish`, `WorkoutHistory.completedDays`, `PlanFactory.addExercise`).
- **Pure value results:** `Generated*` for generator output, `*Row`/`*Ref` for view-local wrappers.
- **Booleans:** `is…/has…/should…` (`isOpen`, `hasReport`, `usedAppleIntelligence`).
- **Files:** one primary type per file, file named after it. Tests mirror the type: `Foo` → `FooTests`.
- **DesignSystem tokens:** semantic, not literal (`Color.textPrimary`, `Color.accent`, `Color.surface2`
  — never `Color.gray`), so theming is centralised.

---

## 8. Testing strategy

- **Framework:** Swift Testing (`import Testing`) in `ReplogTests/`.
- **Target:** the logic layer (`Domain`/`Models`/`Catalog`/view models) is covered ≥80%; SwiftUI views
  are intentionally **not** unit-tested — they're verified by DEBUG-seed launches + screenshots.
- **Persistence/session tests** use `ReplogSchema.inMemoryContainer()` and run `@MainActor` (models are
  MainActor-isolated under the project's default actor isolation).
- **Why this split:** pure functions give deterministic, millisecond tests with real coverage; view
  layout is better judged by eye than by brittle snapshot assertions.

---

## 9. Why this is the industry-standard shape

- **Layered + acyclic dependencies** (UI → Domain → Models) is the backbone of Clean Architecture /
  the "functional core, imperative shell" idea taught across the Apple ecosystem (Apple's own
  _Scrumdinger_ / _Fruta_ / _Backyard Birds_ sample apps use exactly this feature-folder + design-system
  + models split).
- **MV-with-selective-VMs** is where the SwiftUI community landed after the early "MVVM everywhere"
  phase: keep `@Query`/state in views, extract view models only for real logic. Apple's Observation
  framework was built for this.
- **Pure use-case services + value types** mirror how teams at scale (e.g. large fintech/health apps)
  isolate business rules to hit high test coverage without slow UI tests — the same instinct behind
  Point-Free's "functional core" and Uber/Airbnb-style domain layering.
- **Repository for reference data + DI via Environment** is standard for testability and previewability;
  it's what makes SwiftUI previews and in-memory test containers cheap.
- **Design-system-first** is how every serious product team (Apple HIG, Airbnb DLS, Shopify Polaris,
  Uber Base) ships a consistent UI at scale.

The throughline: **a new engineer can open one `Features/<Screen>` folder and be productive, trusting
that shared concerns already live in `DesignSystem`, rules in `Domain`, and data in `Models`.** That
predictability — not any single clever abstraction — is what makes a codebase feel professional.
