# REMEMBER — session handoff for the next fresh Claude session

Read `CLAUDE.md` and `ARCHITECTURE.md` first (they're current). This file captures what the
last session did and the gotchas that aren't obvious from the code.

## Where things stand
- Branch: **`development`**. A large **AI Personal Trainer** cycle + a follow-up bugfix landed
  here. Recent commits (newest first):
  - `9a35688` Science-based per-user starting loads + auto-calibration (replaces hardcoded weights)
  - `c865011` Test audit, docs, polish — AI PT cycle complete
  - `8705203` Smart notifications with caps + preferences
  - `0050396` Weekly/monthly narrative reports + activation/background triggers
  - `1b42f08` Readiness check-in + session modulation
  - `ee4d85c` CoachEngine: explainable post-session + pattern insights, Today card, debrief sheet
  - `7773b39` AI planner: program-driven two-stage generation + fallback + program detail UI
  - `4817a02` ProgramMatcher: gated + scored candidate selection
  - `d3f32e4` Program library: types + catalog + decoding tests
- **Build state:** app target compiles **0 errors / 0 warnings** (headless). Test target compiles;
  the only test-target warnings are a PRE-EXISTING baseline on `Trend` and `GeneratedPlan`
  (Swift-6 MainActor-`Equatable`-in-nonisolated). Do NOT try to "fix" those two by marking them
  `nonisolated` — it cascades (they reference MainActor `Color` tokens / contain non-nonisolated
  members). They predate this work.

## ⚠️ Rules that were in force (confirm they still apply before acting)
- **No-simulator rule (owner):** never boot/launch a simulator, never run the app, no screenshots.
  Verification is **compile-only, headless**:
  - App: `xcodebuild build -project Replog.xcodeproj -scheme Replog -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Tests (compile only): `xcodebuild build-for-testing … 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`
  - Do **not** run `xcodebuild test` / `simctl`. Write tests; the OWNER executes them.
- **Commit rule:** CLAUDE.md says *never commit*. For the last cycle the owner **suspended** that
  and asked for one commit per phase directly to `development`. **That override was per-task —
  assume "never commit" is back in force unless the owner says otherwise this session.**
- Commit trailer used: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

## Tests are written but NOT executed
Per the no-simulator rule, every suite was compiled but never run. `TESTPLAN.md` (repo root) lists
every suite + what it asserts. The owner runs coverage with:
```bash
xcodebuild test -project Replog.xcodeproj -scheme Replog \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -enableCodeCoverage YES -only-testing:ReplogTests
```
If a test turns out to fail on the owner's run, the likely culprits are the few assertions that
depend on exact rounding in `StartingLoadEstimator` / `LoadCalibrator` (see below) — they were
hand-computed, not machine-verified.

## Non-obvious conventions / gotchas discovered this session
- **SourceKit live diagnostics lie across files.** "Cannot find type X in scope" / "does not
  conform to Equatable" spam is cross-file indexing noise. Trust `xcodebuild`, not the inline
  diagnostics (CLAUDE.md says this too — it's very true here).
- **Project default actor isolation is MainActor.** A pure value type that's `Equatable` and gets
  compared with `#expect(a == b)` in a *nonisolated* Swift Testing test emits a Swift-6 warning.
  The fix used throughout: mark such pure value types **`nonisolated`** (e.g. `MovementPattern`,
  `ProgramMatch`, `SessionModulation`, `RepTarget`, `LoadEstimate`, …). Do the same for any new
  pure Equatable type you add and compare in tests. (Plain `String`/`Int`-raw enums don't need it.)
- **Extensions don't inherit a type's `nonisolated`.** If you mark a type `nonisolated` but its
  `Codable`/`Equatable` `init(from:)`/`encode(to:)` live in an `extension`, mark those members
  `nonisolated` too (bit me on the ProgramLibrary decoders).
- **Swift `try?` flattens optionals** — `try? decodeIfPresent(...)` is a *single* optional, not double.
- **Lenient decoding is the house style** (see `Exercise`): only truly-required fields throw; unknown
  enum-ish strings → `.other`/raw; missing optionals never fail the whole file. The 62-program
  library (`Resources/programs.json`) is decoded this way.
- **`#expect` with inline arithmetic RHS** can blow the macro type-checker ("unable to type-check
  in reasonable time"). Precompute the expected value into a `let` first.
- **`@Model` new stored properties** must have defaults (lightweight migration). Added this cycle:
  `Plan.programId/progression*`, `SetTemplate.estimated`, `HistoryEntry.topRPE`, `ReadinessEntry`.

## What's tested vs. what's a deliberate seam (verified on device, not unit-tested)
- **Fully tested (pure logic):** ProgramCatalog/decoding, ProgramMatcher, PatternMapping, RepScheme,
  ProgramPlanBuilder (incl. in-memory persistence), CoachEngine, CoachContextBuilder glue,
  ReadinessModulator, MonthlyReportComposer (+ existing WeeklyReport), NotificationPlanner,
  StartingLoadEstimator, LoadCalibrator, ProgressionEngine calibration.
- **Seams (not unit-tested):** the live FoundationModels calls in `AIPlanService`/`CoachVoice`
  (non-deterministic), and the thin OS boundaries `NotificationScheduler` (UNUserNotificationCenter)
  and `ReportScheduler`'s `BGTaskScheduler`. The BGTask needs an Info.plist
  `BGTaskSchedulerPermittedIdentifiers` entry + Background Modes to ever run — the on-activation
  path is the reliable one.

## Loose ends / things a future session might want to do
- **BGTaskScheduler Info.plist entry** isn't added (identifier `test.Replog.reportRefresh`). Reports
  still publish on app activation without it; wire the plist entry if true background refresh is wanted.
- **Notifications permission** is requested from the Profile master toggle (in-context). "First
  Finish" as an alternative opt-in point was intentionally NOT added — add it if desired.
- **Readiness check-in** is wired into the **Today** start flow only, not `PlanDetailView`'s start
  (deliberate scoping). Mirror it there if you want readiness on every start path.
- **DebugSeed** (`REPLOG_SEED=1`, DEBUG only) now seeds a stalling lift + last-week/month completed
  days + a low-sleep readiness pattern + published reports, so the Today Coach card, Profile "Coach
  Insights", and "Training Reports" are all populated for manual checks.
- Owner-facing "launch the seeded build" one-liner (they run it, not you):
  ```bash
  xcrun simctl boot "iPhone 17" 2>/dev/null; \
  xcodebuild -project Replog.xcodeproj -scheme Replog -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /tmp/replog-dd build && \
  xcrun simctl install "iPhone 17" "$(find /tmp/replog-dd -name Replog.app -path '*Debug-iphonesimulator*' | head -1)" && \
  SIMCTL_CHILD_REPLOG_SEED=1 SIMCTL_CHILD_REPLOG_TAB=profile xcrun simctl launch "iPhone 17" test.Replog
  ```
